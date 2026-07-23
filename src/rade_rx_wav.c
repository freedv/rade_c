/*---------------------------------------------------------------------------*\

  rade_demod_wav.c

  RADAE WAV demodulator.  Reads a WAV file containing received RADE OFDM
  audio and writes a WAV file containing the decoded voice audio.

  Combines radae_rx (OFDM demod + neural decoder) and the FARGAN vocoder
  into a single command-line tool.

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
#include <stdint.h>
#include <math.h>
#include <getopt.h>

#include "rade_api.h"
#include "rade_dsp.h"
#include "fargan.h"
#include "lpcnet.h"

/* ---- WAV file I/O ---- */

#define WAV_FMT_PCM   1
#define WAV_FMT_FLOAT 3

typedef struct {
    int      sample_rate;
    int      num_channels;
    int      bits_per_sample;
    int      is_float;          /* 1 if IEEE float format */
    long     data_offset;       /* byte offset of audio data in file */
    uint32_t data_size;         /* byte count of audio data */
} wav_info;

/* Parse WAV header.  On success the file position is at the first audio byte. */
static int wav_read_header(FILE *f, wav_info *info) {
    char     tag[4];
    uint32_t riff_size;

    if (fread(tag, 1, 4, f) != 4 || memcmp(tag, "RIFF", 4)) return -1;
    if (fread(&riff_size, 4, 1, f) != 1) return -1;
    if (fread(tag, 1, 4, f) != 4 || memcmp(tag, "WAVE", 4)) return -1;

    info->data_offset = -1;

    while (1) {
        char     chunk_id[4];
        uint32_t chunk_size;
        if (fread(chunk_id, 1, 4, f) != 4) break;
        if (fread(&chunk_size, 4, 1, f) != 1) break;

        if (memcmp(chunk_id, "fmt ", 4) == 0) {
            if (chunk_size < 16) return -1;
            uint8_t buf[16];
            if (fread(buf, 1, 16, f) != 16) return -1;

            uint16_t audio_fmt, nch, bps;
            uint32_t sr;
            memcpy(&audio_fmt, buf + 0,  2);
            memcpy(&nch,       buf + 2,  2);
            memcpy(&sr,        buf + 4,  4);
            memcpy(&bps,       buf + 14, 2);

            info->sample_rate     = (int)sr;
            info->num_channels    = (int)nch;
            info->bits_per_sample = (int)bps;
            info->is_float        = (audio_fmt == WAV_FMT_FLOAT);

            if (chunk_size > 16)
                fseek(f, (long)(chunk_size - 16), SEEK_CUR);

        } else if (memcmp(chunk_id, "data", 4) == 0) {
            info->data_offset = ftell(f);
            info->data_size   = chunk_size;
            break;
        } else {
            /* skip unknown chunk (pad to even byte boundary) */
            fseek(f, (long)((chunk_size + 1) & ~1u), SEEK_CUR);
        }
    }
    return (info->data_offset >= 0) ? 0 : -1;
}

/* Read the entire audio payload into a float buffer (16-bit PCM mono only).  Caller must free(). */
static float *wav_read_mono_float(FILE *f, const wav_info *info, long *n_out) {
    long n = (long)info->data_size / 2;

    float *buf = malloc((size_t)n * sizeof(float));
    if (!buf) return NULL;

    for (long i = 0; i < n; i++) {
        int16_t tmp;
        if (fread(&tmp, 2, 1, f) != 1) { free(buf); return NULL; }
        buf[i] = tmp * (2.0f / RADE_INT16_SCALE);
    }
    *n_out = n;
    return buf;
}

