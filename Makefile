PDF_DIR := book/output/pdf
PDF_NAME := avr-assembly-programming
PDF_VERSION := v1.6
PDF_VERSIONED := $(PDF_DIR)/$(PDF_NAME)-$(PDF_VERSION).pdf
PDF_LATEST := $(PDF_DIR)/$(PDF_NAME).pdf
PDF_LOG := $(PDF_DIR)/build-$(PDF_VERSION).log

CHAPTERS := \
	book/ch01_intro/ch01.md \
	book/ch02_arch/ch02.md \
	book/ch03_syntax/ch03.md \
	book/ch03a_gdb_debugging/ch03a.md \
	book/ch04_isa/ch04.md \
	book/ch05_loadstore/ch05.md \
	book/ch06_arith/ch06.md \
	book/ch07_branches/ch07.md \
	book/ch08_subroutines/ch08.md \
	book/ch09_gpio/ch09.md \
	book/ch10_interrupts/ch10.md \
	book/ch11_timer/ch11.md \
	book/ch12_usart/ch12.md \
	book/ch13_spi_twi/ch13.md \
	book/ch14_c_asm/ch14.md \
	book/ch15_optimisation/ch15.md \
	book/ch16_bootloader/ch16.md \
	book/ch17_bitmath/ch17.md \
	book/ch18_realtime/ch18.md \
	book/ch19_cordic/ch19.md \
	book/ch20_adc/ch20.md \
	book/appendices/appendix_a_registers.md \
	book/appendices/appendix_b_instruction_set.md \
	book/appendices/appendix_c_gas_directives.md \
	book/appendices/appendix_d_linker_script.md \
	book/appendices/appendix_e_avrdude.md

PANDOC_FLAGS := \
	--from markdown+smart \
	--toc \
	--number-sections \
	--syntax-highlighting=tango \
	--include-in-header=book/toc-format.tex \
	--pdf-engine=xelatex \
	-V documentclass=book \
	-V geometry:margin=1in \
	-V colorlinks=true \
	-V linkcolor=blue \
	-V urlcolor=blue \
	-V toccolor=black \
	-V mainfont="DejaVu Serif" \
	-V sansfont="DejaVu Sans" \
	-V monofont="DejaVu Sans Mono" \
	-V title="AVR Assembly Programming" \
	-V author="Dazed\\_N\\_Confused; ChatGPT for datasheet/app-note extraction and typing help"

.PHONY: pdf clean-pdf

pdf: $(PDF_VERSIONED)
	cp $(PDF_VERSIONED) $(PDF_LATEST)

$(PDF_VERSIONED): $(CHAPTERS) book/toc-format.tex | $(PDF_DIR)
	pandoc $(CHAPTERS) $(PANDOC_FLAGS) -o $@

$(PDF_DIR):
	mkdir -p $@

clean-pdf:
	rm -f $(PDF_VERSIONED) $(PDF_LATEST) $(PDF_LOG)
