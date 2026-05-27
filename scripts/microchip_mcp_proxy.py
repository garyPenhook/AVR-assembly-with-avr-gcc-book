#!/usr/bin/env python3
"""Stdio MCP proxy for Microchip's HTTP/SSE MCP endpoint.

Cursor launches local MCP servers over stdio. Microchip exposes its ProductInfo
MCP server over HTTPS, so this bridge keeps stdio framing local and forwards
JSON-RPC messages to the remote endpoint.
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
USER_AGENT = os.environ.get("MICROCHIP_MCP_USER_AGENT", "asm-book-microchip-mcp/0.1")

_session_id: str | None = None


def _log(message: str) -> None:
    print(f"[microchip-mcp] {message}", file=sys.stderr, flush=True)


def _read_message() -> dict[str, Any] | None:
    """Read one Content-Length framed JSON-RPC message from stdin."""
    headers: dict[str, str] = {}

    while True:
        line = sys.stdin.buffer.readline()
        if line == b"":
            return None

        if line in (b"\r\n", b"\n"):
            break

        name, sep, value = line.decode("ascii", "replace").partition(":")
        if sep:
            headers[name.strip().lower()] = value.strip()

    try:
        content_length = int(headers["content-length"])
    except (KeyError, ValueError):
        _log("received message without a valid Content-Length header")
        return None

    body = sys.stdin.buffer.read(content_length)
    if not body:
        return None

    return json.loads(body.decode("utf-8"))


def _write_message(message: dict[str, Any]) -> None:
    body = json.dumps(message, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()


def _parse_sse(body: str) -> dict[str, Any] | None:
    data_lines: list[str] = []

    for line in body.splitlines():
        if line.startswith("data:"):
            data_lines.append(line[5:].lstrip())
        elif line == "" and data_lines:
            break

    if not data_lines:
        return None

    return json.loads("\n".join(data_lines))


def _remote_request(message: dict[str, Any]) -> dict[str, Any] | None:
    """Forward a JSON-RPC message to Microchip and return the JSON-RPC response."""
    global _session_id

    payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
    headers = {
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT,
    }
    if _session_id:
        headers["Mcp-Session-Id"] = _session_id

    request = urllib.request.Request(
        MICROCHIP_MCP_URL, data=payload, headers=headers, method="POST"
    )

    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            session_id = response.headers.get("Mcp-Session-Id")
            if session_id:
                _session_id = session_id

            if response.status == 202:
                return None

            body = response.read().decode("utf-8", "replace")
            content_type = response.headers.get("Content-Type", "")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        return {
            "jsonrpc": "2.0",
            "id": message.get("id"),
            "error": {
                "code": -32000,
                "message": f"Microchip MCP HTTP {exc.code}: {body or exc.reason}",
            },
        }
    except Exception as exc:  # noqa: BLE001 - convert transport errors to JSON-RPC
        return {
            "jsonrpc": "2.0",
            "id": message.get("id"),
            "error": {
                "code": -32000,
                "message": f"Microchip MCP request failed: {exc}",
            },
        }

    if "text/event-stream" in content_type:
        return _parse_sse(body)

    if body.strip():
        return json.loads(body)

    return None


def main() -> int:
    while True:
        try:
            message = _read_message()
        except json.JSONDecodeError as exc:
            _log(f"invalid JSON-RPC message: {exc}")
            return 1

        if message is None:
            return 0

        response = _remote_request(message)
        if response is not None and "id" in message:
            _write_message(response)


if __name__ == "__main__":
    raise SystemExit(main())
