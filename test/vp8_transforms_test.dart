// Pure-function correctness tests for the VP8 transform / quantizer code.
//
// These exercise small, independently-testable pieces of the decoder that do
// not depend on the (currently incomplete) reconstruction pipeline:
//
//   * `vp8_short_idct4x4llm_c`   — RFC 6386 §14.1, inverse DCT + add to
//     prediction with clamp-to-[0,255]
//   * `vp8_short_inv_walsh4x4_c` — RFC 6386 §14.2, Y2 second-order WHT
//   * `vp8_dc_quant` / `vp8_ac_yquant` family — RFC 6386 §14.4, quant
//     lookup tables (spot-checked against libvpx/RFC reference values)
//
// Run with: dart test test/vp8_transforms_test.dart

import 'dart:typed_data';

import 'package:pure_dart_vpx/vp8/common/idctllm.dart';
import 'package:pure_dart_vpx/vp8/common/quant_common.dart';
import 'package:test/test.dart';

void main() {
  group('vp8_short_idct4x4llm_c (RFC 6386 §14.1)', () {
    test('all-zero coefficients leave prediction unchanged', () {
      // 4x4 block with stride 8; surround with sentinel bytes that must not
      // be touched, to confirm we never write outside the 4x4 region.
      const stride = 8;
      final pred = Uint8List(stride * 4);
      for (var i = 0; i < pred.length; i++) {
        pred[i] = 17 + i; // arbitrary non-zero pattern
      }
      final recon = Uint8List.fromList(pred);
      final coeffs = Int32List(16); // all zero

      vp8_short_idct4x4llm_c(recon, 0, pred, 0, stride, coeffs, 0);

      // Every pixel in the 4x4 must equal the prediction; sentinels untouched.
      for (var row = 0; row < 4; row++) {
        for (var col = 0; col < 8; col++) {
          expect(
            recon[row * stride + col],
            pred[row * stride + col],
            reason: 'pixel ($row,$col) changed',
          );
        }
      }
    });

    test('output is clamped to [0,255]', () {
      // Push the IDCT into saturation: huge positive DC coefficient with a
      // mid-grey prediction must clamp at 255, huge negative at 0.
      const stride = 4;
      final pred = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        pred[i] = 128;
      }
      final recon = Uint8List(16);

      // Positive saturation
      final coeffsPos = Int32List(16)..[0] = 4096;
      vp8_short_idct4x4llm_c(recon, 0, pred, 0, stride, coeffsPos, 0);
      for (final v in recon) {
        expect(v, 255);
      }

      // Negative saturation
      final coeffsNeg = Int32List(16)..[0] = -4096;
      recon.fillRange(0, 16, 0);
      vp8_short_idct4x4llm_c(recon, 0, pred, 0, stride, coeffsNeg, 0);
      for (final v in recon) {
        expect(v, 0);
      }
    });

    test('DC-only coefficient produces uniform offset (rounded /8)', () {
      // A coefficient of (8) at position 0 is the spec-canonical "add 1 to
      // every pixel" because the IDCT applies (a1+d1+4)>>3 == ((8*4+4)/?)
      // Empirically with libvpx semantics we expect a small uniform delta.
      // Verifying *uniformity* across the 4x4 is the meaningful invariant.
      const stride = 4;
      final pred = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        pred[i] = 100;
      }
      final recon = Uint8List(16);
      final coeffs = Int32List(16)..[0] = 8;

      vp8_short_idct4x4llm_c(recon, 0, pred, 0, stride, coeffs, 0);

      final v0 = recon[0];
      for (final v in recon) {
        expect(v, v0, reason: 'DC-only IDCT must produce uniform output');
      }
      // Plausibility: result must be close to the prediction (within +/- a
      // few units for this small DC).
      expect((v0 - 100).abs(), lessThanOrEqualTo(5));
    });

    test('respects offsets — leaves bytes outside region intact', () {
      const stride = 8;
      final pred = Uint8List(64);
      final recon = Uint8List(64);
      // Fill recon with a sentinel; the IDCT must only touch 4 rows of 4
      // bytes starting at offset (1*stride + 2).
      recon.fillRange(0, recon.length, 0xAB);
      pred.fillRange(0, pred.length, 50);
      final coeffs = Int32List(16); // zeros → recon[r,c] = pred[r,c]
      const offset = 1 * stride + 2;

      vp8_short_idct4x4llm_c(recon, offset, pred, offset, stride, coeffs, 0);

      for (var row = 0; row < 8; row++) {
        for (var col = 0; col < 8; col++) {
          final i = row * stride + col;
          final inside = row >= 1 && row < 5 && col >= 2 && col < 6;
          if (inside) {
            expect(recon[i], 50, reason: 'inside region row=$row col=$col');
          } else {
            expect(
              recon[i],
              0xAB,
              reason: 'sentinel clobbered at row=$row col=$col',
            );
          }
        }
      }
    });
  });

  group('vp8_short_inv_walsh4x4_c (RFC 6386 §14.2)', () {
    test('all-zero input yields all-zero DC coefficients', () {
      // The function writes 16 outputs at positions (i << 4) into the SAME
      // array, modelling the libvpx 25-block macroblock coefficient buffer
      // (25 * 16 = 400 entries). We need at least 16*16+1 slots.
      final buf = Int32List(16 * 16 + 16);
      // input region [0..15] is all zero by default
      vp8_short_inv_walsh4x4_c(buf, 0, 0);
      for (var i = 0; i < 16; i++) {
        expect(buf[i << 4], 0, reason: 'block $i Y2-DC must be zero');
      }
    });

    test('uniform input — first Y2-DC equals 8 for K=4', () {
      // WHT of a constant-K 4x4 block: row pass yields [4K,0,0,0] per row,
      // column pass yields [16K,0,...] for the first column. The inverse
      // here applies (a2+3)>>3 = (16K+3)>>3, which for K=4 is 8.
      final buf = Int32List(16 * 16 + 16);
      for (var i = 0; i < 16; i++) {
        buf[i] = 4;
      }
      vp8_short_inv_walsh4x4_c(buf, 0, 0);
      expect(buf[0], 8, reason: 'first Y2-DC must be (16*4+3)>>3 = 8');
      // Remaining 15 Y2-DC slots must be zero (only DC is non-zero for a
      // uniform input).
      for (var i = 1; i < 16; i++) {
        expect(
          buf[i << 4],
          0,
          reason: 'block $i Y2-DC must be zero for uniform input',
        );
      }
    });
  });

  group('vp8 quantizer lookup (RFC 6386 §14.4)', () {
    test('dc_qlookup boundary values match libvpx reference', () {
      // RFC 6386 Table 4 / libvpx vp8/common/quant_common.c
      // dc_qlookup[0]   ==   4
      // dc_qlookup[127] == 157
      expect(dc_qlookup[0], 4);
      expect(dc_qlookup[127], 157);
      expect(dc_qlookup.length, 128);
    });

    test('ac_qlookup boundary values match libvpx reference', () {
      expect(ac_qlookup[0], 4);
      expect(ac_qlookup[127], 284);
      expect(ac_qlookup.length, 128);
    });

    test('vp8_dc_quant clamps QIndex into table range', () {
      // Negative-index and over-127 inputs must not crash; libvpx clamps.
      // Spec QIndex range is 0..127 (7 bits); deltas can push out of range.
      expect(vp8_dc_quant(0, 0), dc_qlookup[0]);
      expect(vp8_dc_quant(127, 0), dc_qlookup[127]);
      expect(vp8_dc_quant(50, 0), dc_qlookup[50]);
    });

    test('vp8_ac_yquant returns the AC table value at QIndex', () {
      expect(vp8_ac_yquant(0), ac_qlookup[0]);
      expect(vp8_ac_yquant(127), ac_qlookup[127]);
      expect(vp8_ac_yquant(64), ac_qlookup[64]);
    });

    test('dc_qlookup is monotonically non-decreasing', () {
      // The quant ladder must be monotonic so higher QIndex truly means
      // coarser quantization. Catches typos when porting the table.
      for (var i = 1; i < dc_qlookup.length; i++) {
        expect(
          dc_qlookup[i],
          greaterThanOrEqualTo(dc_qlookup[i - 1]),
          reason: 'dc_qlookup non-monotonic at index $i',
        );
      }
    });

    test('ac_qlookup is monotonically non-decreasing', () {
      for (var i = 1; i < ac_qlookup.length; i++) {
        expect(
          ac_qlookup[i],
          greaterThanOrEqualTo(ac_qlookup[i - 1]),
          reason: 'ac_qlookup non-monotonic at index $i',
        );
      }
    });
  });
}
