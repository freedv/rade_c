# RADE API Usage

This document describes the public C API of the Radio Autoencoder (RADE)
library as declared in [src/rade_api.h](src/rade_api.h). The API exposes a
single context that contains one transmitter (Tx) and one receiver (Rx), and
supports both RADE V1 and RADE V2 via the `RADE_MODE_V2` flag.

All functions are declared `extern "C"` so the library can be used from both C
and C++. On Windows the symbols are exported/imported via `__declspec` and use
the `__stdcall` calling convention (handled automatically by the
`RADE_EXPORT` macro).

---

## Concepts and conventions

- **Complex samples** — IQ samples are passed as arrays of `RADE_COMP`, a
  single-precision complex type:

  ```c
  typedef struct {
    float real;
    float imag;
  } RADE_COMP;
  ```

- **Sample rates** — two fixed rates are defined:

  | Macro | Value | Meaning |
  | --- | --- | --- |
  | `RADE_MODEM_SAMPLE_RATE` | 8000 | modem (IQ) waveform sample rate |
  | `RADE_SPEECH_SAMPLE_RATE` | 16000 | speech sample rate |

- **Features** — the API operates on FARGAN vocoder *feature* vectors rather
  than speech audio. `rade_tx()` accepts features and produces modem IQ samples;
  `rade_rx()` accepts modem IQ samples and produces features. The caller is
  responsible for converting speech to features (Tx) and synthesising speech
  from features (Rx) using `lpcnet_demo`. As an example the `rade_tx_wav` /
  `rade_rx_wav` convenience tools wrap this full pipeline internally.

- **Soft-decision bits** — aux text channel bits (V1 EOO bits, V2 BPSK data
  symbols) are represented as floats in `+1.0` / `-1.0` form (i.e. *not* `1`/`0`).

- **Single context** — this version supports a single `struct rade` context,
  with exactly one Tx and one Rx inside it.

---

## Scaling to 16 bits

`RADE_COMP`/feature values are nominal `+/-1.0` peak float — but *nominal*
only: the signal occasionally exceeds `1.0` (RADE V2's target RMS is `~0.707`
at `~3dB` PAPR, so brief peaks above `1.0` are expected, not a bug). Scaling
naively by `32768.0` when converting to/from 16-bit PCM (WAV files, sound
cards, most radio audio interfaces) leaves no headroom for those peaks and
will clip them. `rade_tx_wav.c` instead defines:

```c
#define TX_SCALE 16384.0f   /* nominal 1.0 -> 16384, 6dB of headroom to 32767 */
```

On the Rx side, the scale factor depends on what you're feeding `rade_rx()`:

- **Genuine complex IQ** (both real and imaginary from the Tx side survived
  the channel) — use the algebraic inverse, `1.0f / TX_SCALE` (`~6.10E-5`).
- **Real-only signal** (e.g. a real SSB radio's mono audio output, with the
  imaginary/quadrature component unavailable or reconstructed some other
  way) — typically needs roughly double the canonical inverse (`~1.22E-4`),
  since only half of the complex signal's dynamic range is present in a
  real-valued capture. The exact factor depends on how you reconstruct IQ
  from the real signal (e.g. a Hilbert transform may have its own inherent
  gain) — verify empirically for your specific method rather than assuming
  this number applies unchanged.

Either way, don't chase exact calibration: [`rade_rx_set_agc()`](#v2-input-agc)
(on by default for V2) corrects residual level mismatches at the Rx input
within `+/-20dB` (`0.1x`-`10x`), so landing in the right ballpark is
sufficient. `1.22E-4` is the real-signal value already validated against real
hardware-in-the-loop (OTC) testing in `ota_test.sh`/`rx2.py`.

---

## Initialization and lifecycle

### `void rade_initialize(void)`

Must be called **before any other RADE function**. Initializes internal
library state.

### `void rade_finalize(void)`

Call when finished with RADE to release library-level resources.

### `struct rade *rade_open(char model_file[], int flags)`

Creates and returns a RADE context. `model_file` is used for user supplied models, set to "" for normal use (built-in weights). `flags` is a bitwise OR of:

