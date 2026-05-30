# Makefile - a small multi-file AVR assembly project (Chapter 28)
MCU     := attiny3217
SRCS    := main.S vec.S
OBJS    := $(SRCS:.S=.o)
TARGET  := app

# Flags: -e main sets the entry symbol (no C runtime); --gc-sections drops
# unreferenced sections; -Map writes the link map for inspection.
ASFLAGS := -mmcu=$(MCU)
LDFLAGS := -mmcu=$(MCU) -nostartfiles -e main \
           -Wl,--gc-sections,-Map,$(TARGET).map

.PHONY: all clean size
all: $(TARGET).hex

# pattern rule: each .S -> .o (separate compilation)
%.o: %.S
	avr-gcc $(ASFLAGS) -c $< -o $@

# link the objects into an ELF
$(TARGET).elf: $(OBJS)
	avr-gcc $(LDFLAGS) $^ -o $@

# flashable Intel HEX (reproducible artifact: no ELF timestamps/paths)
$(TARGET).hex: $(TARGET).elf
	avr-objcopy -O ihex $< $@

size: $(TARGET).elf
	avr-size $<

clean:
	rm -f $(OBJS) $(TARGET).elf $(TARGET).hex $(TARGET).map
