/*---------------------------------------------------------------------------*\

  radae_rx.c

  RADAE streaming receiver.
  Reads IQ samples from stdin, writes features to stdout.

\*---------------------------------------------------------------------------*/

/*
  Copyright (C) 2024 David Rowe

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions
  are met:

  - Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.

  - Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
  ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
  A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR
  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>

#include "rade_api.h"
#include "rade_dsp.h"

void usage(void) {
    fprintf(stderr, "usage: radae_rx [options]\n");
    fprintf(stderr, "  -h, --help              Show this help\n");
    fprintf(stderr, "  --model_name FILE       Path to model (ignored, uses built-in weights)\n");
    fprintf(stderr, "  -v LEVEL                Verbosity level (0, 1, or 2)\n");
    fprintf(stderr, "  --disable_unsync SECS   Test mode: disable unsync after SECS seconds (default 0 = disabled)\n");
    fprintf(stderr, "  --v2                    Use RADE V2 (default: V1)\n");
    fprintf(stderr, "  --write_snr_est FILE    Write per-symbol SNR estimates (float32) to FILE (V2 only)\n");
    fprintf(stderr, "  --gain GAIN             Manual gain applied to rx samples before decoding (default 1.0)\n");
    fprintf(stderr, "  --agc 0|1               Enable/disable input AGC (V2 only, default: on)\n");
    fprintf(stderr, "  --no_bpf                Disable input BPF (V2 only)\n");
    fprintf(stderr, "  --no_timing_adj         Disable timing adjustment (V2 only)\n");
    fprintf(stderr, "  --no_freq_corr          Disable frequency offset correction (V2 only)\n");
    fprintf(stderr, "  --impulse_bpf           Replace BPF with pure 50-sample delay h[50]=1 (V2 only)\n");
    fprintf(stderr, "  --write_bpf_out FILE    Write post-BPF IQ samples (complex float32) to FILE (V2 only)\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "Reads IQ samples from stdin, writes vocoder features to stdout.\n");
    fprintf(stderr, "Input format: complex float32 (interleaved I,Q)\n");
}

int main(int argc, char *argv[]) {
    int opt;
    char *model_name = "model19_check3/checkpoints/checkpoint_epoch_100.pth";
    int flags = 0;
    float disable_unsync = 0.0f;
    char *snr_est_fn = NULL;
    float gain = 1.0f;
    int agc = -1;  /* -1 = leave library default (on) */
    int no_bpf = 0;
    int no_timing_adj = 0;
    int no_freq_corr = 0;
    int impulse_bpf = 0;
    char *write_bpf_out = NULL;

    static struct option long_options[] = {
        {"help",           no_argument,       NULL, 'h'},
        {"model_name",     required_argument, NULL, 'm'},
        {"disable_unsync", required_argument, NULL, 'd'},
        {"v2",             no_argument,       NULL, '2'},
        {"write_snr_est",  required_argument, NULL, 's'},
        {"gain",           required_argument, NULL, 'g'},
        {"agc",            required_argument, NULL, 'a'},
        {"no_bpf",         no_argument,       NULL, 'B'},
        {"no_timing_adj",  no_argument,       NULL, 'T'},
        {"no_freq_corr",   no_argument,       NULL, 'F'},
        {"impulse_bpf",    no_argument,       NULL, 'I'},
        {"write_bpf_out",  required_argument, NULL, 'W'},
        {NULL,             0,                 NULL, 0}
    };

    while ((opt = getopt_long(argc, argv, "hm:v:2s:", long_options, NULL)) != -1) {
        switch (opt) {
        case 'h':
            usage();
            return 0;
        case 'm':
            model_name = optarg;
            break;
        case 'v': {
            int v = atoi(optarg);
            if (v == 0)      flags |= RADE_VERBOSE_0;
            else if (v == 2) flags |= RADE_VERBOSE_TERSE;
            else if (v >= 3) flags |= RADE_VERBOSE_FULL;
            break;
        }
        case 'd':
            disable_unsync = atof(optarg);
            break;
        case '2':
            flags |= RADE_MODE_V2;
            break;
        case 's':
            snr_est_fn = optarg;
            break;
        case 'g':
            gain = atof(optarg);
            break;
        case 'a':
            agc = atoi(optarg);
            break;
        case 'B':
            no_bpf = 1;
            break;
        case 'T':
            no_timing_adj = 1;
            break;
        case 'F':
            no_freq_corr = 1;
            break;
        case 'I':
            impulse_bpf = 1;
            break;
        case 'W':
            write_bpf_out = optarg;
            break;
        default:
            usage();
            return 1;
        }
    }

    /* Initialize RADE */
    rade_initialize();

    struct rade *r = rade_open(model_name, flags);
    if (r == NULL) {
        fprintf(stderr, "Failed to open RADE\n");
        return 1;
    }

    /* Set test mode options */
    if (disable_unsync > 0.0f) {
        rade_set_disable_unsync(r, disable_unsync);
        fprintf(stderr, "disable_unsync: %.1f seconds\n", disable_unsync);
    }
    if (gain != 1.0f) {
        fprintf(stderr, "gain: %f\n", gain);
    }
    if (agc >= 0) {
        rade_rx_set_agc(r, agc);
        fprintf(stderr, "agc: %d\n", agc);
    }
    if (no_bpf) {
        rade_rx_set_bpf(r, 0);
        fprintf(stderr, "BPF disabled\n");
    }
    if (no_timing_adj) {
        rade_rx_set_timing_adj(r, 0);
        fprintf(stderr, "timing_adj disabled\n");
    }
    if (no_freq_corr) {
        rade_rx_set_freq_corr(r, 0);
        fprintf(stderr, "freq_corr disabled\n");
    }
    if (impulse_bpf) {
        rade_rx_set_impulse_bpf(r);
        fprintf(stderr, "impulse BPF: h[50]=1.0 (pure 50-sample delay)\n");
    }
    FILE *fbpf_out = NULL;
    if (write_bpf_out) {
        fbpf_out = fopen(write_bpf_out, "wb");
        if (!fbpf_out) {
            fprintf(stderr, "error: cannot open %s for writing\n", write_bpf_out);
            return 1;
        }
        rade_rx_set_bpf_out_file(r, fbpf_out);
        fprintf(stderr, "writing BPF output to %s\n", write_bpf_out);
    }

    int nin_max = rade_nin_max(r);
    int n_features_out = rade_n_features_in_out(r);
    int n_eoo_bits = rade_n_eoo_bits(r);

    fprintf(stderr, "nin_max: %d n_features_out: %d n_eoo_bits: %d\n",
            nin_max, n_features_out, n_eoo_bits);

    /* Allocate buffers */
    RADE_COMP *rx_in = (RADE_COMP *)malloc(sizeof(RADE_COMP) * nin_max);
    float *features_out = (float *)malloc(sizeof(float) * n_features_out);
    float *eoo_out = n_eoo_bits ? (float *)malloc(sizeof(float) * n_eoo_bits) : NULL;

    if (rx_in == NULL || features_out == NULL || (n_eoo_bits && eoo_out == NULL)) {
        fprintf(stderr, "Failed to allocate buffers\n");
        return 1;
    }

    FILE *feoo_bits = fopen("eoo_rx.f32","wb");

    /* Dynamic array for per-symbol SNR log (V2 only) */
    int    snr_log_size = 0;
    int    snr_log_cap  = 0;
    float *snr_log      = NULL;

    /* Main processing loop */
    int frame_count = 0;
    int valid_count = 0;
    while (1) {
        int nin = rade_nin(r);
        size_t n_read = fread(rx_in, sizeof(RADE_COMP), nin, stdin);
        if (n_read != (size_t)nin) {
            break;
        }

        if (gain != 1.0f) {
            for (int i = 0; i < nin; i++) {
                rx_in[i].real *= gain;
                rx_in[i].imag *= gain;
            }
        }

        /* Receive samples */
        int has_eoo = 0;
        int n_out = rade_rx(r, features_out, &has_eoo, eoo_out, rx_in);

        if (n_out > 0) {
            fwrite(features_out, sizeof(float), n_out, stdout);
            valid_count++;
        }

        if (has_eoo) {
            fprintf(stderr, "End-of-over detected\n");
            if (feoo_bits) {
                fwrite(eoo_out, sizeof(float), n_eoo_bits, feoo_bits);
            }
        }

        if (snr_est_fn) {
            if (snr_log_size == snr_log_cap) {
                snr_log_cap = snr_log_cap ? snr_log_cap * 2 : 4096;
                snr_log = realloc(snr_log, sizeof(float) * snr_log_cap);
            }
            snr_log[snr_log_size++] = rade_snrdB_3k_est(r);
        }

        frame_count++;
    }

    fprintf(stderr, "Processed %d modem frames, %d valid outputs\n", frame_count, valid_count);

    if (snr_est_fn && snr_log) {
        FILE *f = fopen(snr_est_fn, "wb");
        if (f) {
            fwrite(snr_log, sizeof(float), snr_log_size, f);
            fclose(f);
        } else {
            fprintf(stderr, "error: cannot write %s\n", snr_est_fn);
        }
    }

    /* Cleanup */
    if (feoo_bits) fclose(feoo_bits);
    if (fbpf_out)  fclose(fbpf_out);
    free(rx_in);
    free(features_out);
    free(eoo_out);
    free(snr_log);
    rade_close(r);
    rade_finalize();

    return 0;
}
