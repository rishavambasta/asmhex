# ==============================================================================
# AsmHex - Ultra-Fast Pure x86_64 Assembly Hexadecimal File Viewer & Editor
# Makefile
# ==============================================================================

NASM      := nasm
CC        := gcc
NASMFLAGS := -f elf64 -F dwarf -g -Isrc/include/ -I.
LDFLAGS   := -no-pie -lX11 -lXext

BUILD_DIR := build
BIN       := asmhex

SRCS      := src/renderer.asm src/file_io.asm src/editor.asm src/x11_shm.asm src/main.asm
OBJS      := $(patsubst src/%.asm, $(BUILD_DIR)/%.o, $(SRCS))
LIB_OBJS  := $(BUILD_DIR)/renderer.o $(BUILD_DIR)/file_io.o $(BUILD_DIR)/editor.o $(BUILD_DIR)/x11_shm.o

.PHONY: all clean run test benchmark

all: $(BIN)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/%.o: src/%.asm font.bin | $(BUILD_DIR)
	$(NASM) $(NASMFLAGS) $< -o $@

$(BIN): $(OBJS)
	$(CC) $(OBJS) $(LDFLAGS) -o $@
	@echo "==========================================================="
	@echo "  Built $(BIN) successfully! Pure x86_64 Assembly binary."
	@echo "==========================================================="

test: $(BIN)
	@echo "Building and running unit & integration test suite..."
	$(CC) -O2 tests/test_suite.c $(LIB_OBJS) $(LDFLAGS) -o $(BUILD_DIR)/test_suite
	./$(BUILD_DIR)/test_suite

benchmark: $(BIN)
	@echo "Building and running rendering benchmark..."
	$(CC) -O2 tests/test_benchmark.c $(LIB_OBJS) $(LDFLAGS) -o $(BUILD_DIR)/test_benchmark
	./$(BUILD_DIR)/test_benchmark

run: $(BIN)
	./$(BIN)

clean:
	rm -rf $(BUILD_DIR) $(BIN) *.ppm screenshot.png sample_elf.png /tmp/asmhex_test.dat

