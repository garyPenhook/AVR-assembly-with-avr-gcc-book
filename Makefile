PDF_DIR := book/output/pdf
PDF_NAME := avr-assembly-programming
# Book revision label (for release notes / tags only; the repo ships one PDF).
PDF_VERSION := v1.4.8.2
PDF_OUTPUT := $(PDF_DIR)/$(PDF_NAME).pdf
PDF_LOG := $(PDF_DIR)/build.log

SHELL := /bin/bash

CHAPTERS := \
	book/ch01_intro/ch01.md \
	book/ch01a_number_systems/ch01a.md \
	book/ch02_arch/ch02.md \
	book/ch03_syntax/ch03.md \
	book/ch03a_gdb_debugging/ch03a.md \
	book/ch04_isa/ch04.md \
	book/ch05_loadstore/ch05.md \
	book/ch05a_unsigned_arith/ch05a.md \
	book/ch05b_signed_arith/ch05b.md \
	book/ch05c_multibyte_arith/ch05c.md \
	book/ch05d_bit_math/ch05d.md \
	book/ch05e_fixed_point/ch05e.md \
	book/ch06_arith/ch06.md \
	book/ch07_branches/ch07.md \
	book/ch08_subroutines/ch08.md \
	book/ch09_gpio/ch09.md \
	book/ch10_interrupts/ch10.md \
	book/ch10a_power_clock/ch10a.md \
	book/ch11_timer/ch11.md \
	book/ch12_usart/ch12.md \
	book/ch13_spi_twi/ch13.md \
	book/ch14_c_asm/ch14.md \
	book/ch15_optimisation/ch15.md \
	book/ch16a_updi/ch16a.md \
	book/ch16_bootloader/ch16.md \
	book/ch17_bitmath/ch17.md \
	book/ch18_realtime/ch18.md \
	book/ch18a_dds/ch18a.md \
	book/ch19_cordic/ch19.md \
	book/ch20_adc/ch20.md \
	book/ch20a_filters/ch20a.md \
	book/appendices/appendix_a_registers.md \
	book/appendices/appendix_b_instruction_set.md \
	book/appendices/appendix_c_gas_directives.md \
	book/appendices/appendix_d_linker_script.md \
	book/appendices/appendix_e_avrdude.md \
	book/appendices/appendix_f_inspecting_binaries.md

PANDOC_FLAGS := \
	--from markdown+smart \
	--toc \
	--toc-depth=3 \
	--number-sections \
	--syntax-highlighting=tango \
	--include-in-header=book/toc-format.tex \
	--include-in-header=book/pdf-preamble.tex \
	--pdf-engine=xelatex \
	--pdf-engine-opt=-interaction=nonstopmode \
	--pdf-engine-opt=-file-line-error \
	--pdf-engine-opt=-halt-on-error \
	-V documentclass=book \
	-V classoption=oneside \
	-V geometry:margin=1in \
	-V geometry:paper=a4paper \
	-V colorlinks=true \
	-V linkcolor=blue \
	-V urlcolor=blue \
	-V toccolor=black \
	-V hyperrefoptions=bookmarksopen=true,bookmarksopenlevel=1 \
	-V mainfont="DejaVu Serif" \
	-V sansfont="DejaVu Sans" \
	-V monofont="DejaVu Sans Mono" \
	-V title="AVR Assembly Programming" \
	-V author="Dazed\\_N\\_Confused; ChatGPT for datasheet/app-note extraction and typing help"

.PHONY: pdf clean-pdf

pdf: $(PDF_OUTPUT)

$(PDF_OUTPUT): $(CHAPTERS) book/toc-format.tex book/pdf-preamble.tex | $(PDF_DIR)
	set -o pipefail; pandoc $(CHAPTERS) $(PANDOC_FLAGS) -o $@ 2>&1 | tee $(PDF_LOG)
	-command -v pdfinfo >/dev/null 2>&1 && pdfinfo $@ >> $(PDF_LOG) 2>&1

$(PDF_DIR):
	mkdir -p $@

clean-pdf:
	rm -f $(PDF_OUTPUT) $(PDF_LOG)
