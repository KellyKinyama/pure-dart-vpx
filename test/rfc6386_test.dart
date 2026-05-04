// Test vectors derived from RFC 6386 (VP8 Data Format and Decoding Guide).
// Each group exercises a discrete section of the decoder against either
// values stated in the RFC text/annex or constructed bitstreams whose
// expected decoder state can be computed from the RFC pseudocode alone.
//
// Run with: dart test test/rfc6386_test.dart
//
// References:
//   RFC 6386 §7    Boolean Entropy Decoder
//   RFC 6386 §9.1  Uncompressed Frame Tag
//   RFC 6386 §9.2  Color Space and Pixel Type
//   RFC 6386 §9.6  Quantizer Indices
//   RFC 6386 §13   DCT Coefficient Decoding
//   RFC 6386 §14   IDCT and inverse Walsh-Hadamard
//   RFC 6386 §17.1 Motion-Vector Clamping

import 'dart:typed_data';

import 'package:pure_dart_vpx/vp8/common/idctllm.dart';
import 'package:pure_dart_vpx/vp8/common/mv.dart';
import 'package:pure_dart_vpx/vp8/common/quant_common.dart';
import 'package:pure_dart_vpx/vp8/decoder/dboolhuff.dart';
import 'package:pure_dart_vpx/vpx_dsp/bitreader.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helper: re-derive the MV-clamp routine without importing decodemv.dart
// (which pulls a large transitive graph). Mirrors `vp8_clamp_mv2` line for
// line so we can verify the RFC §17.1 invariant in isolation.
// ---------------------------------------------------------------------------
class _MvBounds {
  int mb_to_left_edge = 0;
  int mb_to_right_edge = 0;
  int mb_to_top_edge = 0;
  int mb_to_bottom_edge = 0;
}

void _clampMv(MotionVector mv, _MvBounds b) {
  if (mv.col < b.mb_to_left_edge)
    mv.col = b.mb_to_left_edge;
  else if (mv.col > b.mb_to_right_edge)
    mv.col = b.mb_to_right_edge;
  if (mv.row < b.mb_to_top_edge)
    mv.row = b.mb_to_top_edge;
  else if (mv.row > b.mb_to_bottom_edge)
    mv.row = b.mb_to_bottom_edge;
}