/* Write a standard 44-byte PCM WAV header (16-bit, mono). */
static void wav_write_header(FILE *f, int sample_rate, uint32_t data_bytes) {
    uint16_t nch         = 1;
    uint16_t bps         = 16;
    uint16_t fmt         = WAV_FMT_PCM;
    uint32_t fmt_size    = 16;
    uint16_t block_align = (uint16_t)(nch * bps / 8);
    uint32_t byte_rate   = (uint32_t)sample_rate * block_align;
    uint32_t riff_size   = 36 + data_bytes;
    uint32_t sr          = (uint32_t)sample_rate;

    fwrite("RIFF",       1, 4, f);  fwrite(&riff_size,   4, 1, f);
    fwrite("WAVE",       1, 4, f);
    fwrite("fmt ",       1, 4, f);  fwrite(&fmt_size,    4, 1, f);
    fwrite(&fmt,         2, 1, f);  fwrite(&nch,         2, 1, f);
    fwrite(&sr,          4, 1, f);  fwrite(&byte_rate,   4, 1, f);
    fwrite(&block_align, 2, 1, f);  fwrite(&bps,         2, 1, f);
    fwrite("data",       1, 4, f);  fwrite(&data_bytes,  4, 1, f);
}

/* ---- Usage ---- */

static void usage(void) {
    fprintf(stderr,
            "usage: rade_demod_wav [options] <input.wav> <output.wav>\n\n"
            "  Reads a WAV file containing received RADE OFDM audio and writes\n"
            "  a WAV file containing the decoded voice audio.\n\n"
            "  Input WAV : %d Hz 16-bit PCM mono\n"
            "              Use sox or ffmpeg to convert other formats.\n"
            "  Output WAV: mono 16-bit PCM @ %d Hz\n\n"
            "options:\n"
            "  -h, --help     Show this help\n"
            "  -v LEVEL       Verbosity: 0=quiet  1=normal (default)  2=verbose\n"
            "  -f FEATURES    Write RX features to disk"
            "  --v2           Use RADE V2 (default: V1)\n",
            RADE_FS, RADE_FS_SPEECH);
}

/* ---- Main ---- */

