// Bit-exact unit tests for the VP8 4x4 sub-block intra predictors used by
// `b_pred` (RFC 6386 §12.3 / libvpx vp8/common/reconintra4x4.c).
//
// Notation matches the RFC:
//   P  = top-left pixel
//   A..H = 8 above pixels (predict_off - stride + 0..7)
//   I..L = 4 left pixels  (predict_off - 1 + 0..3*stride)
//   avg2(a,b)   = (a + b + 1) >> 1
//   avg3(a,b,c) = (a + 2b + c + 2) >> 2
//
// These tests exercise each predictor with hand-set borders and compare the
// 4x4 output byte-for-byte against the spec formula.

import 'dart:typed_data';

import 'package:pure_dart_vpx/vp8/common/reconintra.dart';
import 'package:test/test.dart';

const int _stride = 12;

({Uint8List buf, int off}) _setup({
  required int p,
  required List<int> above,
  required List<int> left,
}) {
  final buf = Uint8List(_stride * (4 + 4));
  buf.fillRange(0, buf.length, 0xCC); // sentinel
  final off = 1 * _stride + 1;
  buf[off - _stride - 1] = p;
  for (var i = 0; i < above.length; i++) {
    buf[off - _stride + i] = above[i];
  }
  for (var i = 0; i < left.length; i++) {
    buf[off + i * _stride - 1] = left[i];
  }
  return (buf: buf, off: off);
}

List<int> _block(Uint8List buf, int off) {
  final out = <int>[];
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 4; c++) {
      out.add(buf[off + r * _stride + c]);
    }
  }
  return out;
}

int _avg2(int a, int b) => (a + b + 1) >> 1;
int _avg3(int a, int b, int c) => (a + 2 * b + c + 2) >> 2;

