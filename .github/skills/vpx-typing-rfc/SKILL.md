---
name: vpx-typing-rfc
description: 'Replace `dynamic` types with strongly-typed Dart classes across the pure-dart-vpx VP8/VP9 decoder and encoder, and bring the implementation into RFC compliance (RFC 6386 for VP8, libvpx/VP9 bitstream spec). Use when: removing `dynamic` fields/parameters/variables, introducing typed structs that mirror libvpx C structs, auditing bitstream parsing or motion-vector clamping against the RFC, fixing decoder/encoder spec deviations, eliminating `is dynamic` checks, or porting more of libvpx faithfully. Triggers: "remove dynamic", "make typed", "rfc compliant", "match libvpx", "vp8 spec", "vp9 spec", "decodemv", "dboolhuff", "vp8_iface".'
---

# VPX Typing & RFC Compliance Workflow

A repeatable workflow to (1) eliminate `dynamic` from `lib/vp8/`, `lib/vpx/`, `lib/vpx_dsp/`, and `lib/util/`, replacing each with a typed Dart class that mirrors the corresponding libvpx C struct, and (2) verify the parsing/decoding logic against the relevant RFC sections.

## When to Use

- A file under `lib/vp8/`, `lib/vpx/`, `lib/vpx_dsp/`, or `lib/util/` contains `dynamic`, `dynamic?`, `is dynamic`, or untyped `Map`/`List` parameters.
- A function signature uses placeholder types (`dynamic bounds`, `dynamic header`, `dynamic decoder`, `dynamic priv`, `dynamic decrypt_cb`, etc.).
- A bitstream-reading routine needs to be audited against [RFC 6386](https://datatracker.ietf.org/doc/html/rfc6386) (VP8) or the VP9 bitstream spec.
- The user asks to "make the decoder/encoder RFC compliant" or to "port the libvpx struct properly".

Do **not** use this skill for: kokoro-test/, FFI bindings in `vpx_bindings.dart` (those `DynamicLibrary` references are correct), or unrelated refactors.

## Reference Material

- **VP8**: RFC 6386 — https://datatracker.ietf.org/doc/html/rfc6386
  - §4 Overview, §5 Boolean Decoder, §9 Frame-Header parsing, §10 Segment-based adjustments, §11–§16 Intra/Inter prediction, §17 Motion Vectors, §18 Token decoding, §19 Loop Filter.
- **VP9**: VP9 Bitstream & Decoding Process Specification (Google) — https://storage.googleapis.com/downloads.webmproject.org/docs/vp9/vp9-bitstream-specification-v0.6-20160331-draft.pdf
- **libvpx source of truth** (C): https://github.com/webmproject/libvpx — match struct layouts, field names, and decoding order.

## Procedure

Work on **one file at a time**. Do not bulk-rewrite multiple files in a single pass.

### Step 1 — Inventory `dynamic` usage in the target file

Run a grep limited to the file to enumerate every occurrence:

```
grep -n "dynamic" lib/vp8/<file>.dart
```

Classify each hit into one of:

1. **Field of a class** (e.g. `final dynamic decoder;` in `blockd.dart`).
2. **Function parameter** (e.g. `dynamic bounds`, `dynamic? priv`).
3. **Local variable / return type**.
4. **`is dynamic` / cast** — almost always a bug.
5. **Comment or string literal** — leave alone.

### Step 2 — Find the libvpx C counterpart

For each `dynamic`, locate the C type in libvpx:

| Dart symbol | libvpx file (C) | C type | Resolved Dart type |
|---|---|---|---|
| `dynamic? priv` in `vpx_codec_ctx_t`, `vp8_iface.dart`, `vpx_codec_*_fn_t` typedefs | `vpx/internal/vpx_codec_internal.h` | opaque `struct vpx_codec_alg_priv *` (per-codec) | abstract base class `VpxCodecAlgPriv?` |
| `dynamic? user_priv` in `vp8_decode`, `vp8_get_frame`, `vpx_codec_decode` | `vpx/vpx_decoder.h` | `void *user_priv` (caller-owned cookie) | `Object?` |
| `dynamic? data` in `vp8_init` | `vpx/internal/vpx_codec_internal.h` | `vpx_codec_priv_enc_mr_cfg_t *` | `Object?` |
| `dynamic time_stamp` in `vp8dx_receive_compressed_data` | `vp8/decoder/onyxd_if.h` | `int64_t time_stamp` | `int?` |
| `dynamic bounds` in `decodemv.dart` (`vp8_clamp_mv2`, `read_mb_modes_mv`, `decode_mb_mode_mvs`) | `vp8/decoder/decodemv.c` | `int mb_to_{left,right,top,bottom}_edge` fields on `MACROBLOCKD` | existing `MVBounds` class (already declared in `decodemv.dart`) |
| `final dynamic decoder` in `FRAGMENT_DATA` & `MACROBLOCKD` (`blockd.dart`) | `vp8/common/blockd.h` | `struct VP8Decoder *` (`VP8D_COMP *`) | unused — delete. Real `FRAGMENT_DATA` in `onyxd_int.dart` already typed |
| `dynamic decrypt_cb`, `decrypt_state`, `buffer_end`, `clear_buffer` in `BOOL_DECODER` | `vp8/decoder/dboolhuff.h` | `vpx_decrypt_cb`, `void *`, `const unsigned char *`, `int` | unused dead fields — delete. If reintroduced: `typedef VpxDecryptCb = void Function(Object? state, Uint8List inBuf, int inOff, Uint8List outBuf, int outOff, int n)`, `Object? decrypt_state`, `int buffer_end_off` |
| `dynamic header`, `dynamic otherHeader` in `copyEntropyValues` (`c_utils.dart`) | `vp8/common/entropy.h` | `FRAME_CONTEXT *` | unused dead code referencing nonexistent `data_32` shape — delete |
| `dynamic ptr` in `memset32`, `dynamic dst/src` in `memcpy` (`c_utils.dart`) | n/a (libc) | `void *` | unused — delete (Dart `setRange` / `Uint8List.setAll` is the idiom) |
| `dynamic mb` in `mv_bias` (`findnearmv.dart`) — accesses `mb.mbmi.ref_frame` | `vp8/common/findnearmv.c` | `MODE_INFO *` | `MODE_INFO` |
| `dynamic predict` in `vp8_setup_intra_recon`, `dynamic ybf` in `vp8_setup_intra_recon_top_line` | `vp8/common/setupintrarecon.c` | `unsigned char *`, `YV12_BUFFER_CONFIG *` | `Uint8List`, `vpx_image_t` (bodies are no-ops; field refs need `stride[VPX_PLANE_U]` not `uv_stride`) |
| `static Map<String, dynamic> create()` in `MotionVector` (`mv.dart`) | n/a | n/a | unused dead JS-port leftover — delete |

If the table above does not cover the symbol, open the corresponding C source via `github_repo` against `webmproject/libvpx` and record the canonical type.

### Step 3 — Introduce the typed class

- If the typed class **already exists** in `lib/vp8/common/` (e.g. `MotionVector`, `MODE_INFO`, `VP8D_COMP`, `VP8Common`), use it — do **not** create a duplicate.
- If it does not exist, add it to the file that mirrors the C header location:
  - `vp8/common/*.h` → `lib/vp8/common/<name>.dart`
  - `vp8/decoder/*.h` → `lib/vp8/decoder/<name>.dart`
  - `vpx_dsp/*.h` → `lib/vpx_dsp/<name>.dart`
- Field names must match the C struct (snake_case kept) so cross-referencing the RFC and libvpx stays trivial.
- Pointers in C become a `(Uint8List buffer, int offset)` pair, **not** a sublist (no allocations on the hot path).
- Function pointers become a `typedef`, e.g. `typedef VpxDecryptCb = void Function(Object? state, Uint8List input, int inputOff, Uint8List output, int outputOff, int count);`

### Step 4 — Replace and verify each occurrence

For each occurrence found in Step 1:

1. Replace the `dynamic` with the typed class / typedef.
2. Remove now-redundant `is X` runtime checks (the type system does the work).
3. Re-read the surrounding decoder routine and compare it line-by-line with the matching C function in libvpx and the corresponding RFC 6386 section. Note any deviation in a `// RFC 6386 §X.Y:` comment if behavior is correct, or fix it if not.
4. Run `dart analyze lib/<changed-file>.dart` after each file.

### Step 5 — RFC compliance audit checklist

After typing changes in a file, confirm against RFC 6386 (VP8) — the following are the highest-risk areas in this codebase:

- [ ] **Boolean decoder** (`dboolhuff.dart`) — §7 / §9.2: range/value initialization to `255`/`0`, `bit_count` starts at `0`, `vp8dx_bool_error` triggers when reading past `buffer_end`. Buffer indexing uses byte offsets only.
- [ ] **Uncompressed frame header** (`decodeframe.dart`) — §9.1: 3-byte tag for keyframes, start-code `0x9d 0x01 0x2a`, horizontal/vertical scale extraction.
- [ ] **Segment-based adjustments** (`decodemv.dart`) — §9.3 / §10: `update_mb_segmentation_map`, `mb_segment_tree_probs` reset rules.
- [ ] **Loop-filter parameters** — §9.4 / §15: `filter_level`, `sharpness_level`, ref/mode deltas only updated when `mode_ref_lf_delta_update` is set.
- [ ] **Quantizer indices** — §9.6: base Y/UV AC/DC deltas are signed; clamp `q_index + delta` to `[0, 127]`.
- [ ] **Motion-vector clamping** (`vp8_clamp_mv2` in `decodemv.dart`) — §17.1: bounds derived from `mb_to_left_edge`, `mb_to_right_edge`, `mb_to_top_edge`, `mb_to_bottom_edge`. Replace `dynamic bounds` with a `MvLimits` class carrying these four ints.
- [ ] **Token decoding** (`detokenize.dart`) — §13: coefficient band table, EOB token, DCT context update.
- [ ] **Reference frame sign-bias** — §9.7: golden/altref sign bias bits.

For VP9 / encoder paths, replace this checklist with the equivalent VP9 spec sections; the encoder additionally must emit, not just read, every header field, in the **same order** the decoder consumes them.

### Step 6 — Verification

Run, in order:

```
dart analyze
dart format --set-exit-if-changed lib/
dart test
```

Fix any analyzer warnings about implicit `dynamic` (`always_declare_return_types`, `avoid_annotating_with_dynamic`, `inference_failure_on_*`).

If a decoded frame regression appears, bisect by reverting the most recent typed-class introduction and re-running `bin/pure_dart_vpx.dart` on a known-good IVF.

## Output Per Iteration

After completing a file, report:

1. The file path and the count of `dynamic` occurrences removed.
2. The new typed classes / typedefs introduced (with their libvpx C counterpart).
3. Any RFC §-references added as comments.
4. Any spec deviations discovered and how they were resolved.
5. `dart analyze` result on the touched file (must be clean).

## Anti-patterns

- **Do not** introduce `Object?` as a substitute for `dynamic` — that defeats the purpose. Pick the actual type.
- **Do not** create wrapper classes that just hold a single `dynamic` field.
- **Do not** rewrite multiple decoder files in one pass — typing errors compound and become un-bisectable.
- **Do not** rename C-style snake_case fields to Dart camelCase during the same change that introduces the type. Do that as a separate, mechanical pass after RFC compliance is confirmed.
- **Do not** change `lib/vpx/vpx_bindings.dart` references to `ffi.DynamicLibrary` — those are FFI, not stale `dynamic`.
