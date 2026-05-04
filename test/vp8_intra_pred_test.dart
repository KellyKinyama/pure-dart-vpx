// Bit-exact unit tests for the VP8 intra-prediction primitives in
// `lib/vp8/common/reconintra.dart`. These mirror RFC 6386 §12.2 and the
// libvpx vp8/common/reconintra.c reference, exercising every NxN predictor
// with hand-computed expected outputs.
//
// Each test sets up a tiny image with a known border (above row + left
// column + top-left pixel), invokes the predictor, then compares the NxN
// output region byte-for-byte against the spec-prescribed result.

import 'dart:typed_data';

import 'package:pure_dart_vpx/vp8/common/reconintra.dart';
import 'package:test/test.dart';

/// Allocate an image large enough to hold an NxN block at offset
/// `(border, border)` plus a 1-pixel above row and 1-pixel left column.
/// Returns (buffer, predict_off, stride).
({Uint8List buf, int off, int stride}) _setup(int n, {int stride = 0}) {
  final s = stride == 0 ? n + 8 : stride;
  final h = n + 4;
  final buf = Uint8List(s * h);
  // Fill with a sentinel so any out-of-region write is obvious.
  buf.fillRange(0, buf.length, 0xCC);
  final off = 1 * s + 1; // 1 row down, 1 col right — leaves border at [-1].
  return (buf: buf, off: off, stride: s);
}

void _setAbove(Uint8List buf, int off, int stride, List<int> row) {
  for (var i = 0; i < row.length; i++) {
    buf[off - stride + i] = row[i];
  }
}

void _setLeft(Uint8List buf, int off, int stride, List<int> col) {
  for (var i = 0; i < col.length; i++) {
    buf[off + i * stride - 1] = col[i];
  }
}

void _setTopLeft(Uint8List buf, int off, int stride, int v) {
  buf[off - stride - 1] = v;
}

List<int> _readBlock(Uint8List buf, int off, int stride, int n) {
  final out = <int>[];
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      out.add(buf[off + r * stride + c]);
    }
  }
  return out;
}

