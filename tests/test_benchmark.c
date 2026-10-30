#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include <x86intrin.h>

extern void init_renderer_luts(void);
extern void editor_init(void);
extern int file_create_scratch(void);
extern void editor_render(void);

extern uint32_t win_w;
extern uint32_t win_h;
extern void *fb_data;
extern uint32_t fb_pitch;

int main() {
    printf("========================================================\n");
    printf("  AsmHex Performance & Throughput Benchmark\n");
    printf("========================================================\n");

    init_renderer_luts();
    file_create_scratch();
    editor_init();

    win_w = 1040;
    win_h = 720;
    fb_pitch = 1040 * 4;
    fb_data = malloc(1040 * 720 * 4);

    // Warm up
    editor_render();

    int iterations = 1000;
    uint64_t start_cycles = __rdtsc();
    struct timespec start_time, end_time;
    clock_gettime(CLOCK_MONOTONIC, &start_time);

    for (int i = 0; i < iterations; i++) {
        editor_render();
    }

    uint64_t end_cycles = __rdtsc();
    clock_gettime(CLOCK_MONOTONIC, &end_time);

    uint64_t total_cycles = end_cycles - start_cycles;
    double elapsed_sec = (end_time.tv_sec - start_time.tv_sec) + 
                         (end_time.tv_nsec - start_time.tv_nsec) / 1e9;

    double fps = iterations / elapsed_sec;
    double ms_per_frame = (elapsed_sec * 1000.0) / iterations;
    uint64_t cycles_per_frame = total_cycles / iterations;

    printf("  Frames rendered:     %d\n", iterations);
    printf("  Elapsed time:        %.4f seconds\n", elapsed_sec);
    printf("  Average frame time:  %.3f ms\n", ms_per_frame);
    printf("  Cycles per frame:    %lu CPU cycles\n", cycles_per_frame);
    printf("  Rendering Speed:     %.1f FPS\n", fps);
    printf("========================================================\n");

    free(fb_data);
    return 0;
}
