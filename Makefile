# ==============================================================================
# AsmHex - Ultra-Fast Pure x86_64 Assembly Hexadecimal File Viewer & Editor
# Makefile
# ==============================================================================

NASM          := nasm
CC            := gcc
NASMFLAGS     := -f elf64 -F dwarf -g -Isrc/include/ -I.
LDFLAGS       := -no-pie -lX11 -lXext

# Windows 64-bit Cross-Compilation Toolchain
WIN_CC        := x86_64-w64-mingw32-gcc
WIN_NASMFLAGS := -f win64 -DOS_WINDOWS -Isrc/include/ -I.
WIN_CFLAGS    := -O2 -Wall -fno-asynchronous-unwind-tables
WIN_LDFLAGS   := -lgdi32 -luser32 -lshell32
WIN_BIN       := asmhex.exe

BUILD_DIR     := build
BIN           := asmhex

SRCS          := src/renderer.asm src/file_io.asm src/editor.asm src/x11_shm.asm src/hash.asm src/main.asm
OBJS          := $(patsubst src/%.asm, $(BUILD_DIR)/%.o, $(SRCS))
LIB_OBJS      := $(BUILD_DIR)/renderer.o $(BUILD_DIR)/file_io.o $(BUILD_DIR)/editor.o $(BUILD_DIR)/x11_shm.o $(BUILD_DIR)/hash.o

WIN_CORE_OBJS := $(BUILD_DIR)/renderer_win64.obj $(BUILD_DIR)/editor_win64.obj $(BUILD_DIR)/hash_win64.obj
WIN_HOST_OBJ  := $(BUILD_DIR)/win32_host.obj

.PHONY: all clean run test benchmark win64 test-win64

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

# Windows 64-bit Targets
win64: $(WIN_BIN)

$(BUILD_DIR)/%_win64.obj: src/%.asm font.bin | $(BUILD_DIR)
	$(NASM) $(WIN_NASMFLAGS) $< -o $@

$(WIN_HOST_OBJ): src/platform/win32/win32_host.c | $(BUILD_DIR)
	$(WIN_CC) $(WIN_CFLAGS) -c $< -o $@

$(WIN_BIN): $(WIN_CORE_OBJS) $(WIN_HOST_OBJ)
	$(WIN_CC) $(WIN_CFLAGS) $^ $(WIN_LDFLAGS) -o $@
	@echo "==========================================================="
	@echo "  Built $(WIN_BIN) successfully! Windows 64-bit binary."
	@echo "==========================================================="

test: $(BIN)
	@echo "Building and running unit & integration test suite..."
	$(CC) -O2 tests/test_suite.c $(LIB_OBJS) $(LDFLAGS) -o $(BUILD_DIR)/test_suite
	./$(BUILD_DIR)/test_suite

test-win64: $(WIN_BIN) $(BIN)
	@echo "==========================================================="
	@echo "  Running AsmHex Windows 64-bit Test Suite under Wine..."
	@echo "==========================================================="
	@echo "[TEST 1] Testing Windows 64-bit blank buffer launch & screenshot..."
	wine ./$(WIN_BIN) --screenshot $(BUILD_DIR)/win64_test_blank.ppm
	@test -f $(BUILD_DIR)/win64_test_blank.ppm && echo "  -> Win64 Blank buffer rendered & exported successfully."
	@echo "[TEST 2] Testing Windows 64-bit file viewing & rendering..."
	wine ./$(WIN_BIN) --screenshot $(BUILD_DIR)/win64_test_file.ppm $(WIN_BIN)
	@test -f $(BUILD_DIR)/win64_test_file.ppm && echo "  -> Win64 File view rendered & exported successfully."
	@echo "[TEST 3] Testing Windows 64-bit Multi-File Tabbed Diff Mode..."
	wine ./$(WIN_BIN) --screenshot $(BUILD_DIR)/win64_test_diff.ppm --diff $(WIN_BIN) $(BIN)
	@test -f $(BUILD_DIR)/win64_test_diff.ppm && echo "  -> Win64 Tabbed Diff view rendered & exported successfully."
	@echo "==========================================================="
	@echo "  ALL WINDOWS 64-BIT TESTS PASSED WITH 100% SUCCESS!"
	@echo "==========================================================="

test-live: $(BIN)
	@echo "Building and running live X11 resize test..."
	$(CC) -O2 tests/test_resize_live.c $(LIB_OBJS) $(LDFLAGS) -o $(BUILD_DIR)/test_resize_live
	./$(BUILD_DIR)/test_resize_live

benchmark: $(BIN)
	@echo "Building and running rendering benchmark..."
	$(CC) -O2 tests/test_benchmark.c $(LIB_OBJS) $(LDFLAGS) -o $(BUILD_DIR)/test_benchmark
	./$(BUILD_DIR)/test_benchmark

run: $(BIN)
	./$(BIN)

clean:
	rm -rf $(BUILD_DIR) $(BIN) $(WIN_BIN) *.ppm *.png /tmp/asmhex_test.dat

