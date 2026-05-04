import 'dart:typed_data';
import '../common/onyxc_int.dart';
import './dboolhuff.dart';
import '../common/blockd.dart';
import '../common/filter.dart';
import '../../vpx/vpx_image.dart';

const int MAX_PARTITIONS = 8;
const int MAX_MB_SEGMENTS = 4;

class RefCntImg {
  final vpx_image_t img = vpx_image_t();
  int ref_cnt = 0;
}

class DequantFactors {
  int quant_idx = 0;
  final List<Int16List> factor = [
    Int16List(2), // Y1
    Int16List(2), // UV
    Int16List(2), // Y2
  ];
}

class TokenDecoder {
  final BOOL_DECODER bool = BOOL_DECODER();
  final Uint32List left_token_entropy_ctx = Uint32List(9);
  late final Int32List coeffs;

  TokenDecoder() {
    coeffs = Int32List(16 * 25); // 400 coeffs per MB
  }
}

class FRAGMENT_DATA {
  final VP8D_COMP pbi;
  int partitions = 1;
  final Int32List partition_sz = Int32List(MAX_PARTITIONS);
  final List<TokenDecoder> tokens = List.generate(
    MAX_PARTITIONS,
    (_) => TokenDecoder(),
  );

  FRAGMENT_DATA(this.pbi);

  BOOL_DECODER get bool => pbi.bool_decoder;
}

class VP8D_COMP {
  final VP8_COMMON common = VP8_COMMON();
  final BOOL_DECODER bool_decoder = BOOL_DECODER();
  late final MACROBLOCKD segment_hdr;
  late final FRAGMENT_DATA token_hdr;

  List<MODE_INFO> mb_info_rows = [];
  List<int> mb_info_rows_off = [];

  /// Per-MB-column persistent token entropy context (above row).
  ///
  /// Each MB column owns 9 entries: 4 luma top + 2 U top + 2 V top + 1 Y2.
  /// `decode_mb_tokens` reads them as the above-context PT for the first
  /// coefficient of every block and writes back the resulting PT after the
  /// block is consumed. Therefore this buffer MUST persist across MB rows
  /// (the bottom-row PT of MB row R is the above-context for row R+1).
  /// libvpx: `vp8/common/blockd.h ENTROPY_CONTEXT_PLANES`.
  late Uint8List above_token_entropy_ctx;

  final List<RefCntImg> frame_buffers = List.generate(4, (_) => RefCntImg());
  late final List<DequantFactors> dequantFactors;

  /// Byte offsets from the start of img_data for each reference frame buffer.
  final Int32List ref_frame_offsets = Int32List(4);

  /// Sub-pixel interpolation filters (bilinear or 6-tap).
  List<FilterWithShape> subpixel_filters = vp8_sub_pel_filters;

  VP8D_COMP() {
    segment_hdr = MACROBLOCKD();
    token_hdr = FRAGMENT_DATA(this);
    above_token_entropy_ctx = Uint8List(128 * 9);
    dequantFactors = List.generate(MAX_MB_SEGMENTS, (_) => DequantFactors());
  }

  TokenDecoder get tokens_active => token_hdr.tokens[0]; // fallback
  List<TokenDecoder> get tokens => token_hdr.tokens;

  void modemv_init() {
    int mb_cols = common.mb_cols;
    int mb_rows = common.mb_rows;
    int mbi_w = mb_cols + 1;
    int mbi_h = mb_rows + 1;

    common.mode_info_stride = mbi_w;

    int length = mbi_w * mbi_h;
    mb_info_rows = List.generate(length, (_) => MODE_INFO());
    mb_info_rows_off = List.generate(mbi_h, (i) => i * mbi_w + 1);

    if (above_token_entropy_ctx.length < mb_cols * 9) {
      above_token_entropy_ctx = Uint8List(mb_cols * 9);
    }
    // libvpx resets the row context to zero at the start of every frame
    // (see vp8/common/setupintrarecon.c). Without this, mid-stream context
    // leaks across frames and tokens decode incorrectly.
    above_token_entropy_ctx.fillRange(0, above_token_entropy_ctx.length, 0);
  }
}
