/*---------------------------------------------------------------------------*\

  rade_v1_text_test.c

  End-to-end round-trip test for the V1 EOO text channel.

  For each test callsign the test:
    1. Encodes the callsign into EOO bits and sets them via rade_tx_set_eoo_bits().
    2. Generates the modulated EOO frame via rade_tx_eoo().
    3. Demodulates the frame (no noise, perfect timing) via
       rade_ofdm_demod_eoo().
    4. Decodes the callsign from the soft-decision bits.
    5. Checks the decoded string matches the original.

  Returns 0 on full pass, 1 if any test fails.

\*---------------------------------------------------------------------------*/

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "rade_fargan_config.h" /* to silence Opus build warnings */
#include "rade_api.h"
#include "rade_dsp.h"
#include "rade_ofdm.h"

#define CALLSIGN_MAX 8  /* max callsign chars; 8 × 7 bits = 56 bits of EOO */

static void callsign_encode(struct rade *r, const char *callsign) {
    int n_eoo_bits = rade_n_eoo_bits(r);
    float *bits = (float *)calloc(n_eoo_bits, sizeof(float));
    assert(bits);
    int src_len = (int)strlen(callsign);
    for (int i = 0; i < CALLSIGN_MAX; i++) {
        unsigned char c = (i < src_len) ? (unsigned char)callsign[i] : ' ';
        for (int b = 0; b < 7; b++) {
            int bit = (c >> (6 - b)) & 1;
            bits[i * 7 + b] = bit ? 1.0f : -1.0f;
        }
    }
    rade_tx_set_eoo_bits(r, bits);
    free(bits);
}

static int callsign_decode(const float *eoo_bits, int n_eoo_bits, char *out) {
    if (n_eoo_bits < CALLSIGN_MAX * 7) { out[0] = '\0'; return 0; }
    for (int i = 0; i < CALLSIGN_MAX; i++) {
        unsigned char c = 0;
        for (int b = 0; b < 7; b++)
            c |= (unsigned char)(((eoo_bits[i * 7 + b] > 0.0f) ? 1 : 0) << (6 - b));
        out[i] = (char)c;
    }
    out[CALLSIGN_MAX] = '\0';
    int len = CALLSIGN_MAX;
    while (len > 0 && out[len - 1] == ' ') out[--len] = '\0';
    return len;
}

/*---------------------------------------------------------------------------*\
                              HELPERS
\*---------------------------------------------------------------------------*/

static int run_test(struct rade *r, rade_ofdm *ofdm,
                    const char *callsign, int verbose) {
    /* --- encode callsign into EOO bits --- */
    callsign_encode(r, callsign);

    /* --- modulate the EOO frame --- */
    int n_eoo_out = rade_n_tx_eoo_out(r);
    RADE_COMP *tx_eoo = (RADE_COMP *)malloc(sizeof(RADE_COMP) * n_eoo_out);
    assert(tx_eoo);

    int n_written = rade_tx_eoo(r, tx_eoo);
    assert(n_written == n_eoo_out);

    /* --- demodulate (no noise, time_offset = 0) --- */
    int n_eoo_bits = rade_n_eoo_bits(r);
    float *eoo_bits = (float *)malloc(sizeof(float) * n_eoo_bits);
    assert(eoo_bits);

    rade_ofdm_demod_eoo(ofdm, eoo_bits, tx_eoo, 0);

    /* --- decode callsign from soft decisions --- */
    char decoded[CALLSIGN_MAX + 1];
    int decoded_len = callsign_decode(eoo_bits, n_eoo_bits, decoded);

    int pass = (strcmp(decoded, callsign) == 0);

    if (verbose || !pass)
        printf("  [%s]  set='%s'  got='%s'  len=%d\n",
               pass ? "PASS" : "FAIL", callsign, decoded, decoded_len);

    free(tx_eoo);
    free(eoo_bits);
    return pass;
}

/*---------------------------------------------------------------------------*\
                                  MAIN
\*---------------------------------------------------------------------------*/

int main(void) {
    /* ---- init ---- */
    rade_initialize();
    struct rade *r = rade_open("dummy", RADE_VERBOSE_0);
    assert(r != NULL);

    /* A separate OFDM object is used for demodulation; the parameters
       (Nc, M, Ncp, Ns) are compile-time constants so any bottleneck value
       produces identical OFDM geometry. */
    rade_ofdm ofdm;
    rade_ofdm_init(&ofdm, 3);

    /* ---- test cases ---- */
    static const char *callsigns[] = {
        "VK2DVZ",   /* typical 6-char Australian callsign        */
        "W1AW",     /* short 4-char US callsign                  */
        "KG5SWP",   /* 6-char US callsign                        */
        "VK4RGG1",  /* 7-char, near maximum length               */
        "AA1ZZZZZ", /* 8-char, exactly RADE_EOO_CALLSIGN_MAX     */
        "A",        /* minimum 1-char edge case                  */
    };
    int n_cases = (int)(sizeof(callsigns) / sizeof(callsigns[0]));

    printf("rade_v1_text_test: %d test cases\n", n_cases);

    int n_pass = 0;
    for (int i = 0; i < n_cases; i++)
        n_pass += run_test(r, &ofdm, callsigns[i], 1);

    /* ---- summary ---- */
    printf(n_pass == n_cases ? "\nPASS (%d/%d)\n" : "\nFAIL (%d/%d)\n",
           n_pass, n_cases);

    rade_close(r);
    rade_finalize();
    return (n_pass == n_cases) ? 0 : 1;
}