| Flag | Value | Meaning |
| --- | --- | --- |
| `RADE_USE_C_ENCODER` | `0x1` | use the C encoder implementation |
| `RADE_USE_C_DECODER` | `0x2` | use the C decoder implementation |
| `RADE_FOFF_TEST` | `0x4` | frequency-offset test mode (developers only) |
| `RADE_VERBOSE_0` | `0x8` | quiet — suppress all per-frame status output |
| `RADE_MODE_V2` | `0x10` | select RADE V2 (default is V1) |
| `RADE_VERBOSE_TERSE` | `0x20` | terse per-frame status (state, sig, f_off, snr, eoo) |
| `RADE_VERBOSE_FULL` | `0x40` | full per-frame status (all diagnostic fields) |

Returns a pointer to a `struct rade` context, used in all subsequent calls.

### `void rade_close(struct rade *r)`

Closes and frees a context previously returned by `rade_open()`.

### `int rade_version(void)`

Returns the major API version — incremented on breaking changes.

### `int rade_version_minor(void)`

Returns the minor API version — incremented on non-breaking additions.

### The `struct rade` context

```c
struct rade {
    int flags;
    int auxdata;
    int bottleneck;

    rade_tx_state    tx;     /* V1 transmitter state */
    rade_rx_state    rx;     /* V1 receiver state    */
    rade_tx_v2_state tx_v2;  /* V2 transmitter state */
    rade_rx_v2_state rx_v2;  /* V2 receiver state    */
};
```

Treat this as an opaque handle through the API functions.

---

## Sizing helpers

Use these to size the arrays you pass to the Tx/Rx functions. They depend on
the context configuration, so call them after `rade_open()`.

| Function | Returns |
| --- | --- |
| `int rade_n_tx_out(struct rade *r)` | number of `RADE_COMP` samples produced per `rade_tx()` call |
| `int rade_n_tx_eoo_out(struct rade *r)` | number of `RADE_COMP` samples produced by `rade_tx_eoo()` — V1 only |
| `int rade_nin_max(struct rade *r)` | maximum number of input samples ever required by `rade_rx()` (use for buffer allocation) |
| `int rade_n_features_in_out(struct rade *r)` | number of feature floats per Tx input frame / Rx output frame |
| `int rade_n_eoo_bits(struct rade *r)` | number of EOO soft-decision bits — V1 only |

---

## Transmit (Tx)

### `int rade_tx(struct rade *r, RADE_COMP tx_out[], float features_in[])`

Encodes one frame of input `features_in[]` into modem IQ samples written to
`tx_out[]`.

- `features_in[]` must hold `rade_n_features_in_out(r)` floats.
- `tx_out[]` must have room for `rade_n_tx_out(r)` `RADE_COMP` samples.
- Returns the number of `RADE_COMP` samples written to `tx_out[]`.

> Note: the API operates on feature vectors — the caller is responsible for
> converting speech to features (Tx) and synthesising speech from features (Rx),
> e.g. via `lpcnet_demo` or the equivalent Opus/FARGAN library calls.

### `void rade_tx_set_eoo_bits(struct rade *r, float eoo_bits[])` — V1 only (aux text channel)

Sets the EOO bits to be embedded in the End-of-Over frame. `eoo_bits[]` must
contain `rade_n_eoo_bits(r)` floats in `+1.0` / `-1.0` form (not `1`/`0`).
Text encoding (callsign, grid square, etc.) is the responsibility of the caller's
text stack above this API.

### `int rade_tx_eoo(struct rade *r, RADE_COMP tx_eoo_out[])` — V1 only (aux text channel)

Generates the final End-of-Over frame at the end of an over. `tx_eoo_out[]`
must have room for `rade_n_tx_eoo_out(r)` `RADE_COMP` samples. Returns the
number of `RADE_COMP` samples written.

### V2: BPSK data symbol

#### `void rade_tx_set_data_symbol(struct rade *r, float symbol)`

Sets the BPSK data symbol to be transmitted in the next modem frame.
`symbol` must be `+1.0` or `-1.0`. Call this before each `rade_tx()` to
stream one bit per frame (~25 bits/s auxiliary channel).

---

## Receive (Rx)

### `int rade_nin(struct rade *r)`

