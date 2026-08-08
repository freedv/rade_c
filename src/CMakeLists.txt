include_directories(${CMAKE_CURRENT_SOURCE_DIR})

# LPCNet feature extraction tool
add_executable(lpcnet_demo lpcnet_demo.c)
target_link_libraries(lpcnet_demo opus m)

# DSP source files
set(RADE_DSP_SOURCES
    rade_dsp.c
    rade_ofdm.c
    rade_bpf.c
    rade_acq.c
    rade_tx.c
    rade_rx.c
)

# RADE V2 ML inference sources (encoder, decoder, frame-sync)
set(RADE_V2_ML_SOURCES
    rade_enc_v2.c
    rade_dec_v2.c
    rade_sync.c
    rade_enc_v2_data.c
    rade_dec_v2_data.c
    rade_sync_data.c
)

# RADE V2 DSP sources (OFDM modulator, transmitter, receiver)
set(RADE_V2_DSP_SOURCES
    rade_v2_ofdm.c
    rade_tx_v2.c
    rade_rx_v2.c
)

# RADE library
add_library(rade SHARED
    rade_api.c
    rade_enc.c
    rade_dec.c
    rade_enc_data.c
    rade_dec_data.c
    ${RADE_DSP_SOURCES}
    ${RADE_V2_ML_SOURCES}
    ${RADE_V2_DSP_SOURCES}
)
target_link_libraries(rade opus m)
target_compile_definitions(rade PRIVATE -DIS_BUILDING_RADE_API=1)

set_target_properties(rade PROPERTIES
    VERSION 0.1
    SOVERSION 0.1
    PUBLIC_HEADER "rade_api.h"
)

if(NOT WIN32)

# Standalone transmitter
add_executable(radae_tx radae_tx.c)
target_link_libraries(radae_tx rade opus m)

# Standalone receiver
add_executable(radae_rx radae_rx.c)
target_link_libraries(radae_rx rade opus m)

# Utility: convert real baseband to complex IQ
add_executable(real2iq real2iq.c)
target_link_libraries(real2iq m)

# WAV demodulator: WAV in → demod → WAV out
add_executable(rade_rx_wav rade_rx_wav.c)
target_link_libraries(rade_rx_wav rade opus m)

# WAV modulator: WAV in → features → RADE encode → OFDM mod → WAV out
add_executable(rade_tx_wav rade_tx_wav.c)
target_link_libraries(rade_tx_wav rade opus m)

# BPF test tool
add_executable(rade_bpf_test rade_bpf_test.c kiss_fft.c kiss_fftr.c)
target_link_libraries(rade_bpf_test rade opus m)

add_executable(rade_bpf_filter rade_bpf_filter.c)
target_link_libraries(rade_bpf_filter rade m)

# BER test tool: QPSK symbol BER test for modem equalisation code
add_executable(rade_ber_test rade_ber_test.c)
target_link_libraries(rade_ber_test rade m)

# V1 text round-trip test: set callsign → EOO TX → OFDM demod → decode
add_executable(rade_v1_text_test rade_v1_text_test.c)
target_link_libraries(rade_v1_text_test rade m)

# V2 text round-trip test: stream "hello world" via BPSK data symbol channel
add_executable(rade_v2_text_test rade_v2_text_test.c)
target_link_libraries(rade_v2_text_test rade opus m)

# V2 decoder test: reads latents from stdin, writes features to stdout
add_executable(rade_dec_v2_test rade_dec_v2_test.c)
target_link_libraries(rade_dec_v2_test rade opus m)

# V2 encoder test: reads features from stdin, writes latents to stdout
add_executable(rade_enc_v2_test rade_enc_v2_test.c)
target_link_libraries(rade_enc_v2_test rade opus m)


endif(NOT WIN32)
