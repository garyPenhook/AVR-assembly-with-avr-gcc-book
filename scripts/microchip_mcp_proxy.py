#!/usr/bin/env python3
"""Stdio MCP proxy for Microchip's HTTP/SSE MCP endpoint.

Cursor launches local MCP servers over stdio. Microchip exposes its ProductInfo
MCP server over HTTPS, so this bridge keeps stdio framing local and forwards
JSON-RPC messages to the remote endpoint.

Microchip returns most JSON-RPC replies as a short ``text/event-stream`` body
(``event: message`` + single ``data:`` line). Some notifications get HTTP 202
with an empty body and must not produce a stdio reply.

Streamable HTTP (MCP) expects ``MCP-Protocol-Version`` on outbound POSTs; we set
it from each ``initialize`` request's ``params.protocolVersion``, then keep that
value for the rest of the session (override with env ``MCP_PROTOCOL_VERSION``).
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from typing import Any

MICROCHIP_MCP_URL = os.environ.get(
    "MICROCHIP_MCP_URL", "https://api.microchip.com/mcp/resources"
)
USER_AGENT = os.environ.get("MICROCHIP_MCP_USER_AGENT", "asm-book-microchip-mcp/0.2")
REQUEST_TIMEOUT = float(os.environ.get("MICROCHIP_MCP_TIMEOUT", "120"))

_session_id: str | None = None
_protocol_version: str = os.environ.get("MCP_PROTOCOL_VERSION", "2024-11-05")


def _log(message: str) -> None:
    print(f"[microchip-mcp] {message}", file=sys.stderr, flush=True)


def _update_protocol_version(message: dict[str, Any]) -> None:
    """Mirror the client's initialize protocol version into outbound headers."""
    global _protocol_version
    if message.get("method") != "initialize":
        return
    params = message.get("params")
    if not isinstance(params, dict):
        return
    pv = params.get("protocolVersion")
    if isinstance(pv, str) and pv.strip():
        _protocol_version = pv.strip()


def _read_message() -> dict[str, Any] | None:
    """Read one Content-Length framed JSON-RPC message from stdin."""
    headers: dict[str, str] = {}

    while True:
        line = sys.stdin.buffer.readline()
        if line == b"":
            return None

        if line in (b"\r\n", b"\n"):
            break

        text = line.decode("utf-8", "replace")

        name, sep, value = text.partition(":")
        if sep:
            headers[name.strip().lower()] = value.strip()

    try:
        content_length = int(headers["content-length"])
    except (KeyError, ValueError):
        _log("received message without a valid Content-Length header")
        return None

    body = sys.stdin.buffer.read(content_length)
    if len(body) != content_length:
        _log("short read on stdin Content-Length body")
        return None

    try:
        return json.loads(body.decode("utf-8"))
    except json.JSONDecodeError as exc:
        _log(f"invalid JSON in stdin body: {exc}")
        return None


def _write_message(message: dict[str, Any]) -> None:
    body = json.dumps(message, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()


def _parse_sse(body: str) -> dict[str, Any] | None:
    """Parse MCP-style SSE: one or more events separated by blank lines.

    Each event may contain multiple ``data:`` lines (joined with ``\\n`` per SSE).
    Returns the last successfully parsed JSON object (Microchip sends one).
    """
    text = body.replace("\r\n", "\n").replace("\r", "\n")
    blocks = [b for b in text.split("\n\n") if b.strip()]
    if not blocks and text.strip():
        blocks = [text]

    last_obj: dict[str, Any] | None = None
    for block in blocks:
        block = block.strip()
        if not block:
            continue
        data_parts: list[str] = []
        for raw_line in block.split("\n"):
            line = raw_line.strip()
            if not line or line.startswith(":"):
                continue
            low = line.lower()
            if low.startswith("data:"):
                data_parts.append(line.split(":", 1)[1].lstrip())
        if not data_parts:
            continue
        payload = "\n".join(data_parts)
        try:
            obj = json.loads(payload)
        except json.JSONDecodeError:
            _log("SSE data: payload is not valid JSON")
            continue
        if isinstance(obj, dict):
            last_obj = obj
    return last_obj


def _json_rpc_error(req_id: Any, code: int, message: str) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": code, "message": message},
    }


def _drain_response(response: Any) -> None:
    try:
        response.read()
    except Exception:
        pass


def _remote_request(message: dict[str, Any]) -> dict[str, Any] | None:
    """Forward a JSON-RPC message to Microchip and return the JSON-RPC response.

    Returns ``None`` when the upstream response correctly has no JSON body
    (HTTP 202 for notifications). For requests that include ``id``, never
    returns ``None`` — use a synthetic JSON-RPC error if the wire response is
    unusable so the MCP client does not hang.
    """
    global _session_id

    _update_protocol_version(message)

    payload = json.dumps(message, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    headers = {
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT,
        "Connection": "close",
        "MCP-Protocol-Version": _protocol_version,
    }
    if _session_id:
        headers["Mcp-Session-Id"] = _session_id

    request = urllib.request.Request(
        MICROCHIP_MCP_URL, data=payload, headers=headers, method="POST"
    )

    needs_stdio_reply = "id" in message

    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            session_id = response.headers.get("Mcp-Session-Id")
            if session_id:
                _session_id = session_id

            status = getattr(response, "status", None) or response.getcode()

            if status == 202:
                _drain_response(response)
                if needs_stdio_reply:
                    return _json_rpc_error(
                        message["id"],
                        -32000,
                        "Microchip MCP returned HTTP 202 for a message that includes "
                        "an 'id' field; expected JSON or SSE for JSON-RPC requests.",
                    )
                return None

            body_bytes = response.read()
            body = body_bytes.decode("utf-8", "replace")
            content_type = response.headers.get("Content-Type", "")

    except urllib.error.HTTPError as exc:
        err_body = exc.read().decode("utf-8", "replace")
        if needs_stdio_reply:
            return _json_rpc_error(
                message["id"],
                -32000,
                f"Microchip MCP HTTP {exc.code}: {err_body or exc.reason}",
            )
        return None
    except Exception as exc:  # noqa: BLE001 - convert transport errors to JSON-RPC
        if needs_stdio_reply:
            return _json_rpc_error(
                message["id"], -32000, f"Microchip MCP request failed: {exc}"
            )
        return None

    parsed: dict[str, Any] | None = None
    if "text/event-stream" in content_type.lower():
        parsed = _parse_sse(body)
    elif body.strip():
        try:
            loaded = json.loads(body)
            parsed = loaded if isinstance(loaded, dict) else None
        except json.JSONDecodeError:
            parsed = None

    if parsed is None and needs_stdio_reply:
        snippet = body.strip()[:500]
        return _json_rpc_error(
            message["id"],
            -32000,
            "Microchip MCP proxy: could not parse JSON-RPC from response "
            f"(Content-Type={content_type!r}, body={snippet!r}).",
        )

    return parsed


def main() -> int:
    while True:
        message = _read_message()
        if message is None:
            return 0

        if not isinstance(message, dict):
            _log("ignoring non-object JSON-RPC root")
            continue

        response = _remote_request(message)

        # JSON-RPC notifications omit ``id`` and must not receive a reply.
        if "id" not in message:
            continue

        if response is None:
            _log("internal error: missing JSON-RPC response for a request with id")
            continue

        _write_message(response)


if __name__ == "__main__":
    raise SystemExit(main())
