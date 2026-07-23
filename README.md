# C Port of RADE

A C library and set of tools implementing RADE V1 and V2. It was derived from the [reference Python implementation](https://github.com/drowe67/radae) with the assistance of Claude Code, reviewed and tested by the FreeDV team. It passes the same [suite of automated tests](https://github.com/drowe67/radae/pull/66) as the Python version.

Tested on Linux and macOS.

## ⚠️ RADE V2 Status

RADE V2 is under active development. The waveform, model weights, and API are subject to change without notice, and future versions will not be backwards compatible with the current implementation.

Known issues are under investigation. On-air use is not recommended at this stage, and the FreeDV team is not able to provide support for pre-release V2 deployments. Any on-air V2 signals should be considered premature use of the development waveform and are not part of official FreeDV development activity.

The official V2 status will be announced on the [FreeDV blog](https://freedv.org/blog/).

## Pipeline Overview

RADE (Radio AutoEncoder) is a neural codec for transmitting speech over HF radio channels. Speech is converted to feature vectors by the FARGAN vocoder (built as part of Opus), encoded by a neural encoder, modulated onto an OFDM waveform, and transmitted as IQ samples. The receive path reverses this: IQ samples are demodulated, decoded by a neural decoder, and synthesised back to speech by FARGAN.

```
  Transmit:
  speech WAV ──► lpcnet_demo ──► features ──► radae_tx ──► IQ @ 8 kHz ──► radio
              (16 kHz)                                      (radio interface)

  Receive:
  speech WAV ◄── lpcnet_demo ◄── features ◄── radae_rx ◄── IQ @ 8 kHz ◄── radio
              (16 kHz)                                      (radio interface)
```

The convenience tools `rade_tx_wav` and `rade_rx_wav` wrap this entire pipeline
in a single command (WAV in, WAV out). For integration into SDR applications,
the `rade_api.h` C API gives direct access to each stage; see
[RadeAPIUse.md](RadeAPIUse.md) for details.

## Build

```
cd rade_c
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc) # or -j$(sysctl -n hw.logicalcpu) on macOS
```

## IQ Pipeline

The primary interface is a streaming IQ pipeline using `radae_tx` and `radae_rx`.
The radio interface — IQ samples produced by `radae_tx` and consumed by `radae_rx` — is
complex float32 (interleaved I,Q) at 8000 Hz. Speech I/O runs at 16000 Hz.

### RADE V1

#### Transmit: WAV → IQ

```
sox ../input_sample.wav -r 16000 -t .s16 -c 1 - | \
  ./src/lpcnet_demo -features /dev/stdin - | \
  ./src/radae_tx > tx1.iq
```

#### Receive: IQ → WAV

```
cat tx1.iq | \
  ./src/radae_rx | \
  ./src/lpcnet_demo -fargan-synthesis /dev/stdin - | \
  sox -t .s16 -r 16000 -c 1 - decoded1.wav
```

### RADE V2

#### Transmit: WAV → IQ

```
sox ../input_sample.wav -r 16000 -t .s16 -c 1 - | \
  ./src/lpcnet_demo -features /dev/stdin - | \
  ./src/radae_tx --v2 > tx2.iq
```

#### Receive: IQ → WAV

```
cat tx2.iq | \
  ./src/radae_rx --v2 | \
  ./src/lpcnet_demo -fargan-synthesis /dev/stdin - | \
  sox -t .s16 -r 16000 -c 1 - decoded2.wav
```

## WAV Convenience Tools

These tools wrap the full pipeline for simple WAV-in, WAV-out use, handling
the real→IQ conversion internally. Useful for quick tests with off-air recordings.

### Quick Start

The simplest way to try RADE is with the WAV convenience tools. From the build directory:

```
# RADE V1
./src/rade_tx_wav ../input_sample.wav tx_rade1.wav
./src/rade_rx_wav tx_rade1.wav decoded_rade1.wav

# RADE V2
./src/rade_tx_wav --v2 ../input_sample.wav tx_rade2.wav
./src/rade_rx_wav --v2 tx_rade2.wav decoded_rade2.wav
```

This encodes `input_sample.wav` to a RADE waveform and decodes it back to speech —
no additional tools required.

### Real-valued input (SSB radio or off-air WAV)

`rade_rx_wav` accepts a real-valued 8 kHz WAV file directly — for example,
audio recorded from a conventional SSB receiver or a KiwiSDR. Use sox to
resample to 8 kHz first if needed:

```
sox offair.wav -r 8000 -c 1 offair_8k.wav
./src/rade_rx_wav --v2 offair_8k.wav decoded.wav
```

If integrating at the API level, note that real-valued input requires a
different scaling factor than complex IQ — see `RADE_INT16_SCALE` in
`rade_api.h` for the full rationale, and `src/rade_rx_wav.c` for a
worked example.

### rade_tx_wav: Speech WAV → RADE WAV

```
rade_tx_wav [--v2] [-v 0|1] <input.wav> <output.wav>
```

### rade_rx_wav: RADE WAV → Speech WAV

```
rade_rx_wav [--v2] [-v 0|1|2|3] <input.wav> <output.wav>
```

## Files

### Common

| File                | Purpose                                             |
| ------------------- | --------------------------------------------------- |
| `src/rade_api.h`    | Public API                                          |
| `src/rade_api.c`    | API implementation (V1/V2 dispatch)                 |
| `src/radae_tx.c`    | Standalone transmitter executable                   |
| `src/radae_rx.c`    | Standalone receiver executable                      |
| `src/lpcnet_demo.c` | Feature extraction / vocoder synthesis              |
| `src/real2iq.c`     | Real baseband → complex IQ converter                |
| `src/rade_dsp.h/c`  | Complex math utilities, constants, pilot generation |
| `src/rade_bpf.h/c`  | Complex bandpass filter                             |

### RADE V1

| File                  | Purpose                                          |
| --------------------- | ------------------------------------------------ |
| `src/rade_ofdm.h/c`   | OFDM modulation/demodulation                     |
| `src/rade_acq.h/c`    | Acquisition and pilot detection                  |
| `src/rade_tx.h/c`     | Transmitter internals                            |
| `src/rade_rx.h/c`     | Receiver with sync state machine                 |
| `src/rade_enc.h/c`    | Neural encoder                                   |
| `src/rade_dec.h/c`    | Neural decoder                                   |
| `src/rade_enc_data.c` | Encoder weights                                  |
| `src/rade_dec_data.c` | Decoder weights                                  |

### RADE V2

| File                     | Purpose                                          |
| ------------------------ | ------------------------------------------------ |
| `src/rade_v2_ofdm.h/c`   | OFDM modulation/demodulation                     |
| `src/rade_tx_v2.h/c`     | Transmitter internals                            |
| `src/rade_rx_v2.h/c`     | Receiver with sync state machine                 |
| `src/rade_enc_v2.h/c`    | Neural encoder                                   |
| `src/rade_dec_v2.h/c`    | Neural decoder                                   |
| `src/rade_sync.h/c`      | Frame synchronisation                            |
| `src/rade_enc_v2_data.c` | Encoder weights                                  |
| `src/rade_dec_v2_data.c` | Decoder weights                                  |
| `src/rade_sync_data.c`   | Sync weights                                     |

## Verifying RADE Integration

Verification of your RADE integration is essential before any on-air use. A loss test confirms that feature vectors are passing correctly through your encode/decode pipeline, catching issues such as dropped sample buffers or signal processing errors before they manifest as degraded audio on air.

Before testing a hardware or software integration, establish a software-only loss baseline using the C port. This is the C port equivalent of the [reference Python verification](https://github.com/drowe67/radae/blob/main/README.md#verifying-rade-integration) in the radae repo.

Run from `rade_c/build` (requires the `radae` Python repo at `~/radae` for `loss.py`):

```
cd rade_c/build
./src/lpcnet_demo -features ../wav/all.wav features_in.f32
cat features_in.f32 | ./src/radae_tx --v2 > tx_c.f32
cat tx_c.f32 | ./src/radae_rx --v2 -v 0 > features_rx_c.f32
PYTHONPATH=~/radae python3 ~/radae/loss.py features_in.f32 features_rx_c.f32 --clip_start 100 --clip_end 300
```

Expected output (software-only reference, `wav/all.wav`, model `250725`):
```
loss: 0.080 start: 224 acq_time:  1.24 s
```

This matches the Python reference result (loss: 0.081) to within ±10%. When testing a real integration, a loss within ±10% of this figure is considered a pass.

## Automated Testing

A suite of ctests runs automatically on every GitHub push (Linux x86 and ARM). The tests cover V1 and V2 encode/decode pipelines, channel conditions (AWGN, MPP, MPG, MPD), acquisition, SNR estimation, EOO detection, BER, and the WAV convenience tools.

To run the tests locally, the [radae](https://github.com/drowe67/radae) Python reference repo is required:

```
cd ~
git clone https://github.com/drowe67/radae.git
cd radae && mkdir build && cd build
cmake -DRADE_C_BUILD_DIR=~/rade_c/build ..
ctest -R rade_c
```

## Directory Structure

```
rade_c/
├── CMakeLists.txt
├── cmake/
│   └── BuildOpus.cmake
└── src/
    ├── CMakeLists.txt
    ├── rade_api.h             # Public API
    ├── rade_api.c             # API implementation
    ├── radae_tx.c             # Transmitter executable
    ├── radae_rx.c             # Receiver executable
    ├── lpcnet_demo.c          # Feature extraction / vocoder synthesis
    ├── real2iq.c              # Real → IQ converter
    ├── rade_dsp.h/c           # DSP primitives
    ├── rade_bpf.h/c           # Bandpass filter
    ├── rade_ofdm.h/c          # V1 OFDM mod/demod
    ├── rade_acq.h/c           # V1 acquisition
    ├── rade_tx.h/c            # V1 transmitter internals
    ├── rade_rx.h/c            # V1 receiver internals
    ├── rade_enc.h/c           # V1 neural encoder
    ├── rade_dec.h/c           # V1 neural decoder
    ├── rade_enc_data.c        # V1 encoder weights
    ├── rade_dec_data.c        # V1 decoder weights
    ├── rade_v2_ofdm.h/c       # V2 OFDM mod/demod
    ├── rade_tx_v2.h/c         # V2 transmitter internals
    ├── rade_rx_v2.h/c         # V2 receiver internals
    ├── rade_enc_v2.h/c        # V2 neural encoder
    ├── rade_dec_v2.h/c        # V2 neural decoder
    ├── rade_sync.h/c          # V2 frame sync
    ├── rade_enc_v2_data.c     # V2 encoder weights
    ├── rade_dec_v2_data.c     # V2 decoder weights
    └── rade_sync_data.c       # V2 sync weights
```
