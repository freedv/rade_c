# TODO: automated Windows/Linux equivalence ctest

Follow-up idea from the manual Linux-vs-Windows(Wine) cross-check done on
this branch: turn that check into a permanent ctest in rade_c, so any
future Windows build (this MinGW cross-compile, MSYS2, Mooneer's own
process, a GitHub Actions Windows runner, etc.) can be verified against a
golden reference automatically.

Sketch:
- Commit a golden reference (expected loss number, and/or
  linux_features_tx.f32 / linux_features_rx.f32) generated once from a
  native Linux build of rade_tx_wav/rade_rx_wav against a fixed test wav.
- ctest builds/obtains rade_tx_wav/rade_rx_wav for the target platform,
  runs them (under Wine if cross-compiled, natively if not), runs
  loss.py (native Linux python, not through Wine), and diffs against the
  golden reference.
- Reuse the existing +/-10% loss tolerance from
  doc/verification/verification_procedure.md as the pass/fail threshold
  (measured cross-platform noise so far: RX feature RMS diff ~0.00017,
  well inside that).
- Live in rade_c itself (not freedv-gui) so it's one canonical
  "is this Windows build numerically equivalent" gate, reusable
  regardless of who builds it or how.

Not started - raise with Mooneer once he responds on GH, in case his
build process differs enough to change the design.
