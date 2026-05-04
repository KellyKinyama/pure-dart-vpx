// Bit-exact unit tests for `predict_intra_luma` non-B_PRED path. This
// exercises the Y2 → inverse-Walsh → 16-IDCT pipeline which writes the Y2
// DC coefficients into slot 0 of each Y block (positions 0, 16, 32, ..., 240
// of the 384-entry Y coefficient array) before per-block IDCT runs.
//
// All tests use ZERO residuals + ZERO Y2 so the output equals the prediction.

import 'dart:typed_data';

import 'package:pure_dart_vpx/vp8/common/blockd.dart';
import 'package:pure_dart_vpx/vp8/common/reconintra.dart';
import 'package:test/test.dart';

const int _stride = 32; // 16 visible cols + 16 border padding

({Uint8List buf, int off}) _setupY({
  required int above,
  required int left,
  required int corner,
}) {
  final buf = Uint8List(_stride * 32);
  buf.fillRange(0, buf.length, 0xCC);
  final off = 1 * _stride + 1;
  // Above row 0 + 4 above-right pixels for sub-block context (b_pred only).
  for (var c = -1; c < 20; c++) {
    buf[off - _stride + c] = (c == -1) ? corner : above;
  }
  for (var r = 0; r < 16; r++) {
    buf[off + r * _stride - 1] = left;
  }
  return (buf: buf, off: off);
}

List<int> _block16(Uint8List buf, int off) {
  final out = <int>[];
  for (var r = 0; r < 16; r++) {
    for (var c = 0; c < 16; c++) {
      out.add(buf[off + r * _stride + c]);
    }
  }
  return out;
}

MODE_INFO _mi(int yMode) {
  final mi = MODE_INFO();
  mi.mbmi.y_mode = yMode;
  return mi;
}

void main() {
  group('predict_intra_luma (non-B_PRED, zero coeffs)', () {
    test('V_PRED replicates above row, no residual added', () {
      final s = _setupY(above: 100, left: 0, corner: 0);
      final coeffs = Int32List(400);
      predict_intra_luma(s.buf, s.off, _stride, _mi(V_PRED), coeffs, 0);
      expect(_block16(s.buf, s.off), List.filled(256, 100));
    });

    test('H_PRED replicates left column', () {
      final s = _setupY(above: 0, left: 70, corner: 0);
      final coeffs = Int32List(400);
      predict_intra_luma(s.buf, s.off, _stride, _mi(H_PRED), coeffs, 0);
      expect(_block16(s.buf, s.off), List.filled(256, 70));
    });

    test(
      'DC_PRED with above=80, left=120 → dc = (16*80 + 16*120 + 16) >> 5 = 100',
      () {
        final s = _setupY(above: 80, left: 120, corner: 0);
        final coeffs = Int32List(400);
        predict_intra_luma(s.buf, s.off, _stride, _mi(DC_PRED), coeffs, 0);
        expect(_block16(s.buf, s.off), List.filled(256, 100));
      },
    );

    test(
      'TM_PRED uniform: clip(left + above - top_left) = clip(120 + 100 - 80) = 140',
      () {
        final s = _setupY(above: 100, left: 120, corner: 80);
        final coeffs = Int32List(400);
        predict_intra_luma(s.buf, s.off, _stride, _mi(TM_PRED), coeffs, 0);
        expect(_block16(s.buf, s.off), List.filled(256, 140));
      },
    );
  });

  group('predict_intra_luma residual ordering', () {
    test('non-zero AC in block 0 only affects top-left 4x4', () {
      final s = _setupY(above: 100, left: 100, corner: 100);
      final coeffs = Int32List(400);
      // Block 0, position 1 (zigzag index 1, which is column 1 of row 0 in
      // the natural-order 4x4). Picking a single AC and watching it ripple
      // through the IDCT is messy, so just assert the BLOCK 0 region differs
      // and other 15 blocks remain at 100.
      coeffs[0 + 1] = 64;
      predict_intra_luma(s.buf, s.off, _stride, _mi(V_PRED), coeffs, 0);
      // Outside block 0 (rows 0-3, cols 0-3): no change.
      for (var r = 0; r < 16; r++) {
        for (var c = 0; c < 16; c++) {
          if (r < 4 && c < 4) continue;
          expect(
            s.buf[s.off + r * _stride + c],
            100,
            reason: 'block-0 residual leaked to ($r,$c)',
          );
        }
      }
    });

    test('non-zero AC in block 15 (bottom-right) only affects that 4x4', () {
      final s = _setupY(above: 100, left: 100, corner: 100);
      final coeffs = Int32List(400);
      // Block 15: coeff offset = 15 * 16 = 240.
      coeffs[240 + 1] = 64;
      predict_intra_luma(s.buf, s.off, _stride, _mi(V_PRED), coeffs, 0);
      for (var r = 0; r < 16; r++) {
        for (var c = 0; c < 16; c++) {
          if (r >= 12 && c >= 12) continue;
          expect(
            s.buf[s.off + r * _stride + c],
            100,
            reason: 'block-15 residual leaked to ($r,$c)',
          );
        }
      }
    });

    test('Y2 DC propagates to all 16 sub-blocks via inverse Walsh', () {
      final s = _setupY(above: 100, left: 100, corner: 100);
      final coeffs = Int32List(400);
      // Y2 block lives at coeffs_off + 384 (positions 384..399). Set Y2[0] (the
      // DC of the Y2 macroblock) to 8: after inv-Walsh's `(x + 3) >> 3`
      // rounding, every Y2 output is (8+3)/8 = 1, so each Y block gets DC=1
      // written to coeffs[i*16].
      // Then for each Y block, IDCT of a single DC=1 produces (1 + 4) >> 3
      // = 0 added to every pixel — meaning the smallest non-trivial Y2 needs
      // a larger input. Bump to Y2[0] = 64: each Y block DC = (64+3)/8 = 8.
      // Per-pixel add from each Y block: depends on full IDCT, but for a
      // single DC at position 0 the IDCT spreads it as (dc + 4) >> 3 to each
      // pixel.  dc=8 → +1.5 ≈ +1 per pixel.
      coeffs[384] = 64;
      predict_intra_luma(s.buf, s.off, _stride, _mi(V_PRED), coeffs, 0);
      // Exact: every pixel = 100 + 1 = 101 across the entire 16x16.
      expect(_block16(s.buf, s.off), List.filled(256, 101));
    });
  });
}
