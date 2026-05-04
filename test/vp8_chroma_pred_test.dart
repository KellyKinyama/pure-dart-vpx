// Bit-exact unit tests for `predict_intra_chroma`. The function predicts an
// 8x8 U and 8x8 V block (each made of 4 sub-4x4 blocks: indices 16-19 for U,
// 20-23 for V), then adds residuals via `vp8_short_idct4x4llm_c`.
//
// These tests use ZERO residuals so the output equals the prediction exactly.
// They isolate:
//   * UV-mode predictor selection (DC / V / H / TM)
//   * The U/V offset arithmetic (256-coeff block stride, sub-block walk)
//   * Border reads for missing-neighbor cases at frame origin

import 'dart:typed_data';

import 'package:pure_dart_vpx/vp8/common/blockd.dart';
import 'package:pure_dart_vpx/vp8/common/reconintra.dart';
import 'package:test/test.dart';

const int _stride = 24; // 8 visible cols + 16 border padding

({Uint8List buf, int u_off, int v_off}) _setupUv({
  required int aboveU,
  required int leftU,
  required int cornerU,
  required int aboveV,
  required int leftV,
  required int cornerV,
}) {
  // Layout: rows [0..7] for U, rows [8..15] for V; visible block at col 1..8,
  // row 1..8 (relative). Borders at col 0, row 0.
  final buf = Uint8List(_stride * 32);
  buf.fillRange(0, buf.length, 0xCC);
  final u_off = 1 * _stride + 1;
  final v_off = 16 * _stride + 1;

  // Fill above row + left col + corner for U
  for (var c = -1; c < 12; c++) {
    buf[u_off - _stride + c] = (c == -1) ? cornerU : aboveU;
  }
  for (var r = 0; r < 8; r++) {
    buf[u_off + r * _stride - 1] = leftU;
  }

  // Fill above row + left col + corner for V
  for (var c = -1; c < 12; c++) {
    buf[v_off - _stride + c] = (c == -1) ? cornerV : aboveV;
  }
  for (var r = 0; r < 8; r++) {
    buf[v_off + r * _stride - 1] = leftV;
  }

  return (buf: buf, u_off: u_off, v_off: v_off);
}

List<int> _block8(Uint8List buf, int off) {
  final out = <int>[];
  for (var r = 0; r < 8; r++) {
    for (var c = 0; c < 8; c++) {
      out.add(buf[off + r * _stride + c]);
    }
  }
  return out;
}

MODE_INFO _mi(int uvMode) {
  final mi = MODE_INFO();
  mi.mbmi.uv_mode = uvMode;
  return mi;
}

