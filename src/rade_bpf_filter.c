/*---------------------------------------------------------------------------*\

  rade_bpf_filter.c

  Standalone BPF filter: reads IQ f32 from stdin in chunks, applies the
  V2 BPF, writes filtered IQ f32 to stdout.  Useful for listening to the
  BPF output (pipe through sox) to check for clicking/buffer-edge artefacts.

  Usage:
    cat signal.f32 | ./rade_bpf_filter [chunk_size] > filtered.f32
    sox -t f32 -r 8000 -c 2 filtered.f32 filtered.wav

  chunk_size defaults to 160 (V2 sym_len).  Try 120 and 200 to exercise
  the sizes that timing_adj produces.

\*---------------------------------------------------------------------------*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "rade_bpf.h"
#include "rade_dsp.h"

#define FS          8000
#define BANDWIDTH   974.999942f
#define CENTRE      1468.750067f
#define NTAP        101
#define MAX_CHUNK   (160 + 40 + NTAP)  /* sym_len + timing_shift margin */

int main(int argc, char *argv[]) {
    int chunk = (argc >= 2) ? atoi(argv[1]) : 160;
    if (chunk <= 0 || chunk > MAX_CHUNK) {
        fprintf(stderr, "rade_bpf_filter: chunk_size must be 1..%d\n", MAX_CHUNK);
        return 1;
    }
    fprintf(stderr, "rade_bpf_filter: BPF bw=%.1f Hz centre=%.1f Hz ntap=%d chunk=%d\n",
            BANDWIDTH, CENTRE, NTAP, chunk);

    rade_bpf bpf;
    rade_bpf_init(&bpf, NTAP, (float)FS, BANDWIDTH, CENTRE, chunk);

    RADE_COMP in[MAX_CHUNK], out[MAX_CHUNK];
    size_t n;
    while ((n = fread(in, sizeof(RADE_COMP), chunk, stdin)) > 0) {
        if ((int)n < chunk)
            memset(&in[n], 0, (chunk - n) * sizeof(RADE_COMP));
        rade_bpf_process(&bpf, out, in, chunk);
        fwrite(out, sizeof(RADE_COMP), n, stdout);
    }
    return 0;
}