Returns the number of input IQ samples to place into `rx_in[]` for the **next**
call to `rade_rx()`. This value can vary between calls (timing tracking), so
call `rade_nin()` before every `rade_rx()` call. Size your `rx_in[]` buffer
using `rade_nin_max()`.

### `int rade_rx(struct rade *r, float features_out[], int *has_eoo_out, float eoo_out[], RADE_COMP rx_in[])`

Processes `rade_nin(r)` input IQ samples from `rx_in[]`.

- `features_out[]`: receives decoded feature floats; size it with
  `rade_n_features_in_out(r)`.
- `has_eoo_out`: V1 only (aux text channel) — set by the function when `eoo_out[]`
  contains valid End-of-Over soft-decision bits. Pass `NULL` for V2.
- `eoo_out[]`: V1 only (aux text channel) — receives EOO soft-decision bits from
  the QPSK symbols in `...IQIQI...` order; size it with `rade_n_eoo_bits(r)`.
  Pass `NULL` for V2.
- `rx_in[]`: input IQ samples (`rade_nin(r)` of them).

Returns non-zero if `features_out[]` contains valid output; the returned value
is the number of feature samples written to `features_out[]`.

### `int rade_sync(struct rade *r)`

Returns non-zero when the receiver is currently in sync.

### `float rade_freq_offset(struct rade *r)`

Returns the current frequency offset of the received signal. Valid only when
`rade_sync(r) != 0`.

### `float rade_snrdB_3k_est(struct rade *r)`

Returns the current SNR estimate in dB (3 kHz noise bandwidth) of the received
signal as a float. Valid only when `rade_sync(r) != 0`.

### `void rade_set_disable_unsync(struct rade *r, float seconds)`

Test mode: disables the unsync mechanism for the given number of seconds
(`0` = disabled, i.e. normal unsync behavior).

### V2: BPSK data symbol

#### `float rade_rx_get_data_symbol(struct rade *r)`

Returns the soft-decision BPSK data symbol received in the last modem frame.
Valid after `rade_rx()` returns a value greater than zero. Positive values
indicate a `+1` bit, negative values indicate a `-1` bit.

### V2: input AGC

#### `void rade_rx_set_agc(struct rade *r, int enable)`