void main() {
  group('predict_v_nxn (RFC 6386 §12.2 V_PRED)', () {
    test('replicates the above row down every column (n=4)', () {
      final s = _setup(4);
      _setAbove(s.buf, s.off, s.stride, [10, 20, 30, 40]);
      predict_v_nxn(s.buf, s.off, s.stride, 4);
      final expected = [
        10, 20, 30, 40, //
        10, 20, 30, 40, //
        10, 20, 30, 40, //
        10, 20, 30, 40, //
      ];
      expect(_readBlock(s.buf, s.off, s.stride, 4), expected);
    });

    test('n=8 also replicates correctly', () {
      final s = _setup(8);
      final above = List.generate(8, (i) => i * 10 + 5);
      _setAbove(s.buf, s.off, s.stride, above);
      predict_v_nxn(s.buf, s.off, s.stride, 8);
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 8; c++) {
          expect(
            s.buf[s.off + r * s.stride + c],
            above[c],
            reason: 'V_PRED row=$r col=$c',
          );
        }
      }
    });
  });

  group('predict_h_nxn (RFC 6386 §12.2 H_PRED)', () {
    test('replicates the left column across every row (n=4)', () {
      final s = _setup(4);
      _setLeft(s.buf, s.off, s.stride, [11, 22, 33, 44]);
      predict_h_nxn(s.buf, s.off, s.stride, 4);
      final expected = [
        11, 11, 11, 11, //
        22, 22, 22, 22, //
        33, 33, 33, 33, //
        44, 44, 44, 44, //
      ];
      expect(_readBlock(s.buf, s.off, s.stride, 4), expected);
    });
  });

  group('predict_dc_nxn (RFC 6386 §12.2 DC_PRED)', () {
    test('uniform borders → uniform DC = average of 2n neighbours (n=4)', () {
      final s = _setup(4);
      _setAbove(s.buf, s.off, s.stride, [100, 100, 100, 100]);
      _setLeft(s.buf, s.off, s.stride, [100, 100, 100, 100]);
      predict_dc_nxn(s.buf, s.off, s.stride, 4);
      // Sum = 8*100 = 800; (800+4)>>3 = 100.
      for (final v in _readBlock(s.buf, s.off, s.stride, 4)) {
        expect(v, 100);
      }
    });

    test('rounding: (sum + n) >> log2(2n) for n=8', () {
      final s = _setup(8);
      // Sum = 8*1 + 8*0 = 8; (8+8)>>4 = 1.
      _setAbove(s.buf, s.off, s.stride, List.filled(8, 1));
      _setLeft(s.buf, s.off, s.stride, List.filled(8, 0));
      predict_dc_nxn(s.buf, s.off, s.stride, 8);
      for (final v in _readBlock(s.buf, s.off, s.stride, 8)) {
        expect(v, 1, reason: 'DC of mostly-zero neighbours rounds up to 1');
      }
    });

    test('n=16 averages 32 neighbours with +16 rounding', () {
      final s = _setup(16);
      // Sum = 16*200 + 16*50 = 4000; (4000+16)>>5 = 125.
      _setAbove(s.buf, s.off, s.stride, List.filled(16, 200));
      _setLeft(s.buf, s.off, s.stride, List.filled(16, 50));
      predict_dc_nxn(s.buf, s.off, s.stride, 16);
      for (final v in _readBlock(s.buf, s.off, s.stride, 16)) {
        expect(v, 125, reason: 'DC must be 125');
      }
    });
  });

  group('predict_tm_nxn (RFC 6386 §12.2 TM_PRED)', () {
    test('result[r,c] = clamp(left[r] + above[c] - topleft, 0, 255)', () {
      final s = _setup(4);
      _setAbove(s.buf, s.off, s.stride, [10, 20, 30, 40]);
      _setLeft(s.buf, s.off, s.stride, [50, 60, 70, 80]);
      _setTopLeft(s.buf, s.off, s.stride, 100);
      predict_tm_nxn(s.buf, s.off, s.stride, 4);
      // formula: clamp(left[r] + above[c] - 100)
      // row 0 (left=50): -40, -30, -20, -10  → 0,0,0,0
      // row 1 (left=60): -30, -20, -10, 0    → 0,0,0,0
      // row 2 (left=70): -20, -10,   0, 10   → 0,0,0,10
      // row 3 (left=80): -10,   0,  10, 20   → 0,0,10,20
      final expected = [
        0, 0, 0, 0, //
        0, 0, 0, 0, //
        0, 0, 0, 10, //
        0, 0, 10, 20, //
      ];
      expect(_readBlock(s.buf, s.off, s.stride, 4), expected);
    });

    test('clamps positive overflow to 255', () {
      final s = _setup(4);
      _setAbove(s.buf, s.off, s.stride, [200, 200, 200, 200]);
      _setLeft(s.buf, s.off, s.stride, [200, 200, 200, 200]);
      _setTopLeft(s.buf, s.off, s.stride, 0);
      predict_tm_nxn(s.buf, s.off, s.stride, 4);
      // 200 + 200 - 0 = 400 → clamp 255
      for (final v in _readBlock(s.buf, s.off, s.stride, 4)) {
        expect(v, 255);
      }
    });

    test('clamps negative underflow to 0', () {
      final s = _setup(4);
      _setAbove(s.buf, s.off, s.stride, [10, 10, 10, 10]);
      _setLeft(s.buf, s.off, s.stride, [10, 10, 10, 10]);
      _setTopLeft(s.buf, s.off, s.stride, 200);
      predict_tm_nxn(s.buf, s.off, s.stride, 4);
      // 10 + 10 - 200 = -180 → clamp 0
      for (final v in _readBlock(s.buf, s.off, s.stride, 4)) {
        expect(v, 0);
      }
    });
  });
}