void main() {
  group('predict_ve_4x4 (RFC §12.3 B_VE_PRED)', () {
    test('row 0 = avg3 of [P,A,B] [A,B,C] [B,C,D] [C,D,E]; rows 1..3 copy', () {
      const p = 10;
      final above = [20, 30, 40, 50, 60]; // A..E (need a4 too)
      final left = [70, 80, 90, 100];
      final s = _setup(p: p, above: above, left: left);
      predict_ve_4x4(s.buf, s.off, _stride);

      final r0c0 = _avg3(p, above[0], above[1]);
      final r0c1 = _avg3(above[0], above[1], above[2]);
      final r0c2 = _avg3(above[1], above[2], above[3]);
      final r0c3 = _avg3(above[2], above[3], above[4]);
      final expected = [
        r0c0, r0c1, r0c2, r0c3, //
        r0c0, r0c1, r0c2, r0c3, //
        r0c0, r0c1, r0c2, r0c3, //
        r0c0, r0c1, r0c2, r0c3, //
      ];
      expect(_block(s.buf, s.off), expected);
    });
  });

  group('predict_he_4x4 (RFC §12.3 B_HE_PRED)', () {
    test('row r = avg3(L[r-1], L[r], L[r+1]); L[-1]=P, L[3+]=L[3]', () {
      const p = 10;
      final above = [20, 30, 40, 50];
      final left = [50, 60, 70, 80]; // I..L
      final s = _setup(p: p, above: above, left: left);
      predict_he_4x4(s.buf, s.off, _stride);

      // Row r filled uniformly with avg3(prev, cur, next).
      final v0 = _avg3(p, left[0], left[1]); // P, I, J
      final v1 = _avg3(left[0], left[1], left[2]); // I, J, K
      final v2 = _avg3(left[1], left[2], left[3]); // J, K, L
      final v3 = _avg3(left[2], left[3], left[3]); // K, L, L (edge dup)
      final expected = [
        v0, v0, v0, v0, //
        v1, v1, v1, v1, //
        v2, v2, v2, v2, //
        v3, v3, v3, v3, //
      ];
      expect(_block(s.buf, s.off), expected);
    });
  });

  group('predict_ld_4x4 (RFC §12.3 B_LD_PRED)', () {
    test('diagonal-down-left: avg3 of three above pixels', () {
      final above = [10, 20, 30, 40, 50, 60, 70, 80]; // A..H
      final left = [0, 0, 0, 0];
      final s = _setup(p: 0, above: above, left: left);
      predict_ld_4x4(s.buf, s.off, _stride);

      // pp[r,c] = avg3(A[r+c], A[r+c+1], A[r+c+2]) with A[8] aliased to A[7].
      final ext = [...above, above[7]]; // length 9
      final expected = <int>[];
      for (var r = 0; r < 4; r++) {
        for (var c = 0; c < 4; c++) {
          expected.add(_avg3(ext[r + c], ext[r + c + 1], ext[r + c + 2]));
        }
      }
      expect(_block(s.buf, s.off), expected);
    });
  });

  group('predict_rd_4x4 (RFC §12.3 B_RD_PRED)', () {
    test('diagonal-down-right: each anti-diagonal carries one avg3 value', () {
      const p = 100;
      final above = [10, 20, 30, 40]; // A..D
      final left = [50, 60, 70, 80]; // I..L
      final s = _setup(p: p, above: above, left: left);
      predict_rd_4x4(s.buf, s.off, _stride);

      // Diagonals indexed by d = r - c:
      //   d= 0: avg3(I, P, A)
      //   d= 1: avg3(P, A, B)
      //   d= 2: avg3(A, B, C)
      //   d= 3: avg3(B, C, D)
      //   d=-1: avg3(J, I, P)
      //   d=-2: avg3(K, J, I)
      //   d=-3: avg3(L, K, J)
      int diag(int d) {
        if (d == 0) return _avg3(left[0], p, above[0]);
        if (d == 1) return _avg3(p, above[0], above[1]);
        if (d == 2) return _avg3(above[0], above[1], above[2]);
        if (d == 3) return _avg3(above[1], above[2], above[3]);
        if (d == -1) return _avg3(left[1], left[0], p);
        if (d == -2) return _avg3(left[2], left[1], left[0]);
        if (d == -3) return _avg3(left[3], left[2], left[1]);
        throw 'unexpected diag $d';
      }

      final expected = <int>[];
      for (var r = 0; r < 4; r++) {
        for (var c = 0; c < 4; c++) {
          expected.add(diag(c - r));
        }
      }
      expect(_block(s.buf, s.off), expected);
    });
  });

  group('predict_vr_4x4 (RFC §12.3 B_VR_PRED)', () {
    test('rows 0,2 use avg2; rows 1,3 use avg3 (vertical-right)', () {
      const p = 100;
      final above = [10, 20, 30, 40, 50]; // A..E
      final left = [60, 70, 80, 90]; // I..L
      final s = _setup(p: p, above: above, left: left);
      predict_vr_4x4(s.buf, s.off, _stride);

      final r0 = [
        _avg2(p, above[0]),
        _avg2(above[0], above[1]),
        _avg2(above[1], above[2]),
        _avg2(above[2], above[3]),
      ];
      final r1 = [
        _avg3(left[0], p, above[0]),
        _avg3(p, above[0], above[1]),
        _avg3(above[0], above[1], above[2]),
        _avg3(above[1], above[2], above[3]),
      ];
      final r2 = [_avg3(p, left[0], left[1]), r0[0], r0[1], r0[2]];
      final r3 = [_avg3(left[0], left[1], left[2]), r1[0], r1[1], r1[2]];
      expect(_block(s.buf, s.off), [...r0, ...r1, ...r2, ...r3]);
    });
  });

  group('predict_vl_4x4 (RFC §12.3 B_VL_PRED)', () {
    test('rows 0,2 avg2; rows 1,3 avg3 (vertical-left)', () {
      final above = [10, 20, 30, 40, 50, 60, 70, 80]; // A..H
      final s = _setup(p: 0, above: above, left: [0, 0, 0, 0]);
      predict_vl_4x4(s.buf, s.off, _stride);

      final r0 = [
        _avg2(above[0], above[1]),
        _avg2(above[1], above[2]),
        _avg2(above[2], above[3]),
        _avg2(above[3], above[4]),
      ];
      final r1 = [
        _avg3(above[0], above[1], above[2]),
        _avg3(above[1], above[2], above[3]),
        _avg3(above[2], above[3], above[4]),
        _avg3(above[3], above[4], above[5]),
      ];
      final r2 = [r0[1], r0[2], r0[3], _avg3(above[4], above[5], above[6])];
      final r3 = [r1[1], r1[2], r1[3], _avg3(above[5], above[6], above[7])];
      expect(_block(s.buf, s.off), [...r0, ...r1, ...r2, ...r3]);
    });
  });

  group('predict_hd_4x4 (RFC §12.3 B_HD_PRED)', () {
    test('horizontal-down: cols 0/2 avg2, cols 1/3 avg3', () {
      const p = 100;
      final above = [10, 20, 30, 40]; // A..D (only A..C used)
      final left = [50, 60, 70, 80]; // I..L
      final s = _setup(p: p, above: above, left: left);
      predict_hd_4x4(s.buf, s.off, _stride);

      // Per libvpx reconintra4x4.c:
      final r0 = [
        _avg2(left[0], p),
        _avg3(left[0], p, above[0]),
        _avg3(p, above[0], above[1]),
        _avg3(above[0], above[1], above[2]),
      ];
      final r1 = [
        _avg2(left[1], left[0]),
        _avg3(left[1], left[0], p),
        r0[0],
        r0[1],
      ];
      final r2 = [
        _avg2(left[2], left[1]),
        _avg3(left[2], left[1], left[0]),
        r1[0],
        r1[1],
      ];
      final r3 = [
        _avg2(left[3], left[2]),
        _avg3(left[3], left[2], left[1]),
        r2[0],
        r2[1],
      ];
      expect(_block(s.buf, s.off), [...r0, ...r1, ...r2, ...r3]);
    });
  });

  group('predict_hu_4x4 (RFC §12.3 B_HU_PRED)', () {
    test('horizontal-up: triangular pattern based on left column', () {
      final left = [50, 60, 70, 80]; // I..L
      final s = _setup(p: 0, above: [0, 0, 0, 0], left: left);
      predict_hu_4x4(s.buf, s.off, _stride);

      final p0 = _avg2(left[0], left[1]); // (I+J+1)/2
      final p1 = _avg3(left[0], left[1], left[2]); // (I+2J+K)
      final p2 = _avg2(left[1], left[2]);
      final p3 = _avg3(left[1], left[2], left[3]);
      final p4 = _avg2(left[2], left[3]);
      final p5 = _avg3(left[2], left[3], left[3]); // edge dup
      final l3 = left[3];

      final expected = [
        p0, p1, p2, p3, //
        p2, p3, p4, p5, //
        p4, p5, l3, l3, //
        l3, l3, l3, l3, //
      ];
      expect(_block(s.buf, s.off), expected);
    });
  });
}