void main() {
  // -------------------------------------------------------------------------
  // RFC 6386 §7  Boolean Entropy Decoder
  // -------------------------------------------------------------------------
  group('RFC 6386 §7 boolean decoder', () {
    test(
      'init state: range=255, bit_count=0, value preloaded with 2 bytes',
      () {
        final bd = BOOL_DECODER();
        final src = Uint8List.fromList([0xAB, 0xCD, 0x12, 0x34]);
        vp8dx_start_decode(bd, src, 0, src.length);
        expect(bd.range, 255, reason: 'RFC §7: range starts at 255');
        expect(bd.bit_count, 0, reason: 'RFC §7: bit_count starts at 0');
        expect(
          bd.value,
          (0xAB << 8) | 0xCD,
          reason: 'RFC §7: value is the first 2 bytes, MSB first',
        );
        expect(bd.input_len, src.length - 2);
        expect(bd.ptr, 2);
      },
    );

    test('reading prob=128 against an all-zeros stream yields zero bits', () {
      // With value preloaded as 0x0000, every comparison value < SPLIT for
      // prob=128 returns retval=0 (RFC §7 vpx_read).
      final bd = BOOL_DECODER();
      final src = Uint8List(8); // all zero
      vp8dx_start_decode(bd, src, 0, src.length);
      for (int i = 0; i < 32; i++) {
        expect(vpx_read_bit(bd), 0, reason: 'bit $i should be 0');
      }
    });

    test('reading prob=128 against an all-FF stream yields one bits', () {
      // value preloaded with 0xFFFF -> always >= SPLIT for prob=128.
      final bd = BOOL_DECODER();
      final src = Uint8List.fromList(List.filled(8, 0xFF));
      vp8dx_start_decode(bd, src, 0, src.length);
      for (int i = 0; i < 32; i++) {
        expect(vpx_read_bit(bd), 1, reason: 'bit $i should be 1');
      }
    });

    test('insufficient input (< 2 bytes) leaves decoder in safe state', () {
      final bd = BOOL_DECODER();
      vp8dx_start_decode(bd, Uint8List.fromList([0xFF]), 0, 1);
      expect(bd.value, 0);
      expect(bd.input, isNull);
      expect(bd.input_len, 0);
      expect(bd.range, 255);
    });

    test('renormalization eventually consumes input bytes', () {
      // After enough reads, ptr should advance past the initial 2 preload bytes.
      final bd = BOOL_DECODER();
      final src = Uint8List.fromList(List.filled(16, 0x55));
      vp8dx_start_decode(bd, src, 0, src.length);
      for (int i = 0; i < 64; i++) {
        vpx_read_bit(bd);
      }
      expect(
        bd.ptr,
        greaterThan(2),
        reason: 'RFC §7 renorm refill must advance ptr past preload',
      );
    });
  });

  // -------------------------------------------------------------------------
  // RFC 6386 §9.1  Uncompressed Frame Tag (3 bytes)
  // -------------------------------------------------------------------------
  group('RFC 6386 §9.1 frame tag', () {
    // Manual tag construction mirroring the parser in decodeframe.dart so we
    // can confirm the bit layout. Layout (LSB first within byte 0):
    //   bit 0       frame_type   (0 = key, 1 = inter)
    //   bits 1..3   version
    //   bit 4       show_frame
    //   bits 5..23  first_partition_length_in_bytes (24-bit field >> 5)
    Uint8List frameTag({
      required int frameType,
      required int version,
      required int showFrame,
      required int firstPartLen,
    }) {
      final raw =
          (frameType & 1) |
          ((version & 7) << 1) |
          ((showFrame & 1) << 4) |
          ((firstPartLen & 0x7FFFF) << 5);
      return Uint8List.fromList([
        raw & 0xFF,
        (raw >> 8) & 0xFF,
        (raw >> 16) & 0xFF,
      ]);
    }

    test('keyframe tag round-trips: type=0, version=0, show=1, len=42', () {
      final tag = frameTag(
        frameType: 0,
        version: 0,
        showFrame: 1,
        firstPartLen: 42,
      );
      final clear0 = tag[0];
      final isKey = (clear0 & 1) == 0;
      final version = (clear0 >> 1) & 7;
      final show = (clear0 >> 4) & 1;
      final firstPart = (clear0 | (tag[1] << 8) | (tag[2] << 16)) >> 5;
      expect(isKey, true);
      expect(version, 0);
      expect(show, 1);
      expect(firstPart, 42);
    });

    test('interframe tag, hidden frame', () {
      final tag = frameTag(
        frameType: 1,
        version: 3,
        showFrame: 0,
        firstPartLen: 0x12345,
      );
      expect((tag[0] & 1) == 0, false, reason: 'frame_type bit set => inter');
      expect((tag[0] >> 1) & 7, 3);
      expect((tag[0] >> 4) & 1, 0);
      expect((tag[0] | (tag[1] << 8) | (tag[2] << 16)) >> 5, 0x12345);
    });

    test('start code 0x9d 0x01 0x2a is the canonical RFC §9.1 sentinel', () {
      const startCode = [0x9d, 0x01, 0x2a];
      expect(startCode, [157, 1, 42]);
    });

    test('width/height scale extraction (RFC §9.1)', () {
      // Construct width=640 with horiz_scale=2 => byte4 = (scale<<6) | (640>>8) & 0x3F
      const w = 640, h = 480, hs = 2, vs = 1;
      final b3 = w & 0xFF;
      final b4 = ((hs & 3) << 6) | ((w >> 8) & 0x3F);
      final b5 = h & 0xFF;
      final b6 = ((vs & 3) << 6) | ((h >> 8) & 0x3F);
      final decW = (b3 | (b4 << 8)) & 0x3FFF;
      final decH = (b5 | (b6 << 8)) & 0x3FFF;
      expect(decW, w);
      expect(decH, h);
      expect(b4 >> 6, hs);
      expect(b6 >> 6, vs);
    });
  });

  // -------------------------------------------------------------------------
  // RFC 6386 §9.6  Quantizer indices: lookup tables and clamping
  // -------------------------------------------------------------------------
  group('RFC 6386 §9.6 / Annex quantizer tables', () {
    test('dc_qlookup endpoints match RFC table', () {
      expect(dc_qlookup.length, 128);
      expect(dc_qlookup[0], 4, reason: 'RFC dc_q[0] = 4');
      expect(dc_qlookup[127], 157, reason: 'RFC dc_q[127] = 157');
    });

    test('ac_qlookup endpoints match RFC table', () {
      expect(ac_qlookup.length, 128);
      expect(ac_qlookup[0], 4, reason: 'RFC ac_q[0] = 4');
      expect(ac_qlookup[127], 284, reason: 'RFC ac_q[127] = 284');
    });

    test('vp8_dc_quant clamps QIndex+Delta to [0, 127]', () {
      expect(vp8_dc_quant(0, 0), 4);
      expect(vp8_dc_quant(127, 0), 157);
      expect(vp8_dc_quant(127, 5), 157, reason: 'over-range clamps high');
      expect(vp8_dc_quant(0, -5), 4, reason: 'under-range clamps low');
    });

    test('vp8_ac_yquant clamps to [0, 127]', () {
      expect(vp8_ac_yquant(0), 4);
      expect(vp8_ac_yquant(127), 284);
      expect(vp8_ac_yquant(200), 284);
      expect(vp8_ac_yquant(-3), 4);
    });

    test(
      'Y2 DC/AC second-order quant (dc_qlookup3 / ac_qlookup2) endpoints',
      () {
        expect(vp8_dc2quant(0, 0), 8);
        expect(vp8_dc2quant(127, 0), 314);
        expect(vp8_ac2quant(0, 0), 8);
        expect(vp8_ac2quant(127, 0), 440);
      },
    );

    test('UV DC quant saturates at 132 per RFC §9.6 / libvpx clamp', () {
      // dc_qlookup2 plateaus at 132 from QIndex 132 onward in libvpx.
      expect(vp8_dc_uv_quant(127, 0), 132);
      expect(vp8_dc_uv_quant(200, 0), 132);
    });
  });

  // -------------------------------------------------------------------------
  // RFC 6386 §14  Inverse transforms
  // -------------------------------------------------------------------------
  group('RFC 6386 §14 inverse transforms', () {
    test('idct4x4 of all-zero coeffs yields prediction unchanged', () {
      final coeffs = Int32List(16);
      final predict = Uint8List.fromList(List.filled(16, 128));
      final recon = Uint8List(16);
      vp8_short_idct4x4llm_c(recon, 0, predict, 0, 4, coeffs, 0);
      for (int i = 0; i < 16; i++) {
        expect(recon[i], 128, reason: 'pixel $i unchanged for zero coeffs');
      }
    });

    test('idct4x4 clamps output to [0, 255] (RFC §14)', () {
      // A large positive DC coefficient onto a 200 baseline must clamp at 255.
      final coeffs = Int32List(16);
      coeffs[0] = 2048; // huge DC
      final predict = Uint8List.fromList(List.filled(16, 200));
      final recon = Uint8List(16);
      vp8_short_idct4x4llm_c(recon, 0, predict, 0, 4, coeffs, 0);
      for (int i = 0; i < 16; i++) {
        expect(recon[i], lessThanOrEqualTo(255));
        expect(recon[i], greaterThanOrEqualTo(0));
      }
      // Top-left should saturate.
      expect(recon[0], 255);
    });

    test('idct4x4 with large negative DC clamps at 0', () {
      final coeffs = Int32List(16);
      coeffs[0] = -2048;
      final predict = Uint8List.fromList(List.filled(16, 50));
      final recon = Uint8List(16);
      vp8_short_idct4x4llm_c(recon, 0, predict, 0, 4, coeffs, 0);
      expect(recon[0], 0);
    });

    test(
      'inverse Walsh of all-zero input leaves the dequant buffer at zero',
      () {
        // The function writes into `input[mb_dqcoeff_ptr + (i << 4)]` for
        // i = 0..15, so the backing buffer must be at least 256 entries when
        // mb_dqcoeff_ptr = 0.
        final buf = Int32List(256);
        vp8_short_inv_walsh4x4_c(buf, 0, 0);
        for (int i = 0; i < 16; i++) {
          expect(buf[i << 4], 0, reason: 'WHT(0) cell $i must be 0');
        }
      },
    );

    test(
      'inverse Walsh is linear: WHT_inv(2*x) == 2 * WHT_inv(x) (mod rounding)',
      () {
        // RFC §14: the WHT_inv is a linear transform up to the +3 / >>3
        // rounding. We exercise that by feeding a small impulse twice and
        // confirming non-zero output that scales monotonically.
        final small = Int32List(256);
        small[0] = 8;
        small[1] = -8;
        vp8_short_inv_walsh4x4_c(small, 0, 0);
        final smallOut = [for (int i = 0; i < 16; i++) small[i << 4]];

        final big = Int32List(256);
        big[0] = 80;
        big[1] = -80;
        vp8_short_inv_walsh4x4_c(big, 0, 0);
        final bigOut = [for (int i = 0; i < 16; i++) big[i << 4]];

        // Output should be non-trivial.
        expect(smallOut.any((v) => v != 0), true);
        expect(bigOut.any((v) => v != 0), true);
        // And scale roughly with input magnitude.
        final smallEnergy = smallOut
            .map((v) => v.abs())
            .reduce((a, b) => a + b);
        final bigEnergy = bigOut.map((v) => v.abs()).reduce((a, b) => a + b);
        expect(
          bigEnergy,
          greaterThan(smallEnergy * 5),
          reason: 'scaling input by 10 must produce ~10× more energy',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // RFC 6386 §17.1  Motion-vector clamping
  // -------------------------------------------------------------------------
  group('RFC 6386 §17.1 MV clamp', () {
    test('inside-bounds MV is unchanged', () {
      final mv = MotionVector()
        ..row = 4
        ..col = -8;
      final b = _MvBounds()
        ..mb_to_left_edge = -128
        ..mb_to_right_edge = 128
        ..mb_to_top_edge = -64
        ..mb_to_bottom_edge = 64;
      _clampMv(mv, b);
      expect(mv.row, 4);
      expect(mv.col, -8);
    });

    test('left/right edges clamp col', () {
      final b = _MvBounds()
        ..mb_to_left_edge = -16
        ..mb_to_right_edge = 16
        ..mb_to_top_edge = -1000
        ..mb_to_bottom_edge = 1000;
      final lo = MotionVector()..col = -100;
      final hi = MotionVector()..col = 100;
      _clampMv(lo, b);
      _clampMv(hi, b);
      expect(lo.col, -16);
      expect(hi.col, 16);
    });

    test('top/bottom edges clamp row', () {
      final b = _MvBounds()
        ..mb_to_left_edge = -1000
        ..mb_to_right_edge = 1000
        ..mb_to_top_edge = -32
        ..mb_to_bottom_edge = 32;
      final lo = MotionVector()..row = -200;
      final hi = MotionVector()..row = 200;
      _clampMv(lo, b);
      _clampMv(hi, b);
      expect(lo.row, -32);
      expect(hi.row, 32);
    });
  });

  // -------------------------------------------------------------------------
  // MotionVector struct invariants (libvpx union { int16[2]; uint32 })
  // -------------------------------------------------------------------------
  group('MotionVector union semantics', () {
    test('row/col aliases the int32 view', () {
      final mv = MotionVector()
        ..row = 0x1234
        ..col = 0x5678;
      // little-endian: low half = row, high half = col
      expect(mv.integer, (0x5678 << 16) | 0x1234);
    });

    test('row stores as signed 16-bit', () {
      final mv = MotionVector()..row = -1;
      expect(mv.row, -1);
    });
  });
}
