/*---------------------------------------------------------------------------*\

  rade_v2_text_test.c

  End-to-end streaming text test for the RADE V2 BPSK data symbol channel.

  Encodes a test string as a cycling stream of +/-1 BPSK symbols (one per
  modem frame), passes the IQ samples through the V2 receiver with no added
  noise, then uses a sliding-window search to recover the string from the
  received soft-decision symbols.

  No external files or Python are required.

  Returns 0 on PASS, 1 on FAIL.

\*---------------------------------------------------------------------------*/

/*
  Copyright (C) 2026 David Rowe

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

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "rade_api.h"

#define TEST_MSG     "hello world"
#define N_TX_FRAMES  300    /* frames to transmit; covers acquisition + several message copies */
#define SKIP_SYMBOLS 60     /* discard symbols during acquisition window */

int main(void) {
    rade_initialize();
    struct rade *r = rade_open("dummy", RADE_MODE_V2 | RADE_VERBOSE_0);
    assert(r != NULL);

    int n_features = rade_n_features_in_out(r);
    int n_tx_out   = rade_n_tx_out(r);
    int n_eoo_out  = rade_n_tx_eoo_out(r);
    int nin_max    = rade_nin_max(r);

    /* Build cycling bit stream from TEST_MSG: MSB first, +1.0 = 1, -1.0 = 0 */
    int msg_len = (int)strlen(TEST_MSG);
    int n_bits  = msg_len * 8;
    float *tx_bits = (float *)malloc(sizeof(float) * n_bits);
    assert(tx_bits);
    for (int i = 0; i < msg_len; i++) {
        unsigned char c = (unsigned char)TEST_MSG[i];
        for (int b = 0; b < 8; b++)
            tx_bits[i * 8 + b] = ((c >> (7 - b)) & 1) ? 1.0f : -1.0f;
    }

    /* Allocate TX sample buffer (data frames + EOO) */
    int total_samples = N_TX_FRAMES * n_tx_out + n_eoo_out;
    RADE_COMP *tx_buf      = (RADE_COMP *)malloc(sizeof(RADE_COMP) * total_samples);
    float     *features_in = (float *)calloc(n_features, sizeof(float)); /* silence */
    assert(tx_buf && features_in);

    /* Generate TX: set data symbol for each frame before encoding */
    int tx_pos = 0;
    for (int frame = 0; frame < N_TX_FRAMES; frame++) {
        rade_tx_set_data_symbol(r, tx_bits[frame % n_bits]);
        int n = rade_tx(r, tx_buf + tx_pos, features_in);
        tx_pos += n;
    }
    int n = rade_tx_eoo(r, tx_buf + tx_pos);
    tx_pos += n;

    /* RX: feed buffered samples through receiver, collect data symbols */
    float     *features_out = (float *)malloc(sizeof(float) * n_features);
    RADE_COMP *rx_in        = (RADE_COMP *)malloc(sizeof(RADE_COMP) * nin_max);
    float     *rx_symbols   = (float *)malloc(sizeof(float) * (N_TX_FRAMES + 100));
    assert(features_out && rx_in && rx_symbols);

    int n_rx_symbols = 0;
    int rx_pos = 0;
    int has_eoo;
    int eoo_detected = 0;

    while (rx_pos + rade_nin(r) <= tx_pos) {
        int nin = rade_nin(r);
        memcpy(rx_in, tx_buf + rx_pos, sizeof(RADE_COMP) * nin);
        rx_pos += nin;
        int n_out = rade_rx(r, features_out, &has_eoo, NULL, rx_in);
        if (has_eoo) eoo_detected = 1;
        if (n_out > 0)
            rx_symbols[n_rx_symbols++] = rade_rx_get_data_symbol(r);
    }

    fprintf(stderr, "rade_v2_text_test: %d symbols received, EOO %s\n",
            n_rx_symbols, eoo_detected ? "detected" : "NOT detected");

    /* Sliding window search for TEST_MSG after acquisition window */
    int found     = 0;
    int found_off = 0;
    for (int start = SKIP_SYMBOLS;
         start <= n_rx_symbols - n_bits && !found;
         start++) {
        char decoded[sizeof(TEST_MSG)] = {0};
        int all_printable = 1;
        for (int i = 0; i < msg_len && all_printable; i++) {
            unsigned char c = 0;
            for (int b = 0; b < 8; b++)
                if (rx_symbols[start + i * 8 + b] > 0.0f)
                    c |= (unsigned char)(1 << (7 - b));
            decoded[i] = (char)c;
            if (c < 32 || c > 126) all_printable = 0;
        }
        if (all_printable && memcmp(decoded, TEST_MSG, msg_len) == 0) {
            found     = 1;
            found_off = start;
        }
    }

    if (found)
        fprintf(stderr, "  found '%s' at symbol offset %d\n", TEST_MSG, found_off);
    else
        fprintf(stderr, "  '%s' not found in %d received symbols (after skip %d)\n",
                TEST_MSG, n_rx_symbols, SKIP_SYMBOLS);

    int pass = found && eoo_detected;
    printf("%s\n", pass ? "PASS" : "FAIL");

    free(tx_bits);
    free(tx_buf);
    free(features_in);
    free(features_out);
    free(rx_in);
    free(rx_symbols);
    rade_close(r);
    rade_finalize();
    return pass ? 0 : 1;
}
