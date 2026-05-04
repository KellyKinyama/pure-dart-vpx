---
applyTo: 'lib/vp8/**/*.dart, lib/vpx/**/*.dart, lib/vpx_dsp/**/*.dart, lib/util/**/*.dart'
description: 'Ban `dynamic` in the VP8/VPX decoder/encoder. Forces typed Dart classes mirroring libvpx C structs and RFC 6386 / VP9 spec compliance.'
---

# No `dynamic` in pure-dart-vpx codec sources

Files under `lib/vp8/`, `lib/vpx/`, `lib/vpx_dsp/`, and `lib/util/` are a faithful port of libvpx and must be RFC 6386 (VP8) / VP9-spec compliant. Treat any `dynamic` here as a bug.

## Rules

- **Never introduce `dynamic`** as a field type, parameter type, return type, local variable type, generic argument, or in `is dynamic` checks.
- **Do not substitute `Object?` for `dynamic`** unless the field is a true opaque-`void *` (caller cookie like `user_priv`). Pick the actual libvpx C type.
- **Mirror libvpx struct layouts.** Field names stay snake_case (`mb_to_left_edge`, `coeff_probs`, `mv_probs`) so cross-referencing C source and the RFC remains trivial. Do not rename to camelCase in the same change as a typing fix.
- **Pointers become `(Uint8List buffer, int offset)` pairs.** Never `sublist()` on the hot path.
- **Function pointers become `typedef`s** (e.g. `typedef VpxDecryptCb = void Function(...)`).
- **`ffi.DynamicLibrary` is not `dynamic`.** Do not touch `lib/vpx/vpx_bindings.dart`.

## When typing reveals a deviation

If adding a type makes existing code stop compiling because it references a field the C struct never had (e.g. `ybf.uv_stride` instead of `ybf.stride[VPX_PLANE_U]`), the existing code is the bug. Fix it against libvpx, not by widening the type back to `dynamic`.

## RFC compliance reminders

When changing any decoder routine, re-verify against the matching RFC 6386 section before committing:

- Boolean decoder init: `range = 255`, `bit_count = 0` (§7).
- Frame tag / start code `0x9d 0x01 0x2a` (§9.1).
- Loop-filter deltas only updated when `mode_ref_lf_delta_update == 1` (§9.4).
- Quantizer index clamp `[0, 127]` after applying signed deltas (§9.6).
- Motion-vector clamping uses `mb_to_{left,right,top,bottom}_edge` (§17.1).
- Coefficient band table + EOB token (§13).

For deeper procedure (per-file workflow, libvpx-symbol mapping table, full RFC checklist), invoke the `vpx-typing-rfc` skill.