void main() {
  group('predict_intra_chroma (zero residuals)', () {
    test(
      'DC_PRED with above=120, left=140, corner=130 → dc = (8*120 + 8*140 + 8) >> 4',
      () {
        final s = _setupUv(
          aboveU: 120,
          leftU: 140,
          cornerU: 130,
          aboveV: 100,
          leftV: 160,
          cornerV: 130,
        );
        final coeffs = Int32List(400);
        predict_intra_chroma(
          s.buf,
          s.u_off,
          s.buf,
          s.v_off,
          _stride,
          _mi(DC_PRED),
          coeffs,
          0,
        );

        // dc_u = (8*120 + 8*140 + 8) / 16 = (960 + 1120 + 8) / 16 = 2088 / 16 = 130
        // dc_v = (8*100 + 8*160 + 8) / 16 = (800 + 1280 + 8) / 16 = 2088 / 16 = 130
        const dcU = 130;
        const dcV = 130;
        expect(_block8(s.buf, s.u_off), List.filled(64, dcU));
        expect(_block8(s.buf, s.v_off), List.filled(64, dcV));
      },
    );

    test('V_PRED replicates above row', () {
      final s = _setupUv(
        aboveU: 77,
        leftU: 0,
        cornerU: 0,
        aboveV: 88,
        leftV: 0,
        cornerV: 0,
      );
      final coeffs = Int32List(400);
      predict_intra_chroma(
        s.buf,
        s.u_off,
        s.buf,
        s.v_off,
        _stride,
        _mi(V_PRED),
        coeffs,
        0,
      );
      expect(_block8(s.buf, s.u_off), List.filled(64, 77));
      expect(_block8(s.buf, s.v_off), List.filled(64, 88));
    });

    test('H_PRED replicates left column', () {
      final s = _setupUv(
        aboveU: 0,
        leftU: 55,
        cornerU: 0,
        aboveV: 0,
        leftV: 66,
        cornerV: 0,
      );
      final coeffs = Int32List(400);
      predict_intra_chroma(
        s.buf,
        s.u_off,
        s.buf,
        s.v_off,
        _stride,
        _mi(H_PRED),
        coeffs,
        0,
      );
      expect(_block8(s.buf, s.u_off), List.filled(64, 55));
      expect(_block8(s.buf, s.v_off), List.filled(64, 66));
    });

    test('TM_PRED: pixel = clip(left + above - top_left)', () {
      final s = _setupUv(
        aboveU: 100,
        leftU: 110,
        cornerU: 90,
        aboveV: 90,
        leftV: 80,
        cornerV: 100,
      );
      final coeffs = Int32List(400);
      predict_intra_chroma(
        s.buf,
        s.u_off,
        s.buf,
        s.v_off,
        _stride,
        _mi(TM_PRED),
        coeffs,
        0,
      );
      // U pixel = clip(110 + 100 - 90) = 120 (uniform since above and left
      // are constant)
      expect(_block8(s.buf, s.u_off), List.filled(64, 120));
      // V pixel = clip(80 + 90 - 100) = 70
      expect(_block8(s.buf, s.v_off), List.filled(64, 70));
    });

    test(
      'U/V are independent: writing U does not stomp V (offset arithmetic)',
      () {
        final s = _setupUv(
          aboveU: 200,
          leftU: 200,
          cornerU: 200,
          aboveV: 50,
          leftV: 50,
          cornerV: 50,
        );
        final coeffs = Int32List(400);
        predict_intra_chroma(
          s.buf,
          s.u_off,
          s.buf,
          s.v_off,
          _stride,
          _mi(DC_PRED),
          coeffs,
          0,
        );
        // U should be 200, V should be 50, no cross-pollution.
        expect(_block8(s.buf, s.u_off), List.filled(64, 200));
        expect(_block8(s.buf, s.v_off), List.filled(64, 50));
      },
    );
  });

  group('predict_intra_chroma sub-block walk: residual into block 17 only', () {
    test(
      'non-zero coeffs in U block 17 (top-right 4x4) only affect that quadrant',
      () {
        final s = _setupUv(
          aboveU: 100,
          leftU: 100,
          cornerU: 100,
          aboveV: 0,
          leftV: 0,
          cornerV: 0,
        );
        final coeffs = Int32List(400);
        // Block 17 = U sub-block at row 0, col 4. Coeff offset = 256 + (17-16)*16 = 272.
        // Set DC coeff (zigzag[0]=index 0) so all 16 output pixels get a constant add.
        // IDCT for a single DC: pixel += (dc + 4) >> 3 to each of 16 positions
        // (after horizontal then vertical separable transform with all other
        // taps zero, the DC term spreads to every pixel as dc/8 rounded).
        coeffs[272 + 0] = 16; // DC = 16 → each pixel adds (16+4)>>3 = 2
        predict_intra_chroma(
          s.buf,
          s.u_off,
          s.buf,
          s.v_off,
          _stride,
          _mi(DC_PRED),
          coeffs,
          0,
        );

        // Expected U: 100 everywhere except top-right 4x4 (rows 0-3, cols 4-7) = 102.
        final expectedU = <int>[];
        for (var r = 0; r < 8; r++) {
          for (var c = 0; c < 8; c++) {
            expectedU.add((r < 4 && c >= 4) ? 102 : 100);
          }
        }
        expect(_block8(s.buf, s.u_off), expectedU);
      },
    );

    test('non-zero coeffs in V block 22 only affect V bottom-left 4x4', () {
      final s = _setupUv(
        aboveU: 0,
        leftU: 0,
        cornerU: 0,
        aboveV: 100,
        leftV: 100,
        cornerV: 100,
      );
      final coeffs = Int32List(400);
      // Block 22 = V sub-block at row 1, col 0 (i.e. rows 4-7, cols 0-3).
      // Coeff offset = 256 + (22-16)*16 = 256 + 96 = 352.
      coeffs[352 + 0] = 32; // each pixel adds (32+4)>>3 = 4
      predict_intra_chroma(
        s.buf,
        s.u_off,
        s.buf,
        s.v_off,
        _stride,
        _mi(DC_PRED),
        coeffs,
        0,
      );
      final expectedV = <int>[];
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 8; c++) {
          expectedV.add((r >= 4 && c < 4) ? 104 : 100);
        }
      }
      expect(_block8(s.buf, s.v_off), expectedV);
    });
  });
}