int main(int argc, char *argv[]) {
    int verbose = 1;
    int use_v2  = 0;
    int opt;
    FILE* feature_fp = NULL;
    static struct option long_options[] = {
        {"help", no_argument, NULL, 'h'},
        {"v2",   no_argument, NULL,  1 },
        {"f",    required_argument, NULL, 'f'},
        {NULL,   0,           NULL, 0 }
    };

    while ((opt = getopt_long(argc, argv, "hv:f:", long_options, NULL)) != -1) {
        switch (opt) {
            case 'h': usage(); return 0;
            case 'v': verbose = atoi(optarg); break;
            case 'f':
                feature_fp = fopen(optarg, "wb");
                if (!feature_fp) {
                    perror("Could not open feature file");
                    usage();
                    return 1;
                }
                break;
            case  1:  use_v2  = 1; break;
            default:  usage(); return 1;
        }
    }
    if (argc - optind != 2) { usage(); return 1; }

    const char *input_file  = argv[optind];
    const char *output_file = argv[optind + 1];

    /* ------------------------------------------------------------------ read input WAV */
    FILE *fin = fopen(input_file, "rb");
    if (!fin) {
        fprintf(stderr, "rade_demod: can't open '%s'\n", input_file);
        return 1;
    }

    wav_info wav;
    if (wav_read_header(fin, &wav) != 0) {
        fprintf(stderr, "rade_demod: can't parse '%s' as WAV\n", input_file);
        fclose(fin);
        return 1;
    }
    if (verbose >= 1)
        fprintf(stderr, "Input: %s  %d Hz  %d ch  %d-bit %s\n",
                input_file, wav.sample_rate, wav.num_channels,
                wav.bits_per_sample, wav.is_float ? "float" : "int");

    if (wav.bits_per_sample != 16 || wav.is_float) {
        fprintf(stderr, "rade_demod: input must be 16-bit PCM WAV (got %d-bit %s); "
                "use sox or ffmpeg to convert\n",
                wav.bits_per_sample, wav.is_float ? "float" : "int");
        fclose(fin);
        return 1;
    }
    if (wav.sample_rate != RADE_FS) {
        fprintf(stderr, "rade_demod: input must be %d Hz (got %d Hz); "
                "use sox or ffmpeg to resample\n", RADE_FS, wav.sample_rate);
        fclose(fin);
        return 1;
    }
    if (wav.num_channels != 1) {
        fprintf(stderr, "rade_demod: input must be mono (got %d channels); "
                "use sox or ffmpeg to convert\n", wav.num_channels);
        fclose(fin);
        return 1;
    }

    long  n_mono = 0;
    float *mono  = wav_read_mono_float(fin, &wav, &n_mono);
    fclose(fin);
    if (!mono) return 1;

    float *audio = mono;
    long   n_8k  = n_mono;

    if (verbose >= 1)
        fprintf(stderr, "Modem input: %ld samples @ %d Hz  (%.1f s)\n",
                n_8k, RADE_FS, (double)n_8k / RADE_FS);

    /* ------------------------------------------------- real → IQ (imag = 0) */
    /* The OFDM carriers sit at 1062-1875 Hz; the negative-frequency mirror
       of a real signal falls at -1875 to -1062 Hz and is rejected by the
       OFDM correlators, so no Hilbert transform is needed. */
    RADE_COMP *iq = malloc((size_t)n_8k * sizeof(RADE_COMP));
    if (!iq) {
        fprintf(stderr, "rade_demod: malloc failed (IQ buffer)\n");
        free(audio);
        return 1;
    }
    for (long i = 0; i < n_8k; i++) {
        iq[i].real = audio[i];
        iq[i].imag = 0.0f;
    }
    free(audio);

    /* ------------------------------------------------------ open RADE receiver */
    rade_initialize();

    int flags = 0;
    if (verbose == 0) flags |= RADE_VERBOSE_0;
    else if (verbose == 2) flags |= RADE_VERBOSE_TERSE;
    else if (verbose >= 3) flags |= RADE_VERBOSE_FULL;
    if (use_v2) flags |= RADE_MODE_V2;
    /* model_name is ignored; built-in weights are used */
    char *model_name = "model19_check3/checkpoints/checkpoint_epoch_100.pth";
    struct rade *r = rade_open(model_name, flags);
    if (!r) {
        fprintf(stderr, "rade_demod: rade_open failed\n");
        free(iq);
        rade_finalize();
        return 1;
    }

    int nin_max        = rade_nin_max(r);
    int n_features_out = rade_n_features_in_out(r);
    int n_eoo_bits     = rade_n_eoo_bits(r);

    RADE_COMP *rx_buf     = malloc((size_t)nin_max        * sizeof(RADE_COMP));
    float     *feat_buf   = malloc((size_t)n_features_out * sizeof(float));
    float     *eoo_buf    = n_eoo_bits ? malloc((size_t)n_eoo_bits * sizeof(float)) : NULL;
    if (!rx_buf || !feat_buf || (n_eoo_bits && !eoo_buf)) {
        fprintf(stderr, "rade_demod: malloc failed\n");
        free(iq); free(rx_buf); free(feat_buf); free(eoo_buf);
        rade_close(r); rade_finalize();
        return 1;
    }

    /* ------------------------------------------------- open FARGAN vocoder */
    FARGANState fargan;
    fargan_init(&fargan);

    /* Buffer for the 5-frame warm-up required by fargan_cont().
       Layout: 5 consecutive NB_TOTAL_FEATURES-float frames. */
    int   fargan_ready  = 0;
    float cont_buf[5 * NB_TOTAL_FEATURES];
    int   cont_frames   = 0;

    /* ---------------------------------------------------- open output WAV */
    FILE *fout = fopen(output_file, "wb");
    if (!fout) {
        fprintf(stderr, "rade_demod: can't open '%s' for writing\n", output_file);
        free(iq); free(rx_buf); free(feat_buf); free(eoo_buf);
        rade_close(r); rade_finalize();
        return 1;
    }
    /* Placeholder header – data_size patched at the end. */
    wav_write_header(fout, RADE_FS_SPEECH, 0);
    uint32_t total_bytes = 0;

    /* ---------------------------------------------------- demodulation loop */
    long iq_pos    = 0;
    int   mf_count  = 0;   /* modem frames fed to RX */
    int   vld_count = 0;   /* valid feature outputs */
    float snr_sum   = 0.0f; /* accumulate SNR while in sync */

    while (iq_pos < n_8k) {
        int  nin       = rade_nin(r);
        long remaining = n_8k - iq_pos;

        /* Copy samples into rx_buf; zero-pad the final short block so the
           last modem frame has a chance to flush. */
        if (remaining < nin) {
            memset(rx_buf, 0, (size_t)nin * sizeof(RADE_COMP));
            memcpy(rx_buf, &iq[iq_pos], (size_t)remaining * sizeof(RADE_COMP));
            iq_pos = n_8k;
        } else {
            memcpy(rx_buf, &iq[iq_pos], (size_t)nin * sizeof(RADE_COMP));
            iq_pos += nin;
        }

        int has_eoo = 0;
        int n_out   = rade_rx(r, feat_buf, &has_eoo, eoo_buf, rx_buf);

        if (has_eoo && verbose >= 1)
            fprintf(stderr, "End-of-over at modem frame %d\n", mf_count);

        if (n_out > 0) {
            vld_count++;
            snr_sum += rade_snrdB_3k_est(r);
            int n_frames = n_out / RADE_NB_TOTAL_FEATURES;

            for (int fi = 0; fi < n_frames; fi++) {
                float *feat = &feat_buf[fi * RADE_NB_TOTAL_FEATURES];

                if (feature_fp) {
                    fwrite(feat, sizeof(float), RADE_NB_TOTAL_FEATURES, feature_fp);
                }

                /* ---- fargan_cont warm-up: buffer the first 5 frames ---- */
                if (!fargan_ready) {
                    memcpy(&cont_buf[cont_frames * RADE_NB_TOTAL_FEATURES],
                           feat, (size_t)RADE_NB_TOTAL_FEATURES * sizeof(float));
                    if (++cont_frames >= 5) {
                        /* fargan_cont expects features packed at stride
                           NB_FEATURES – copy only the first NB_FEATURES of
                           each buffered frame, matching lpcnet_demo behaviour. */
                        float packed[5 * NB_FEATURES];
                        for (int i = 0; i < 5; i++)
                            memcpy(&packed[i * NB_FEATURES],
                                   &cont_buf[i * NB_TOTAL_FEATURES],
                                   (size_t)NB_FEATURES * sizeof(float));

                        float zeros[FARGAN_CONT_SAMPLES];
                        memset(zeros, 0, sizeof(zeros));
                        fargan_cont(&fargan, zeros, packed);
                        fargan_ready = 1;
                    }
                    continue;   /* warm-up frames are not synthesised */
                }

                /* ---- synthesise one 10-ms speech frame ---- */
                float   fpcm[LPCNET_FRAME_SIZE];
                int16_t pcm[LPCNET_FRAME_SIZE];

                fargan_synthesize(&fargan, fpcm, feat);

                /* float → int16, matching lpcnet_demo rounding */
                for (int s = 0; s < LPCNET_FRAME_SIZE; s++) {
                    float v = fpcm[s] * 32768.0f;
                    if (v >  32767.0f)  v =  32767.0f;
                    if (v < -32767.0f)  v = -32767.0f;
                    pcm[s] = (int16_t)floor(0.5 + (double)v);
                }

                fwrite(pcm, sizeof(int16_t), (size_t)LPCNET_FRAME_SIZE, fout);
                total_bytes += (uint32_t)(LPCNET_FRAME_SIZE * (int)sizeof(int16_t));
            }
        }
        mf_count++;
    }

    /* -------------------------------------------------------- finalise WAV */
    fseek(fout, 0, SEEK_SET);
    wav_write_header(fout, RADE_FS_SPEECH, total_bytes);
    fclose(fout);

    /* ------------------------------------------------------------ summary */
    if (verbose >= 1) {
        float snr_mean = vld_count ? snr_sum / vld_count : 0.0f;
        fprintf(stderr, "Modem frames: %d   valid: %d   SNR: %.1f dB\n",
                mf_count, vld_count, snr_mean);
        fprintf(stderr, "Output: %s  %.1f s  (%u bytes)\n",
                output_file, (double)total_bytes / (2.0 * RADE_FS_SPEECH), total_bytes);
    }

    /* -----------------------------------------------------------  cleanup */
    if (feature_fp) {
        fclose(feature_fp);
    }

    free(iq);
    free(rx_buf);
    free(feat_buf);
    free(eoo_buf);
    rade_close(r);
    rade_finalize();
    return 0;
}
