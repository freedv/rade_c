# rade_c ctests (moved from the radae repo, where they were enabled by RADE_C_BUILD_DIR).
#
# The tests use radae's Python reference, models, scripts and wav files, so they need a
# radae checkout and build, pinned in CI to RADAE_REF in .github/workflows/run_ctest.yml:
#
#   cmake -DRADAE_DIR=~/radae ..         (radae built in ~/radae/build)
#   ctest -V                             (always serial, the tests share files in RADAE_DIR)
#
# RADAE_DIR:        radae checkout; the tests cd here and read/write files in it
# RADAE_BUILD_DIR:  radae build, for lpcnet_demo and ch (default ${RADAE_DIR}/build)
# CMAKE_BINARY_DIR: this rade_c build
# CMAKE_SOURCE_DIR: this rade_c checkout (C only test scripts are in test/)

if(NOT RADAE_BUILD_DIR)
    set(RADAE_BUILD_DIR ${RADAE_DIR}/build)
endif()
message(STATUS "rade_c ctests enabled: RADAE_DIR=${RADAE_DIR} RADAE_BUILD_DIR=${RADAE_BUILD_DIR}")


# basic test of streaming Tx/Rx, compare to vanilla Tx in inference.py
add_test(NAME rade_c_v1_tx_basic
        COMMAND sh -c "cd ${RADAE_DIR}; \
                       ./inference.sh model19_check3/checkpoints/checkpoint_epoch_100.pth wav/brian_g8sez.wav /dev/null \
                       --rate_Fs --pilots --pilot_eq --eq_ls --cp 0.004 --bottleneck 3 --auxdata --write_rx rx.f32 --correct_freq_offset; \
                       cat features_in.f32 | ${CMAKE_BINARY_DIR}/src/radae_tx > rx.f32
                       cat rx.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx > features_txs_out.f32; \
                       python3 loss.py features_in.f32 features_txs_out.f32 --loss_test 0.15 --acq_time_test 0.5 --clip_start 5")
                       set_tests_properties(rade_c_v1_tx_basic PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# TODO need unit test for band pass filter, Python test, C unit test

# SNR=-2dB AWGN
add_test(NAME rade_c_v1_rx_awgn
        COMMAND sh -c "cd ${RADAE_DIR}; \
                       ./inference.sh model19_check3/checkpoints/checkpoint_epoch_100.pth wav/all.wav /dev/null \
                       --EbNodB 1 --freq_offset 13 \
                       --rate_Fs --pilots --pilot_eq --eq_ls --cp 0.004 --bottleneck 3 --time_offset -16 --write_rx rx.f32  \
                       --prepend_noise 1 --append_noise 3 --end_of_over --auxdata --correct_freq_offset; \
                       cat rx.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx > features_rx_out.f32; \
                       python3 loss.py features_in.f32 features_rx_out.f32 --loss 0.3 --acq_time_test 1.0 --clip_end 300")
                       set_tests_properties(rade_c_v1_rx_awgn PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# SNR=0dB MPP
# End of over detection is not always reliable on MPP, so run-on timer terminates over, --clip_end removes garbage at end
# We don't don't bother checking acquisition time on this channel, as it's a severe case.
add_test(NAME rade_c_v1_rx_mpp
        COMMAND sh -c "cd ${RADAE_DIR}; \
                       test/make_g.sh; \
                       ./inference.sh model19_check3/checkpoints/checkpoint_epoch_100.pth wav/all.wav /dev/null \
                       --rate_Fs --pilots --pilot_eq --eq_ls --cp 0.004 --bottleneck 3 --time_offset -16 \
                       --EbNodB 3 --freq_offset -11 --g_file g_mpp.f32 --write_rx rx.f32 \
                       --prepend_noise 1 --append_noise 3 --end_of_over --auxdata --correct_freq_offset; \
                       cat rx.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --disable_unsync 5.0 > features_rx_out.f32; \
                       python3 loss.py features_in.f32 features_rx_out.f32 --loss 0.35 --clip_end 300")
                       set_tests_properties(rade_c_v1_rx_mpp PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# SNR=0dB MPG.  We disable_unsync as we don't really care if we re-sync on long fades - user won't care much.  Main aim is to make sure loss is OK
# in this channel
add_test(NAME rade_c_v1_rx_mpg
        COMMAND sh -c "cd ${RADAE_DIR}; \
                       test/make_g.sh; \
                       ./inference.sh model19_check3/checkpoints/checkpoint_epoch_100.pth wav/all.wav /dev/null \
                       --rate_Fs --pilots --pilot_eq --eq_ls --cp 0.004 --bottleneck 3 --time_offset -16 \
                       --EbNodB 3 --freq_offset -11 --g_file g_mpg.f32 --write_rx rx.f32 \
                       --prepend_noise 1 --append_noise 3 --end_of_over --auxdata --correct_freq_offset; \
                       cat rx.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --disable_unsync 5.0 > features_rx_out.f32; \
                       python3 loss.py features_in.f32 features_rx_out.f32 --loss 0.3 --clip_end 300")
                       set_tests_properties(rade_c_v1_rx_mpg PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# SNR=3dB MPD, nasty channel that is fast fading but generally high SNR - so mission here is "don't break" rather than low SNR
add_test(NAME rade_c_v1_rx_mpd
        COMMAND sh -c "cd ${RADAE_DIR}; \
                       test/make_g.sh; \
                       ./inference.sh model19_check3/checkpoints/checkpoint_epoch_100.pth wav/all.wav /dev/null \
                       --rate_Fs --pilots --pilot_eq --eq_ls --cp 0.004 --bottleneck 3 --time_offset -16 \
                       --EbNodB 6 --freq_offset -28 --g_file g_mpd.f32 --write_rx rx.f32 \
                       --prepend_noise 1 --append_noise 3 --end_of_over --auxdata --correct_freq_offset; \
                       cat rx.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --disable_unsync 5.0 > features_rx_out.f32; \
                       python3 loss.py features_in.f32 features_rx_out.f32 --loss 0.3 --clip_end 300")
                       set_tests_properties(rade_c_v1_rx_mpd PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# SNR=-2dB AWGN ~5 Hz/min = 5/60 Hz/s freq drift
add_test(NAME rade_c_v1_rx_dfdt
        COMMAND sh -c "cd ${RADAE_DIR}; \
                      ./inference.sh model19_check3/checkpoints/checkpoint_epoch_100.pth wav/all.wav /dev/null \
                       --EbNodB 1 --freq_offset 13 --df_dt 0.1 \
                       --rate_Fs --pilots --pilot_eq --eq_ls --cp 0.004 --bottleneck 3 --time_offset -16 --write_rx rx.f32  \
                       --prepend_noise 1 --append_noise 3 --end_of_over --auxdata; \
                       cat rx.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx > features_rx_out.f32; \
                       python3 loss.py features_in.f32 features_rx_out.f32 --loss 0.3 --acq_time_test 0.8 --clip_end 100")
                       set_tests_properties(rade_c_v1_rx_dfdt PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# SNR=7dB ability to handle small differences in sample rate between tx and rx (delta Fs)
add_test(NAME rade_c_v1_rx_dfs
        COMMAND sh -c "cd ${RADAE_DIR}; \
                       ./inference.sh model19_check3/checkpoints/checkpoint_epoch_100.pth wav/brian_g8sez.wav /dev/null \
                       --EbNodB 10 --freq_offset 11 \
                       --rate_Fs --pilots --pilot_eq --eq_ls --cp 0.004 --bottleneck 3 --auxdata --write_rx rx.f32 --correct_freq_offset; \
                       cat rx.f32 | python3 f32toint16.py --scale 8192 | sox -t .s16 -r 8000 -c 2 - -t .s16 -r 8001 -c 2 - | python3 int16tof32.py > rx_.f32; \
                       cat rx_.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx > features_rxs_out.f32; \
                       python3 loss.py features_in.f32 features_rxs_out.f32 --loss_test 0.15 --acq_time_test 0.5")
                       set_tests_properties(rade_c_v1_rx_dfs PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# Test ability to handle buffer slips due to sample clock offsets, rx ADC clock > tx ADC clock.  We make sample clock error larger than 200ppm spec
# in order to exercise code.  Nice thing about "nin" design is it allows us to get meaningful "loss.py" results, ie no frames are lost.  We're
# really just trying to exercise the slip code here, not too concerned about loss.  There should be a noticable transition in tmax in each test as
# it hits the upper or lower limit
add_test(NAME rade_c_v1_rx_slip_plus
        COMMAND sh -c "cd ${RADAE_DIR}; \
                       ./inference.sh model19_check3/checkpoints/checkpoint_epoch_100.pth wav/brian_g8sez.wav /dev/null \
                       --EbNodB 10 --freq_offset 11 \
                       --rate_Fs --pilots --pilot_eq --eq_ls --cp 0.004 --bottleneck 3 --auxdata --write_rx rx.f32 --correct_freq_offset --prepend_noise 0.06; \
                       cat rx.f32 | python3 f32toint16.py --scale 8192 | sox -t .s16 -r 8000 -c 2 - -t .s16 -r 8005 -c 2 - | python3 int16tof32.py > rx_.f32; \
                       cat rx_.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx > features_rxs_out.f32; \
                       python3 loss.py features_in.f32 features_rxs_out.f32 --loss_test 0.2 --acq_time_test 1.0")
                       set_tests_properties(rade_c_v1_rx_slip_plus PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# Test bugfix for issue where a combination of timing slips and dropped frames over a long enough
# period of time results in the RADE DSP logic being unable to regain sync.
add_test(NAME rade_c_v1_rx_slip_plus_drops
         COMMAND sh -c "cd ${RADAE_DIR}; \
                        sox wav/long_qso.wav -t .s16 -r 8020 -c 1 - | \
                          python3 int16tof32.py --zeropad | \
                          ${CMAKE_BINARY_DIR}/src/radae_rx 2>&1 >/dev/null | \
                          tail -n2 | \
                          grep 'state:       sync'")

# Test ability to handle buffer slips due to sample clock offsets, rx ADC clock < tx ADC clock
add_test(NAME rade_c_v1_rx_slip_minus
        COMMAND sh -c "cd ${RADAE_DIR}; \
                       ./inference.sh model19_check3/checkpoints/checkpoint_epoch_100.pth wav/brian_g8sez.wav /dev/null \
                       --EbNodB 10 --freq_offset 31 \
                       --rate_Fs --pilots --pilot_eq --eq_ls --cp 0.004 --bottleneck 3 --auxdata --write_rx rx.f32 --correct_freq_offset --prepend_noise 0.11; \
                       cat rx.f32 | python3 f32toint16.py --scale 8192 | sox -t .s16 -r 8000 -c 2 - -t .s16 -r 7995 -c 2 - | python3 int16tof32.py > rx_.f32; \
                       cat rx_.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx > features_rxs_out.f32; \
                       python3 loss.py features_in.f32 features_rxs_out.f32 --loss_test 0.25 --acq_time_test 1.0")
                       set_tests_properties(rade_c_v1_rx_slip_minus PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# Characterise run time using full simplex Tx stack (C core encoder version).  No pass/fail, just for characterisation of run time
add_test(NAME rade_c_v1_tx_stack_c
        COMMAND bash -c "WAV='wav/all.wav'; cd ${RADAE_DIR}; \
                       \\time -o log.txt -f '%e' ${RADAE_BUILD_DIR}/src/lpcnet_demo -features $WAV - | 
                       ${CMAKE_BINARY_DIR}/src/radae_tx > /dev/null; \
                       RUN_TIME=$(cat log.txt); DUR=$(soxi -D $WAV); percent=$(python3 -c \"percent=100*$RUN_TIME/$DUR; print('%f' % percent)\"); \
                       printf \"\nrun time: %5.2f duration: %5.2f percent CPU: %5.2f\n\n\" $RUN_TIME $DUR $percent ")

# As above but with C core decoder for comparison
add_test(NAME rade_c_v1_rx_stack_c
        COMMAND bash -c "WAV='wav/all.wav'; cd ${RADAE_DIR}; \
                       ./inference.sh model19_check3/checkpoints/checkpoint_epoch_100.pth $WAV /dev/null \
                       --EbNodB 10 --freq_offset 13 --df_dt -0.1 --auxdata \
                       --rate_Fs --pilots --pilot_eq --eq_ls --cp 0.004 --bottleneck 3 --time_offset -16 --write_rx rx.f32  \
                       --prepend_noise 1 --append_noise 3 --end_of_over --correct_freq_offset ; \
                       \\time -o log.txt -f '%e' cat rx.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx | \
                       ${RADAE_BUILD_DIR}/src/lpcnet_demo -fargan-synthesis - /dev/null; \
                       RUN_TIME=$(cat log.txt); DUR=$(soxi -D $WAV); percent=$(python3 -c \"percent=100*$RUN_TIME/$DUR; print('%f' % percent)\"); \
                       printf \"\nrun time: %5.2f duration: %5.2f percent CPU: %5.2f\n\n\" $RUN_TIME $DUR $percent ")

# EOO data: C tx & rx, no noise. Note Python radae_txe.py just generates eoo_tx.f32 for C radae_tx
add_test(NAME rade_c_v1_eoo_data_c
        COMMAND sh -c "cd ${RADAE_DIR}; \
                       ${RADAE_BUILD_DIR}/src/lpcnet_demo -features wav/brian_g8sez.wav features_in.f32; \
                       cat features_in.f32 | python3 radae_txe.py --eoo_data_test > /dev/null; \
                       cat features_in.f32 | ${CMAKE_BINARY_DIR}/src/radae_tx > rx.f32; \
                       cat rx.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx > /dev/null; \
                       python3 eoo_ber.py eoo_tx.f32 eoo_rx.f32")
                       set_tests_properties(rade_c_v1_eoo_data_c PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# C tx & rx, over a multipath channel, we set up 5 "overs", each with an EOO chunk of data.  Just one of them needs
# to have a BER < 5% for a PASS.  About 6dB SNR
add_test(NAME rade_c_v1_eoo_data_mpp
        COMMAND sh -c "cd ${RADAE_DIR}; test/make_g.sh; \
                       ${RADAE_BUILD_DIR}/src/lpcnet_demo -features wav/brian_g8sez.wav features_in.f32; \
                       cat features_in.f32 | python3 radae_txe.py --eoo_data_test > /dev/null; \
                       cat features_in.f32 | ${CMAKE_BINARY_DIR}/src/radae_tx > tx.f32; \
                       cat tx.f32 tx.f32 tx.f32 tx.f32 tx.f32 > tx_2.f32;
                       cat tx_2.f32 | python3 f32toint16.py --real --scale 8192 > tx.raw; \
                       ${RADAE_BUILD_DIR}/src/ch tx.raw rx.raw --No -24 --mpp --fading_dir .; \
                       cat rx.raw | python3 int16tof32.py --zeropad > rx.f32; \
                       cat rx.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx > /dev/null; \
                       python3 eoo_ber.py eoo_tx.f32 eoo_rx.f32")
                       set_tests_properties(rade_c_v1_eoo_data_mpp PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# BPF test - only one iteration
add_test(NAME rade_c_v1_bpf_singlepass
         COMMAND ${CMAKE_BINARY_DIR}/src/rade_bpf_test 1 8000)

# BPF test - filter in small chunks
add_test(NAME rade_c_v1_bpf_chunks
         COMMAND ${CMAKE_BINARY_DIR}/src/rade_bpf_test 10 960)

# SNR estimator spot tests: check C radae_rx reports SNR3k within 3 dB of inference.sh Measured SNR3k
add_test(NAME rade_c_v1_snr_est_high
         COMMAND sh -c "cd ${RADAE_DIR}; \
                       ./inference.sh model19_check3/checkpoints/checkpoint_epoch_100.pth wav/brian_g8sez.wav /dev/null \
                       --rate_Fs --pilots --pilot_eq --eq_ls --cp 0.004 --bottleneck 3 --auxdata --write_rx rx.f32 \
                       --correct_freq_offset --EbNodB 10 >snr_inf_c_high.txt 2>/dev/null; \
                       SNR3K=\$(grep Measured snr_inf_c_high.txt | awk '{print \$4}'); \
                       cat rx.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx 2>&1 >/dev/null | python3 test/check_snr.py --snr3k \$SNR3K --tol 2.0")
         set_tests_properties(rade_c_v1_snr_est_high PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

add_test(NAME rade_c_v1_snr_est_low
         COMMAND sh -c "cd ${RADAE_DIR}; \
                       ./inference.sh model19_check3/checkpoints/checkpoint_epoch_100.pth wav/brian_g8sez.wav /dev/null \
                       --rate_Fs --pilots --pilot_eq --eq_ls --cp 0.004 --bottleneck 3 --auxdata --write_rx rx.f32 \
                       --correct_freq_offset --EbNodB 5 >snr_inf_c_low.txt 2>/dev/null; \
                       SNR3K=\$(grep Measured snr_inf_c_low.txt | awk '{print \$4}'); \
                       cat rx.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx 2>&1 >/dev/null | python3 test/check_snr.py --snr3k \$SNR3K --tol 2.0")
         set_tests_properties(rade_c_v1_snr_est_low PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# DIGITAL SYMBOL BER TESTS (C port) ------------------------------------------
# Substitute random QPSK symbols (+/-1) for encoder output, apply channel model,
# demodulate, and check BER against theoretical QPSK/MPP curves with 2 dB implementation loss.

# Noiseless: all bits must be correct
add_test(NAME rade_c_v1_ber
         COMMAND sh -c "cd ${RADAE_DIR}; \
                        ${CMAKE_BINARY_DIR}/src/rade_ber_test --EbNodB 100 --frames 100")
         set_tests_properties(rade_c_v1_ber PROPERTIES PASS_REGULAR_EXPRESSION "BER: 0.0000")

# AWGN: BER must be below theoretical QPSK target (with 2 dB implementation loss allowance)
add_test(NAME rade_c_v1_ber_awgn
         COMMAND sh -c "cd ${RADAE_DIR}; ${CMAKE_SOURCE_DIR}/test/rade_c_ber_awgn.sh ${CMAKE_BINARY_DIR}")
         set_tests_properties(rade_c_v1_ber_awgn PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# MPP: BER must be below theoretical two-path Rayleigh target (with 2 dB implementation loss allowance)
add_test(NAME rade_c_v1_ber_mpp
         COMMAND sh -c "cd ${RADAE_DIR}; ${CMAKE_SOURCE_DIR}/test/rade_c_ber_mpp.sh ${CMAKE_BINARY_DIR}")
         set_tests_properties(rade_c_v1_ber_mpp PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# MPP at high SNR: noise is negligible, so BER is set by how well the pilot EQ tracks
# the fading phase. Catches EQ regressions: correct interpolation 0.0007, one symbol
# lag (rade_c 667390a) 0.0023. Fixed limit, as the fading error floor is above theory.
add_test(NAME rade_c_v1_ber_mpp_high_snr
         COMMAND sh -c "cd ${RADAE_DIR}; test/make_g.sh; \
                        ${CMAKE_BINARY_DIR}/src/rade_ber_test --EbNodB 30 --frames 2000 --g_file g_mpp.f32 | \
                        awk '/BER/ { print; if ($2 < 0.0012) print \"PASS\" }'")
         set_tests_properties(rade_c_v1_ber_mpp_high_snr PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# V2 C port tests ----------------------------------------------------------------

# Test V2 C encoder: C encoder output fed to Python stateful decoder, check loss
add_test(NAME rade_c_v2_enc
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ${RADAE_BUILD_DIR}/src/lpcnet_demo -features wav/brian_g8sez.wav features_in.f32; \
             python3 -c \"import numpy as np; \
                 f=np.fromfile('features_in.f32',dtype=np.float32).reshape(-1,36); \
                 n=(len(f)//4)*4; \
                 f21=np.concatenate([f[:n,:20],-np.ones((n,1),dtype=np.float32)],axis=1); \
                 f21.flatten().tofile('features_v2_in.f32')\"; \
             cat features_v2_in.f32 | ${CMAKE_BINARY_DIR}/src/rade_enc_v2_test > z_v2_c.f32; \
             python3 stateful_encoder_v2.py 250725/checkpoints/checkpoint_epoch_200.pth \
                 features_in.f32 /dev/null --read_latent z_v2_c.f32 --loss_test 0.2")
         set_tests_properties(rade_c_v2_enc PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# Test V2 C decoder: Python stateful encoder latents fed to C decoder, compare with Python decoder
add_test(NAME rade_c_v2_dec
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ${RADAE_BUILD_DIR}/src/lpcnet_demo -features wav/brian_g8sez.wav features_in.f32; \
             python3 stateful_encoder_v2.py 250725/checkpoints/checkpoint_epoch_200.pth \
                 features_in.f32 features_v2_py.f32 --write_latent z_v2_py.f32; \
             cat z_v2_py.f32 | ${CMAKE_BINARY_DIR}/src/rade_dec_v2_test > features_v2_c_raw.f32; \
             python3 -c \"import numpy as np; \
                 f=np.fromfile('features_v2_c_raw.f32',dtype=np.float32).reshape(-1,21); \
                 out=np.concatenate([f[:,:20],np.zeros((len(f),16),dtype=np.float32)],axis=1); \
                 out.flatten().tofile('features_v2_c.f32')\"; \
             python3 loss.py features_in.f32 features_v2_py.f32 --features_hat2 features_v2_c.f32 --compare")
         set_tests_properties(rade_c_v2_dec PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# Test V2 C transmitter: compare IQ output to tx2.py reference using RMS difference
# EOO max diff threshold: 0.01 -- the SSB BPF is one continuous filter spanning the
# data->EOO boundary, so its memory carries the pre-existing ~1.2% data-side encoder
# float difference into the start of the EOO window as a decaying transient (observed
# peak ~0.006, decaying to ~1e-5 by the end of the 960-sample EOO window); a tight
# near-float32-precision threshold is no longer the right expectation here.
# Data diff_rms/sig_rms threshold: 3% (encoder float differences are ~1.2%)
add_test(NAME rade_c_v2_tx
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ${RADAE_BUILD_DIR}/src/lpcnet_demo -features wav/brian_g8sez.wav features_in.f32; \
             python3 tx2.py 250725/checkpoints/checkpoint_epoch_200.pth \
                 features_in.f32 tx2_py.f32; \
             cat features_in.f32 | ${CMAKE_BINARY_DIR}/src/radae_tx --v2 > tx2_c.f32; \
             python3 -c \"\
import numpy as np; \
py=np.fromfile('tx2_py.f32',dtype=np.complex64); \
c=np.fromfile('tx2_c.f32',dtype=np.complex64); \
n=min(len(py),len(c)); \
data_py=py[:n-960]; data_c=c[:n-960]; \
eoo_py=py[n-960:n]; eoo_c=c[n-960:n]; \
diff_rms=np.sqrt(np.mean(np.abs(data_py-data_c)**2)); \
sig_rms=np.sqrt(np.mean(np.abs(data_py)**2)); \
eoo_max=np.max(np.abs(eoo_py-eoo_c)); \
print(f'diff_rms/sig_rms: {diff_rms/sig_rms:.4f}  eoo_max_diff: {eoo_max:.2e}'); \
ok = diff_rms/sig_rms < 0.03 and eoo_max < 0.01; \
print('PASS' if ok else 'FAIL')\"")
         set_tests_properties(rade_c_v2_tx PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# Test V2 C receiver: C tx -> C rx pipeline. At high SNR (no noise) the
# decoder output loss vs the original vocoder features should be <0.2.
add_test(NAME rade_c_v2_rx
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ${RADAE_BUILD_DIR}/src/lpcnet_demo -features wav/brian_g8sez.wav features_in.f32; \
             cat features_in.f32 | ${CMAKE_BINARY_DIR}/src/radae_tx --v2 > tx2_c.f32; \
             cat tx2_c.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 > features_rx_c.f32; \
             python3 loss.py features_in.f32 features_rx_c.f32 --loss_test 0.2 --clip_start 200")
         set_tests_properties(rade_c_v2_rx PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# V2 C receiver AWGN high SNR
add_test(NAME rade_c_v2_rx_awgn
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ./inference.sh 250725/checkpoints/checkpoint_epoch_200.pth wav/all.wav /dev/null \
             --rate_Fs --latent-dim 56 --peak --cp 0.004 --time_offset -16 --correct_time_offset -16 \
             --auxdata --w1_dec 128 --write_rx rx_v2_c.f32 \
             --prepend_noise 1 --append_noise 2 --freq_offset 25 --correct_freq_offset; \
             cat rx_v2_c.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 > features_rx_v2_c.f32; \
             python3 loss.py features_in.f32 features_rx_v2_c.f32 --loss_test 0.15 \
             --acq_time_test 2.0 --clip_start 100 --clip_end 300")
         set_tests_properties(rade_c_v2_rx_awgn PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# V2 C receiver AWGN low SNR: EbNodB=1
add_test(NAME rade_c_v2_rx_awgn_low
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ./inference.sh 250725/checkpoints/checkpoint_epoch_200.pth wav/all.wav /dev/null \
             --rate_Fs --latent-dim 56 --peak --cp 0.004 --time_offset -16 --correct_time_offset -16 \
             --auxdata --w1_dec 128 --write_rx rx_v2_c.f32 \
             --prepend_noise 1 --append_noise 2 --freq_offset 25 --correct_freq_offset \
             --EbNodB 1; \
             cat rx_v2_c.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 > features_rx_v2_c.f32; \
             python3 loss.py features_in.f32 features_rx_v2_c.f32 --loss_test 0.45 --clip_start 100 --clip_end 300")
         set_tests_properties(rade_c_v2_rx_awgn_low PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# V2 C receiver MPP high SNR
add_test(NAME rade_c_v2_rx_mpp
         COMMAND sh -c "cd ${RADAE_DIR}; \
             test/make_g.sh; \
             ./inference.sh 250725/checkpoints/checkpoint_epoch_200.pth wav/all.wav /dev/null \
             --rate_Fs --latent-dim 56 --peak --cp 0.004 --time_offset -16 --correct_time_offset -16 \
             --auxdata --w1_dec 128 --write_rx rx_v2_c.f32 \
             --prepend_noise 1 --append_noise 2 --freq_offset 25 --correct_freq_offset \
             --g_file g_mpp.f32; \
             cat rx_v2_c.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 > features_rx_v2_c.f32; \
             python3 loss.py features_in.f32 features_rx_v2_c.f32 --loss_test 0.15 --clip_start 100 --clip_end 300")
         set_tests_properties(rade_c_v2_rx_mpp PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# V2 C receiver MPP low SNR: EbNodB=6
add_test(NAME rade_c_v2_rx_mpp_low
         COMMAND sh -c "cd ${RADAE_DIR}; \
             test/make_g.sh; \
             ./inference.sh 250725/checkpoints/checkpoint_epoch_200.pth wav/all.wav /dev/null \
             --rate_Fs --latent-dim 56 --peak --cp 0.004 --time_offset -16 --correct_time_offset -16 \
             --auxdata --w1_dec 128 --write_rx rx_v2_c.f32 \
             --prepend_noise 1 --append_noise 2 --freq_offset 25 --correct_freq_offset \
             --g_file g_mpp.f32 --EbNodB 6; \
             cat rx_v2_c.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 > features_rx_v2_c.f32; \
             python3 loss.py features_in.f32 features_rx_v2_c.f32 --loss_test 0.40 --clip_start 100 --clip_end 300")
         set_tests_properties(rade_c_v2_rx_mpp_low PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# V2 C receiver sample clock offset (rade_c Issue #27): no significant loss at +/-125 ppm,
# sync and decode at +/-250 ppm high SNR. The +/-125 ppm high SNR tests also check the
# rade_clock_offset_ppm() estimate. With the legacy IIR timing loop (radae_rx --timing_iir)
# all fail (PI/IIR loss: clean +/-125 ppm 0.09/0.12, MPP 0.30/0.8-1.0, +/-250 ppm 0.10/2.3-3.6).
add_test(NAME rade_c_v2_rx_samclk_slow
         COMMAND sh -c "cd ${RADAE_DIR}; ${CMAKE_SOURCE_DIR}/test/v2_c_samclk.sh ${CMAKE_BINARY_DIR}/src 7999 0.10 -125 15")
         set_tests_properties(rade_c_v2_rx_samclk_slow PROPERTIES PASS_REGULAR_EXPRESSION "PASS" FAIL_REGULAR_EXPRESSION "FAIL")
add_test(NAME rade_c_v2_rx_samclk_fast
         COMMAND sh -c "cd ${RADAE_DIR}; ${CMAKE_SOURCE_DIR}/test/v2_c_samclk.sh ${CMAKE_BINARY_DIR}/src 8001 0.10 125 15")
         set_tests_properties(rade_c_v2_rx_samclk_fast PROPERTIES PASS_REGULAR_EXPRESSION "PASS" FAIL_REGULAR_EXPRESSION "FAIL")
add_test(NAME rade_c_v2_rx_samclk_slow_mpp
         COMMAND sh -c "cd ${RADAE_DIR}; test/make_g.sh; \
             INF_OPTS='--g_file g_mpp.f32 --EbNodB 6' ${CMAKE_SOURCE_DIR}/test/v2_c_samclk.sh ${CMAKE_BINARY_DIR}/src 7999 0.35")
         set_tests_properties(rade_c_v2_rx_samclk_slow_mpp PROPERTIES PASS_REGULAR_EXPRESSION "PASS" FAIL_REGULAR_EXPRESSION "FAIL")
add_test(NAME rade_c_v2_rx_samclk_fast_mpp
         COMMAND sh -c "cd ${RADAE_DIR}; test/make_g.sh; \
             INF_OPTS='--g_file g_mpp.f32 --EbNodB 6' ${CMAKE_SOURCE_DIR}/test/v2_c_samclk.sh ${CMAKE_BINARY_DIR}/src 8001 0.35")
         set_tests_properties(rade_c_v2_rx_samclk_fast_mpp PROPERTIES PASS_REGULAR_EXPRESSION "PASS" FAIL_REGULAR_EXPRESSION "FAIL")
add_test(NAME rade_c_v2_rx_samclk_slow_250
         COMMAND sh -c "cd ${RADAE_DIR}; ${CMAKE_SOURCE_DIR}/test/v2_c_samclk.sh ${CMAKE_BINARY_DIR}/src 7998 0.15")
         set_tests_properties(rade_c_v2_rx_samclk_slow_250 PROPERTIES PASS_REGULAR_EXPRESSION "PASS" FAIL_REGULAR_EXPRESSION "FAIL")
add_test(NAME rade_c_v2_rx_samclk_fast_250
         COMMAND sh -c "cd ${RADAE_DIR}; ${CMAKE_SOURCE_DIR}/test/v2_c_samclk.sh ${CMAKE_BINARY_DIR}/src 8002 0.15")
         set_tests_properties(rade_c_v2_rx_samclk_fast_250 PROPERTIES PASS_REGULAR_EXPRESSION "PASS" FAIL_REGULAR_EXPRESSION "FAIL")

# V2 C receiver wrong carrier detector. The algorithm is tested by the v2_wrong_k_* Python tests; these
# check the C port matches. (1) C vs Python on the same signal: per-symbol rho within 0.01, identical
# acquisition veto and mistune decisions (AGC off in both, rx2.py's default)
add_test(NAME rade_c_v2_wrong_k_compare
         COMMAND sh -c "cd ${RADAE_DIR}; test/make_g.sh; \
             ${CMAKE_SOURCE_DIR}/test/v2_c_wrong_k_compare.sh ${CMAKE_BINARY_DIR}/src -45 --g_file g_mpp.f32 --EbNodB 6")
         set_tests_properties(rade_c_v2_wrong_k_compare PROPERTIES PASS_REGULAR_EXPRESSION "PASS" FAIL_REGULAR_EXPRESSION "FAIL")
# (2) all C chain over a real valued channel, default AGC on: radae_tx -> ch (-80 Hz, MPP, ~10 dB SNR3k)
# -> radae_rx. PASS if no sync and rade_mistune() = -1
add_test(NAME rade_c_v2_wrong_k_ch_mpp_neg
         COMMAND sh -c "cd ${RADAE_DIR}; test/make_g.sh; \
             ${CMAKE_SOURCE_DIR}/test/v2_c_wrong_k_ch.sh ${CMAKE_BINARY_DIR}/src -80 oor --mpp --fading_dir .")
         set_tests_properties(rade_c_v2_wrong_k_ch_mpp_neg PROPERTIES PASS_REGULAR_EXPRESSION "PASS" FAIL_REGULAR_EXPRESSION "FAIL")

# V2 C receiver: NaN, Inf and huge input samples are discarded and the receiver keeps working.
add_test(NAME rade_c_v2_rx_nonfinite
         COMMAND sh -c "cd ${RADAE_DIR}; ${CMAKE_SOURCE_DIR}/test/v2_c_nonfinite.sh ${CMAKE_BINARY_DIR}/src")
         set_tests_properties(rade_c_v2_rx_nonfinite PROPERTIES PASS_REGULAR_EXPRESSION "PASS" FAIL_REGULAR_EXPRESSION "FAIL")

# V2 C receiver EOO detection: tx2.py -> ch -> C rx, AWGN channel.
add_test(NAME rade_c_v2_rx_eoo
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ./tx2.sh 250725/checkpoints/checkpoint_epoch_200.pth wav/brian_g8sez.wav v2_eoo_tx2.f32; \
             cat v2_eoo_tx2.f32 | python3 f32toint16.py --real --scale 16383 | \
             ${RADAE_BUILD_DIR}/src/ch - - --No -24 | python3 int16tof32.py --zeropad > v2_eoo_rx2.f32; \
             cat v2_eoo_rx2.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 2>&1 >/dev/null")
         set_tests_properties(rade_c_v2_rx_eoo PROPERTIES PASS_REGULAR_EXPRESSION "End-of-over detected")

# V2 C receiver EOO detection: tx2.py -> ch -> C rx, MPP fading channel.
# scale 8192 (rather than 16383) + No -30 gives the same ~10dB SNR3k as the AWGN
# test above with zero clipping from multipath anti-fade peaks (16383 clips ~0.09%).
add_test(NAME rade_c_v2_rx_eoo_mpp
         COMMAND sh -c "cd ${RADAE_DIR}; \
             test/make_g.sh; \
             ./tx2.sh 250725/checkpoints/checkpoint_epoch_200.pth wav/brian_g8sez.wav v2_eoo_mpp_tx2.f32; \
             cat v2_eoo_mpp_tx2.f32 | python3 f32toint16.py --real --scale 8192 | \
             ${RADAE_BUILD_DIR}/src/ch - - --No -30 --mpp --fading_dir . | python3 int16tof32.py --zeropad > v2_eoo_mpp_rx2.f32; \
             cat v2_eoo_mpp_rx2.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 2>&1 >/dev/null")
         set_tests_properties(rade_c_v2_rx_eoo_mpp PROPERTIES PASS_REGULAR_EXPRESSION "End-of-over detected")

# V2 C receiver EOO detection: C tx (radae_tx) -> ch -> C rx, MPP fading channel.
add_test(NAME rade_c_v2_tx_eoo_mpp
         COMMAND sh -c "cd ${RADAE_DIR}; \
             test/make_g.sh; \
             ${RADAE_BUILD_DIR}/src/lpcnet_demo -features wav/brian_g8sez.wav features_in.f32; \
             cat features_in.f32 | ${CMAKE_BINARY_DIR}/src/radae_tx --v2 > v2_eoo_ctx.f32; \
             cat v2_eoo_ctx.f32 | python3 f32toint16.py --real --scale 8192 | \
             ${RADAE_BUILD_DIR}/src/ch - - --No -30 --mpp --fading_dir . | python3 int16tof32.py --zeropad > v2_eoo_ctx_rx.f32; \
             cat v2_eoo_ctx_rx.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 2>&1 >/dev/null")
         set_tests_properties(rade_c_v2_tx_eoo_mpp PROPERTIES PASS_REGULAR_EXPRESSION "End-of-over detected")

# V2 C receiver SNR estimator: high SNR (EbNodB=12, mirrors v2_snr_est_high)
add_test(NAME rade_c_v2_rx_snr_high
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ${RADAE_BUILD_DIR}/src/lpcnet_demo -features wav/david_vk5dgr.wav snr_feats.f32; \
             python3 inference.py 250725/checkpoints/checkpoint_epoch_200.pth snr_feats.f32 /dev/null \
             --latent-dim 56 --w1_dec 128 --auxdata --rate_Fs --cp 0.004 \
             --time_offset -16 --correct_time_offset -16 --peak \
             --EbNodB 12 --write_rx snr_rx_high.f32 --append_noise 1 > snr_inf_high.txt; \
             SNR3K=\$(grep Measured snr_inf_high.txt | awk '{print \$4}'); \
             cat snr_rx_high.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 \
             --write_snr_est snr_est_v2_c_high.f32 >/dev/null; \
             python3 check_snr_est.py \$SNR3K snr_est_v2_c_high.f32 3.0")
         set_tests_properties(rade_c_v2_rx_snr_high PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# V2 C receiver SNR estimator: low SNR (EbNodB=2, mirrors v2_snr_est_low)
add_test(NAME rade_c_v2_rx_snr_low
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ${RADAE_BUILD_DIR}/src/lpcnet_demo -features wav/david_vk5dgr.wav snr_feats.f32; \
             python3 inference.py 250725/checkpoints/checkpoint_epoch_200.pth snr_feats.f32 /dev/null \
             --latent-dim 56 --w1_dec 128 --auxdata --rate_Fs --cp 0.004 \
             --time_offset -16 --correct_time_offset -16 --peak \
             --EbNodB 2 --write_rx snr_rx_low.f32 --append_noise 1 > snr_inf_low.txt; \
             SNR3K=\$(grep Measured snr_inf_low.txt | awk '{print \$4}'); \
             cat snr_rx_low.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 \
             --write_snr_est snr_est_v2_c_low.f32 >/dev/null; \
             python3 check_snr_est.py \$SNR3K snr_est_v2_c_low.f32 2.0")
         set_tests_properties(rade_c_v2_rx_snr_low PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# V2 C receiver AGC: gain mismatch on a clean (no channel impairment) signal,
# C tx -> C rx. Mirrors v2_rx2_agc_mpp_high/low's gain values (4, 0.25) but on
# a clean channel so a gain-staging regression isn't masked by channel noise.
add_test(NAME rade_c_v2_rx_agc_clean_high
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ${RADAE_BUILD_DIR}/src/lpcnet_demo -features wav/all.wav features_in.f32; \
             cat features_in.f32 | ${CMAKE_BINARY_DIR}/src/radae_tx --v2 > tx2_c.f32; \
             cat tx2_c.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 --gain 4 > features_rx_v2_c.f32; \
             python3 loss.py features_in.f32 features_rx_v2_c.f32 --loss_test 0.10 --clip_start 100 --clip_end 300")
         set_tests_properties(rade_c_v2_rx_agc_clean_high PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

add_test(NAME rade_c_v2_rx_agc_clean_low
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ${RADAE_BUILD_DIR}/src/lpcnet_demo -features wav/all.wav features_in.f32; \
             cat features_in.f32 | ${CMAKE_BINARY_DIR}/src/radae_tx --v2 > tx2_c.f32; \
             cat tx2_c.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 --gain 0.25 > features_rx_v2_c.f32; \
             python3 loss.py features_in.f32 features_rx_v2_c.f32 --loss_test 0.095 --clip_start 100 --clip_end 300")
         set_tests_properties(rade_c_v2_rx_agc_clean_low PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# V2 C receiver AGC on MPP fading: Python tx (inference.sh, same as
# rade_c_v2_rx_mpp/_low) since it's the C rx's AGC under test, not the tx.
add_test(NAME rade_c_v2_rx_agc_mpp_high
         COMMAND sh -c "cd ${RADAE_DIR}; \
             test/make_g.sh; \
             ./inference.sh 250725/checkpoints/checkpoint_epoch_200.pth wav/all.wav /dev/null \
             --rate_Fs --latent-dim 56 --peak --cp 0.004 --time_offset -16 --correct_time_offset -16 \
             --auxdata --w1_dec 128 --write_rx rx_v2_c.f32 \
             --prepend_noise 1 --append_noise 2 --freq_offset 25 --correct_freq_offset \
             --g_file g_mpp.f32; \
             cat rx_v2_c.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 --gain 4 > features_rx_v2_c.f32; \
             python3 loss.py features_in.f32 features_rx_v2_c.f32 --loss_test 0.15 --clip_start 100 --clip_end 300")
         set_tests_properties(rade_c_v2_rx_agc_mpp_high PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

add_test(NAME rade_c_v2_rx_agc_mpp_low
         COMMAND sh -c "cd ${RADAE_DIR}; \
             test/make_g.sh; \
             ./inference.sh 250725/checkpoints/checkpoint_epoch_200.pth wav/all.wav /dev/null \
             --rate_Fs --latent-dim 56 --peak --cp 0.004 --time_offset -16 --correct_time_offset -16 \
             --auxdata --w1_dec 128 --write_rx rx_v2_c.f32 \
             --prepend_noise 1 --append_noise 2 --freq_offset 25 --correct_freq_offset \
             --g_file g_mpp.f32 --EbNodB 6; \
             cat rx_v2_c.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 --gain 0.25 > features_rx_v2_c.f32; \
             python3 loss.py features_in.f32 features_rx_v2_c.f32 --loss_test 0.40 --clip_start 100 --clip_end 300")
         set_tests_properties(rade_c_v2_rx_agc_mpp_low PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# V2 C receiver regression test for Issue #8 (loss varying with timing delay).
# Sweeps 3 points spanning the documented worst-case window (~16.8-17.8ms) and
# checks C receiver loss stddev stays well below the ~0.0026 seen before the
# AGC IIR-smoothing fix (empirically confirmed to catch the pre-fix bug).
add_test(NAME v2_c_loss_vs_delay
         COMMAND sh -c "cd ${RADAE_DIR}; \
             RADE_C=${CMAKE_BINARY_DIR}/src RESULTS=v2_c_loss_vs_delay.txt \
             ${CMAKE_SOURCE_DIR}/test/v2_c_timing.sh 0.010 0.020 2 2>&1 | \
             awk '/stddev:/{print ($NF<0.002)?\"PASS\":\"FAIL c_std=\"$NF}'")
         set_tests_properties(v2_c_loss_vs_delay PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# ota_test.sh with rade_c's rade_tx_wav/rade_rx_wav (--v2_c) instead of Python for
# RADE V2, exercising the same "ideal application" chirp-SSB-V1-V2 pipeline used for
# the real OTC hardware tests. Mirrors ota_test_awgn/ota_test_mpp above.
add_test(NAME ota_test_v2_c_awgn
        COMMAND sh -c "cd ${RADAE_DIR}; \
                       RADE_C=${CMAKE_BINARY_DIR}/src V2_C=1 ./test/ota_test_cal.sh ${RADAE_BUILD_DIR} wav/brian_g8sez.wav -24 0.4")

add_test(NAME ota_test_v2_c_mpp
        COMMAND sh -c "cd ${RADAE_DIR}; \
                       RADE_C=${CMAKE_BINARY_DIR}/src V2_C=1 ./test/ota_test_cal.sh ${RADAE_BUILD_DIR} wav/brian_g8sez.wav -30 0.45 --mpp --freq -25")

# V2 C receiver gain-staging verification: C tx -> C rx, clean channel,
# +/-6dB gain mismatch vs a gain=1.0 baseline. Matches the magnitude of the
# real freedv-gui/freedv-backend TX level mismatch found 260718 (rather than
# the AGC tests' wider +/-12dB) -- models the kind of check a downstream
# integrator's own verification suite should run against this API.
add_test(NAME rade_c_v2_rx_gain_p6db
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ${RADAE_BUILD_DIR}/src/lpcnet_demo -features wav/all.wav features_in.f32; \
             cat features_in.f32 | ${CMAKE_BINARY_DIR}/src/radae_tx --v2 > tx2_c.f32; \
             cat tx2_c.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 --gain 1.0 > features_rx_v2_c.f32; \
             cat tx2_c.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 --gain 2.0 > features_rx_v2_c2.f32; \
             python3 loss.py features_in.f32 features_rx_v2_c.f32 --features_hat2 features_rx_v2_c2.f32 \
             --compare --delta 0.01 --clip_start 100 --clip_end 300")
         set_tests_properties(rade_c_v2_rx_gain_p6db PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

add_test(NAME rade_c_v2_rx_gain_m6db
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ${RADAE_BUILD_DIR}/src/lpcnet_demo -features wav/all.wav features_in.f32; \
             cat features_in.f32 | ${CMAKE_BINARY_DIR}/src/radae_tx --v2 > tx2_c.f32; \
             cat tx2_c.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 --gain 1.0 > features_rx_v2_c.f32; \
             cat tx2_c.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 --gain 0.5 > features_rx_v2_c2.f32; \
             python3 loss.py features_in.f32 features_rx_v2_c.f32 --features_hat2 features_rx_v2_c2.f32 \
             --compare --delta 0.01 --clip_start 100 --clip_end 300")
         set_tests_properties(rade_c_v2_rx_gain_m6db PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# V1 text round-trip test: callsign/gridsquare via EOO data channel
add_test(NAME rade_c_v1_text
         COMMAND ${CMAKE_BINARY_DIR}/src/rade_v1_text_test)
         set_tests_properties(rade_c_v1_text PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# V2 text round-trip test: streaming text via BPSK data symbol channel
add_test(NAME rade_c_v2_text
         COMMAND ${CMAKE_BINARY_DIR}/src/rade_v2_text_test)
         set_tests_properties(rade_c_v2_text PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# WAV pipeline loss test: speech WAV -> RADE WAV -> decoded WAV, measure loss (no noise, nominal gain).
# Models the verification procedure for third-party integrators of the RADE library.
# Threshold: 5% above software-only (rade_c#989770e) baseline (V2: 0.084, V1: 0.113, AGC on, wav/all.wav).
# Tighter than the 10% integrator criterion -- these are reference tools with no HW in the loop.
# Baseline is a moving target if the model is retrained -- update threshold and hash accordingly.
add_test(NAME rade_c_v1_wav
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ${CMAKE_BINARY_DIR}/src/rade_tx_wav ${RADAE_DIR}/wav/all.wav /tmp/rade_c_v1_wav_tx.wav -f /tmp/rade_c_v1_wav_features_tx.f32; \
             ${CMAKE_BINARY_DIR}/src/rade_rx_wav /tmp/rade_c_v1_wav_tx.wav /tmp/rade_c_v1_wav_rx.wav -f /tmp/rade_c_v1_wav_features_rx.f32; \
             python3 loss.py /tmp/rade_c_v1_wav_features_tx.f32 /tmp/rade_c_v1_wav_features_rx.f32 --loss_test 0.119 --clip_start 100 --clip_end 300")
         set_tests_properties(rade_c_v1_wav PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

add_test(NAME rade_c_v2_wav
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ${CMAKE_BINARY_DIR}/src/rade_tx_wav --v2 ${RADAE_DIR}/wav/all.wav /tmp/rade_c_v2_wav_tx.wav -f /tmp/rade_c_v2_wav_features_tx.f32; \
             ${CMAKE_BINARY_DIR}/src/rade_rx_wav --v2 /tmp/rade_c_v2_wav_tx.wav /tmp/rade_c_v2_wav_rx.wav -f /tmp/rade_c_v2_wav_features_rx.f32; \
             python3 loss.py /tmp/rade_c_v2_wav_features_tx.f32 /tmp/rade_c_v2_wav_features_rx.f32 --loss_test 0.088 --clip_start 100 --clip_end 300")
         set_tests_properties(rade_c_v2_wav PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# Smoke tests: run the exact README quick-start commands with voice.wav.
# No loss threshold -- just verifies the example commands complete without error.
add_test(NAME rade_c_readme_smoke_wav
         COMMAND sh -c "\
             ${CMAKE_BINARY_DIR}/src/rade_tx_wav ${CMAKE_SOURCE_DIR}/input_sample.wav /tmp/rade_c_smoke_wav_v1_tx.wav && \
             ${CMAKE_BINARY_DIR}/src/rade_rx_wav /tmp/rade_c_smoke_wav_v1_tx.wav /tmp/rade_c_smoke_wav_v1_rx.wav && \
             ${CMAKE_BINARY_DIR}/src/rade_tx_wav --v2 ${CMAKE_SOURCE_DIR}/input_sample.wav /tmp/rade_c_smoke_wav_v2_tx.wav && \
             ${CMAKE_BINARY_DIR}/src/rade_rx_wav --v2 /tmp/rade_c_smoke_wav_v2_tx.wav /tmp/rade_c_smoke_wav_v2_rx.wav && \
             echo PASS")
         set_tests_properties(rade_c_readme_smoke_wav PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

add_test(NAME rade_c_readme_smoke_iq
         COMMAND sh -c "\
             sox ${CMAKE_SOURCE_DIR}/input_sample.wav -r 16000 -t .s16 -c 1 - | \
             ${CMAKE_BINARY_DIR}/src/lpcnet_demo -features /dev/stdin - | \
             ${CMAKE_BINARY_DIR}/src/radae_tx > /tmp/rade_c_smoke_iq_v1.iq && \
             cat /tmp/rade_c_smoke_iq_v1.iq | \
             ${CMAKE_BINARY_DIR}/src/radae_rx | \
             ${CMAKE_BINARY_DIR}/src/lpcnet_demo -fargan-synthesis /dev/stdin - | \
             sox -t .s16 -r 16000 -c 1 - /tmp/rade_c_smoke_iq_v1_dec.wav && \
             sox ${CMAKE_SOURCE_DIR}/input_sample.wav -r 16000 -t .s16 -c 1 - | \
             ${CMAKE_BINARY_DIR}/src/lpcnet_demo -features /dev/stdin - | \
             ${CMAKE_BINARY_DIR}/src/radae_tx --v2 > /tmp/rade_c_smoke_iq_v2.iq && \
             cat /tmp/rade_c_smoke_iq_v2.iq | \
             ${CMAKE_BINARY_DIR}/src/radae_rx --v2 | \
             ${CMAKE_BINARY_DIR}/src/lpcnet_demo -fargan-synthesis /dev/stdin - | \
             sox -t .s16 -r 16000 -c 1 - /tmp/rade_c_smoke_iq_v2_dec.wav && \
             echo PASS")
         set_tests_properties(rade_c_readme_smoke_iq PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

# V2 real-valued WAV rx noise folding test (SNR3k ~6 dB operating point).
# Re{tx+noise} aliases negative-frequency noise to positive frequencies, giving
# the real rx ~3 dB less effective SNR than the complex IQ rx.
# Path A: complex IQ rx at EbNodB=12 (SNR3k~5.6 dB).
# Path B: real WAV rx at EbNodB=15 (+3 dB to compensate noise folding penalty).
# Both should reach the same loss; delta threshold 0.005 (validated: correct 3 dB
# offset gives delta~0.002, wrong 2.5 dB offset gives delta~0.011 -> FAIL).
add_test(NAME rade_c_v2_wav_real
         COMMAND sh -c "cd ${RADAE_DIR}; \
             ./inference.sh 250725/checkpoints/checkpoint_epoch_200.pth wav/all.wav /dev/null \
             --rate_Fs --latent-dim 56 --peak --cp 0.004 --time_offset -16 --correct_time_offset -16 \
             --auxdata --w1_dec 128 --write_rx /tmp/rade_c_v2_wav_real_rx_iq.f32 \
             --prepend_noise 1 --append_noise 2 --freq_offset 25 --correct_freq_offset \
             --EbNodB 12 2>/dev/null; \
             cat /tmp/rade_c_v2_wav_real_rx_iq.f32 | ${CMAKE_BINARY_DIR}/src/radae_rx --v2 -v 0 \
             > /tmp/rade_c_v2_feat_iq.f32 2>/dev/null; \
             ./inference.sh 250725/checkpoints/checkpoint_epoch_200.pth wav/all.wav /dev/null \
             --rate_Fs --latent-dim 56 --peak --cp 0.004 --time_offset -16 --correct_time_offset -16 \
             --auxdata --w1_dec 128 --write_rx /tmp/rade_c_v2_wav_real_rx_real.f32 \
             --prepend_noise 1 --append_noise 2 --freq_offset 25 --correct_freq_offset \
             --EbNodB 15 2>/dev/null; \
             python3 f32toint16.py --real --scale 16384 < /tmp/rade_c_v2_wav_real_rx_real.f32 | \
             sox -r 8000 -c 1 -e signed-integer -b 16 -t raw - /tmp/rade_c_v2_wav_real.wav; \
             ${CMAKE_BINARY_DIR}/src/rade_rx_wav --v2 /tmp/rade_c_v2_wav_real.wav /dev/null \
             -f /tmp/rade_c_v2_feat_real.f32 2>/dev/null; \
             python3 loss.py features_in.f32 /tmp/rade_c_v2_feat_iq.f32 \
             --features_hat2 /tmp/rade_c_v2_feat_real.f32 \
             --compare --delta 0.005 --clip_start 100 --clip_end 300")
         set_tests_properties(rade_c_v2_wav_real PROPERTIES PASS_REGULAR_EXPRESSION "PASS")