Enables/disables the Rx input AGC — **on by default**. AGC normalises the RMS
level of incoming `rx_in[]` samples to compensate for Tx/Rx gain-staging
mismatches; without it, decode quality is sensitive to input level (see
[Scaling to 16 bits](#scaling-to-16-bits)). Effective correction range is
`+/-20dB` around the nominal Rx level of `1.0` — pass `enable = 0` to disable
(e.g. to characterise raw level sensitivity), `1` to re-enable.

---

## Typical usage

### RADE V1 transmit loop

```c
rade_initialize();
struct rade *r = rade_open("", RADE_VERBOSE_0);

int n_features = rade_n_features_in_out(r);
int n_tx       = rade_n_tx_out(r);

float     features_in[n_features];
RADE_COMP tx_out[n_tx];

/* optional: set EOO bits from your text stack before the end of over */
/* rade_tx_set_eoo_bits(r, eoo_bits); */

while (have_more_speech()) {
    fill_features(features_in);                  /* caller's feature extractor */
    int nout = rade_tx(r, tx_out, features_in);
    send_iq(tx_out, nout);                       /* to the radio */
}

/* optional: transmit End-of-Over frame (aux text channel) */
/* RADE_COMP eoo_out[rade_n_tx_eoo_out(r)];
   int neoo = rade_tx_eoo(r, eoo_out);
   send_iq(eoo_out, neoo); */

rade_close(r);
rade_finalize();
```

### RADE V1 receive loop

```c
rade_initialize();
struct rade *r = rade_open("", RADE_VERBOSE_0);

int n_features = rade_n_features_in_out(r);
int n_eoo      = rade_n_eoo_bits(r);

RADE_COMP rx_in[rade_nin_max(r)];
float     features_out[n_features];
float     eoo_out[n_eoo];

for (;;) {
    int nin = rade_nin(r);                       /* call before every rade_rx() */
    read_iq(rx_in, nin);                         /* from the radio */

    int has_eoo = 0;
    int nout = rade_rx(r, features_out, &has_eoo, eoo_out, rx_in);

    if (nout) {
        write_to_fargan(features_out, nout);     /* write features to FARGAN vocoder */
    }
    if (has_eoo) {
        /* end of over — pass eoo_out[] to your text stack for decoding */
    }

    if (rade_sync(r)) {
        float foff = rade_freq_offset(r);
        float snr  = rade_snrdB_3k_est(r);
        (void)foff; (void)snr;
    }
}

rade_close(r);
rade_finalize();
```

### RADE V2 transmit loop

```c
rade_initialize();
struct rade *r = rade_open("", RADE_MODE_V2 | RADE_VERBOSE_0);

int n_features = rade_n_features_in_out(r);
int n_tx       = rade_n_tx_out(r);

float     features_in[n_features];
RADE_COMP tx_out[n_tx];

int bit_index = 0;
/* user-supplied 25 bits/s text encoded as BPSK bit stream */
float data_bits[] = { 1.0f, -1.0f, 1.0f, /* ... */ }; 

while (have_more_speech()) {
    rade_tx_set_data_symbol(r, data_bits[bit_index++ % n_bits]);
    fill_features(features_in);                  /* caller's feature extractor */
    int nout = rade_tx(r, tx_out, features_in);
    send_iq(tx_out, nout);
}

RADE_COMP eoo_out[rade_n_tx_eoo_out(r)];
rade_tx_eoo(r, eoo_out);
send_iq(eoo_out, rade_n_tx_eoo_out(r));

rade_close(r);
rade_finalize();
```

### RADE V2 receive loop

```c
rade_initialize();
struct rade *r = rade_open("", RADE_MODE_V2 | RADE_VERBOSE_0);

int n_features = rade_n_features_in_out(r);
RADE_COMP rx_in[rade_nin_max(r)];
float     features_out[n_features];

for (;;) {
    int nin = rade_nin(r);
    read_iq(rx_in, nin);

    int has_eoo = 0;
    int nout = rade_rx(r, features_out, &has_eoo, NULL, rx_in);

    if (nout) {
        write_to_fargan(features_out, nout);     /* write features to FARGAN vocoder */
        float sym = rade_rx_get_data_symbol(r);  /* +ve = 1, -ve = 0 */
        process_data_bit(sym > 0.0f ? 1 : 0);    /* user-supplied BPSK bit stream decoder */
    }
    if (has_eoo) { /* end of over */ }
}

rade_close(r);
rade_finalize();
```

---

## Function quick reference

| Function | Purpose |
| --- | --- |
| `rade_initialize` | initialize library (call first) |
| `rade_finalize` | tear down library (call last) |
| `rade_open` | create a Tx/Rx context (V1 or V2 via flags) |
| `rade_close` | destroy a context |
| `rade_version` | query major API version (breaking changes) |
| `rade_version_minor` | query minor API version (non-breaking additions) |
| `rade_n_tx_out` | Tx output samples per frame |
| `rade_n_tx_eoo_out` | Tx EOO output samples — V1 only |
| `rade_nin_max` | max Rx input samples (buffer sizing) |
| `rade_n_features_in_out` | feature floats per frame |
| `rade_n_eoo_bits` | number of EOO bits — V1 only |
| `rade_tx` | encode features → IQ samples |
| `rade_tx_set_eoo_bits` | V1 (aux text channel): set EOO bits |
| `rade_tx_eoo` | V1 (aux text channel): generate End-of-Over frame |
| `rade_tx_set_data_symbol` | V2 (aux text channel): set BPSK data symbol for next frame |
| `rade_nin` | input samples needed for next `rade_rx` |
| `rade_rx` | decode IQ samples → features (+ EOO on V1) |
| `rade_rx_get_data_symbol` | V2 (aux text channel): get received BPSK data symbol |
| `rade_sync` | is the Rx in sync? |
| `rade_freq_offset` | current Rx frequency offset |
| `rade_snrdB_3k_est` | current Rx SNR estimate (dB, float) |
| `rade_set_disable_unsync` | test mode: disable unsync |
| `rade_rx_set_agc` | V2: enable/disable Rx input AGC (on by default) |
