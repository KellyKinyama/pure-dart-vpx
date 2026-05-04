import 'dart:typed_data';
import '../../vpx/vpx_image.dart';
import '../common/vp8_loopfilter.dart';
import 'detokenize.dart';
import '../../vpx_dsp/bitreader.dart';
import '../common/entropymv.dart';
import '../common/entropy.dart';
import '../common/onyxc_int.dart';
import '../common/quant_common.dart';
import '../common/reconinter.dart';
import '../common/reconintra.dart';
import 'dboolhuff.dart';
import 'decodemv.dart';
import '../common/entropymode.dart';
// import '../vpx/vpx_image.dart';
import '../common/filter.dart';
import 'onyxd_int.dart';
import '../common/blockd.dart';
import '../common/mv.dart';

const int FRAME_HEADER_SZ = 3;
const int KEYFRAME_HEADER_SZ = 7;

const int CURRENT_FRAME = 0;
const int LAST_FRAME = 1;
const int GOLDEN_FRAME = 2;
const int ALTREF_FRAME = 3;
const int NUM_REF_FRAMES = 4;

const int MAX_MB_SEGMENTS = 4;

const int TOKEN_BLOCK_Y1 = 0;
const int TOKEN_BLOCK_UV = 1;
const int TOKEN_BLOCK_Y2 = 2;

const int BORDER_PIXELS = 16;
const int MV_PROB_CNT = 19;
const int MB_FEATURE_TREE_PROBS = 3;

const int DC_PRED = 0;
const int B_PRED = 4;

void vp8cx_init_de_quantizer(VP8D_COMP pbi) {
  final seg = pbi.segment_hdr;
  final common = pbi.common;
  int length = (seg.enabled == 1) ? MAX_MB_SEGMENTS : 1;

  for (int i = 0; i < length; i++) {
    int q = common.mbmi_qindex;
    if (seg.enabled == 1) {
      q = (seg.abs == 0) ? q + seg.quant_idx[i] : seg.quant_idx[i];
    }

    final dqf = pbi.dequantFactors[i];
    if (dqf.quant_idx != q || common.delta_update != 0) {
      dqf.factor[TOKEN_BLOCK_Y1][0] = vp8_dc_quant(q, common.y1dc_delta_q);
      dqf.factor[TOKEN_BLOCK_Y2][0] = vp8_dc2quant(q, common.y2dc_delta_q);
      dqf.factor[TOKEN_BLOCK_UV][0] = vp8_dc_uv_quant(q, common.uvdc_delta_q);
      dqf.factor[TOKEN_BLOCK_Y1][1] = vp8_ac_yquant(q);
      dqf.factor[TOKEN_BLOCK_Y2][1] = vp8_ac2quant(q, common.y2ac_delta_q);
      dqf.factor[TOKEN_BLOCK_UV][1] = vp8_ac_uv_quant(q, common.uvac_delta_q);
      dqf.quant_idx = q;
    }
  }
}

void decode_mb_rows(VP8D_COMP pbi) {
  final img = pbi.frame_buffers[CURRENT_FRAME].img;
  int mb_rows = pbi.common.mb_rows;
  int mb_cols = pbi.common.mb_cols;

  for (int row = 0, partition = 0; row < mb_rows; row++) {
    int mbi_off = pbi.mb_info_rows_off[1 + row];
    final tokens = pbi.tokens[row & (pbi.token_hdr.partitions - 1)];
    final coeffs = tokens.coeffs;
    int coeffs_off = 0;

    // Fix up left for this row
    final mbi_left = pbi.mb_info_rows[mbi_off];
    fixup_left(img, row, mbi_left.mbmi.y_mode, PLANE_Y);
    fixup_left(img, row, mbi_left.mbmi.uv_mode, PLANE_U);
    fixup_left(img, row, mbi_left.mbmi.uv_mode, PLANE_V);

    for (int col = 0; col < mb_cols; col++) {
      if (row == 0) {
        fixup_above(img, col, pbi.mb_info_rows[mbi_off].mbmi.y_mode, PLANE_Y);
        fixup_above(img, col, pbi.mb_info_rows[mbi_off].mbmi.uv_mode, PLANE_U);
        fixup_above(img, col, pbi.mb_info_rows[mbi_off].mbmi.uv_mode, PLANE_V);
      }

      decode_macroblock(
        pbi,
        partition,
        row,
        col,
        img,
        pbi.mb_info_rows[mbi_off],
        coeffs,
        coeffs_off,
      );

      mbi_off++;
      // libvpx reuses the same 400-entry coefficient scratch for every MB
      // (vp8/decoder/threading.c `decode_mb_row` uses `mb->qcoeff` directly).
      // The previous `coeffs_off += 400` was a JS-port artifact that treated
      // the buffer as if it concatenated all MBs in a row, blowing past the
      // 400-element bound at column 1.
    }

    if (pbi.common.level != 0 && row > 0) {
      if (pbi.common.filter_type != 0) {
        vp8_loop_filter_row_simple(pbi, row - 1);
      } else {
        vp8_loop_filter_row_normal(pbi, row - 1, 0, mb_cols);
      }
    }

    if (++partition == pbi.token_hdr.partitions) partition = 0;
  }

  // Final row loop filter
  if (pbi.common.level != 0) {
    if (pbi.common.filter_type != 0) {
      vp8_loop_filter_row_simple(pbi, pbi.common.mb_rows - 1);
    } else {
      vp8_loop_filter_row_normal(
        pbi,
        pbi.common.mb_rows - 1,
        0,
        pbi.common.mb_cols,
      );
    }
  }
}

void fixup_left(vpx_image_t img, int row, int mode, int plane) {
  int stride = img.stride[plane];
  int width = (plane == PLANE_Y) ? 16 : 8;
  int predict_off = img.planes_off[plane] + (stride * row * width);
  int left_off = predict_off - 1;

  if (mode == DC_PRED && row > 0) {
    int above_off = predict_off - stride;
    for (int i = 0; i < width; i++) {
      img.img_data![left_off] = img.img_data![above_off + i];
      left_off += stride;
    }
  } else {
    left_off -= stride;
    for (int i = -1; i < width; i++) {
      img.img_data![left_off] = 129;
      left_off += stride;
    }
  }
}

void fixup_above(vpx_image_t img, int col, int mode, int plane) {
  int stride = img.stride[plane];
  int width = (plane == PLANE_Y) ? 16 : 8;
  int predict_off = img.planes_off[plane] + (col * width);
  int above_off = predict_off - stride;

  if (mode == DC_PRED && col > 0) {
    int left_off = predict_off - 1;
    for (int i = 0; i < width; i++) {
      img.img_data![above_off + i] = img.img_data![left_off];
      left_off += stride;
    }
  } else {
    img.img_data!.fillRange(above_off - 1, above_off + width, 127);
  }
  // above-right subblock modes padding
  img.img_data!.fillRange(above_off + width, above_off + width + 4, 127);
}

void decode_macroblock(
  VP8D_COMP pbi,
  int partition,
  int row,
  int col,
  vpx_image_t img,
  MODE_INFO mbi_cache,
  Int32List coeffs,
  int coeffs_off,
) {
  final tokens = pbi.tokens[partition];
  final left = tokens.left_token_entropy_ctx;

  if (col == 0) left.fillRange(0, left.length, 0);

  final mbmi = mbi_cache.mbmi;
  coeffs.fillRange(coeffs_off, coeffs_off + 400, 0);

  // libvpx layout: the above-token entropy context is row-persistent and
  // indexed by MB column, with 9 entries per column (4 Y top, 2 U top,
  // 2 V top, 1 Y2). Decoders read context for the first coefficient of
  // each block and write back the post-decode PT, so subsequent MB rows
  // see the bottom-row context produced here.
  final aboveCtxStart = col * 9;
  final aboveCtx = Uint8List.sublistView(
    pbi.above_token_entropy_ctx,
    aboveCtxStart,
    aboveCtxStart + 9,
  );

  if (mbmi.mb_skip_coeff == 1) {
    vp8_reset_mb_tokens_context(left, aboveCtx, mbmi.y_mode);
    mbmi.eob_mask = 0;
  } else {
    final dqf = pbi.dequantFactors[mbmi.segment_id];
    mbmi.eob_mask = decode_mb_tokens(
      tokens.bool,
      left,
      aboveCtx,
      coeffs,
      coeffs_off,
      mbmi.y_mode,
      pbi.common.entropy_hdr.coeff_probs,
      dqf.factor,
    );
  }

  if (mbmi.y_mode <= B_PRED) {
    int y_off =
        img.planes_off[PLANE_Y] + (img.stride[PLANE_Y] * row * 16) + (col * 16);
    int u_off =
        img.planes_off[PLANE_U] + (img.stride[PLANE_U] * row * 8) + (col * 8);
    int v_off =
        img.planes_off[PLANE_V] + (img.stride[PLANE_V] * row * 8) + (col * 8);
    predict_intra_chroma(
      img.img_data!,
      u_off,
      img.img_data!,
      v_off,
      img.stride[PLANE_U],
      mbi_cache,
      coeffs,
      coeffs_off,
    );
    predict_intra_luma(
      img.img_data!,
      y_off,
      img.stride[PLANE_Y],
      mbi_cache,
      coeffs,
      coeffs_off,
    );
  } else {
    vp8_build_inter_predictors_mb(
      pbi,
      img,
      coeffs,
      coeffs_off,
      mbi_cache,
      col,
      row,
    );
  }
}

int setup_token_decoder(FRAGMENT_DATA hdr, Uint8List data, int ptr, int sz) {
  int partitions = 1 << hdr.bool.get_uint(2);
  int partition_change = (hdr.partitions != partitions) ? 1 : 0;
  hdr.partitions = partitions;

  if (sz < 3 * (partitions - 1))
    throw "Truncated packet found parsing partition lengths";
  int local_sz = sz - 3 * (partitions - 1);
  int local_ptr = ptr;

  for (int i = 0; i < partitions; i++) {
    if (i < partitions - 1) {
      hdr.partition_sz[i] =
          (data[local_ptr] |
                  (data[local_ptr + 1] << 8) |
                  (data[local_ptr + 2] << 16))
              .toInt();
      local_ptr += 3;
    } else {
      hdr.partition_sz[i] = local_sz;
    }
    if (local_sz < hdr.partition_sz[i]) throw "Truncated partition";
    local_sz -= hdr.partition_sz[i];
  }

  int tokens_ptr = local_ptr;
  for (int i = 0; i < partitions; i++) {
    vp8dx_start_decode(
      hdr.tokens[i].bool,
      data,
      tokens_ptr,
      hdr.partition_sz[i],
    );
    tokens_ptr += hdr.partition_sz[i];
  }
  return partition_change;
}

void init_frame(VP8D_COMP pbi) {
  final pc = pbi.common;
  if (pc.is_key_frame) {
    pc.entropy_hdr.mv_probs[0].setRange(
      0,
      MV_PROB_CNT,
      vp8_default_mv_context[0],
    );
    pc.entropy_hdr.mv_probs[1].setRange(
      0,
      MV_PROB_CNT,
      vp8_default_mv_context[1],
    );
    vp8_init_mbmode_probs(pc);
    vp8_default_coef_probs(pc);
  }
  // libvpx (vp8/decoder/onyxd_if.c `vp8_create_decoder_instances`):
  // mode-info storage must be (re)allocated whenever the frame dimensions
  // change. Without this, `vp8_decode_mode_mvs` indexes into an empty
  // `mb_info_rows_off` and throws RangeError on the first macroblock row.
  if (pc.is_key_frame ||
      pc.frame_size_updated == 1 ||
      pbi.mb_info_rows.isEmpty) {
    pbi.modemv_init();
    _allocFrameBuffers(pbi);
    pc.frame_size_updated = 0;
  }
}

/// libvpx `vp8_alloc_frame_buffers` (vp8/common/alloccommon.c).
///
/// VP8 needs a border of `VP8BORDERINPIXELS = 32` pixels around every plane
/// so that the intra-prediction `[-1]` accesses and inter-prediction MV
/// reaches outside the visible frame are valid. Without this, `fixup_left`
/// dereferences `img_data[-1]` on the first macroblock column.
///
/// We allocate four I420 buffers (CURRENT/LAST/GOLDEN/ALTREF) sized to the
/// 16-byte aligned macroblock grid plus a 32-pixel border on each side.
/// `planes_off[*]` points to the first *visible* pixel; the prediction code
/// can therefore safely read/write at `planes_off + (-1)`.
void _allocFrameBuffers(VP8D_COMP pbi) {
  const border = 32;
  final pc = pbi.common;
  // Use the MB-aligned dims (already computed in vp8_decode_frame):
  final yWidth = pc.mb_cols * 16;
  final yHeight = pc.mb_rows * 16;
  final uvWidth = yWidth >> 1;
  final uvHeight = yHeight >> 1;

  final yStride = yWidth + 2 * border;
  final uvStride = uvWidth + 2 * border;
  final ySize = yStride * (yHeight + 2 * border);
  final uvSize = uvStride * (uvHeight + 2 * border);
  final total = ySize + 2 * uvSize;

  for (var i = 0; i < pbi.frame_buffers.length; i++) {
    final img = pbi.frame_buffers[i].img;
    if (img.img_data != null && img.img_data!.length == total) {
      // Already sized correctly — keep contents (refs / loop filter state).
      continue;
    }
    img.fmt = VPX_IMG_FMT_I420;
    img.bps = 12;
    img.x_chroma_shift = 1;
    img.y_chroma_shift = 1;
    img.w = yWidth;
    img.h = yHeight;
    img.d_w = pc.Width;
    img.d_h = pc.Height;
    img.stride[VPX_PLANE_Y] = yStride;
    img.stride[VPX_PLANE_U] = uvStride;
    img.stride[VPX_PLANE_V] = uvStride;
    img.img_data = Uint8List(total);
    img.img_data_off = 0;
    img.img_data_owner = 1;
    // Plane offsets point at the FIRST VISIBLE PIXEL, leaving the
    // `border` rows above and `border` columns to the left available for
    // out-of-frame prediction reads/writes.
    img.planes_off[VPX_PLANE_Y] = border * yStride + border;
    img.planes_off[VPX_PLANE_U] = ySize + border * uvStride + border;
    img.planes_off[VPX_PLANE_V] = ySize + uvSize + border * uvStride + border;
    // Initialise borders to neutral grey so out-of-frame reads return
    // sensible values even if the border-extension pass is not yet ported.
    img.img_data!.fillRange(0, ySize, 128);
    img.img_data!.fillRange(ySize, ySize + 2 * uvSize, 128);
    // libvpx initialises every freshly allocated frame buffer with a
    // refcount of 1 so the first `swap_frame_buffers` release succeeds.
    pbi.frame_buffers[i].ref_cnt = 1;
  }
}

int vp8_decode_frame(Uint8List data, VP8D_COMP pbi) {
  final bc = pbi.bool_decoder;
  final pc = pbi.common;
  final xd = pbi.segment_hdr;
  int sz = data.length;

  if (sz < 3) return -1;
  int clear0 = data[0];
  pc.is_key_frame = (clear0 & 0x01) == 0;
  pc.version = (clear0 >> 1) & 7;
  pc.show_frame = (clear0 >> 4) & 1;
  int first_partition_sz = (clear0 | (data[1] << 8) | (data[2] << 16)) >> 5;

  if (sz <= first_partition_sz + (pc.is_key_frame ? 10 : 3)) return -1;

  int ptr = FRAME_HEADER_SZ;
  if (pc.is_key_frame) {
    if (data[ptr] != 0x9d || data[ptr + 1] != 0x01 || data[ptr + 2] != 0x2a)
      return -1;
    int w = (data[ptr + 3] | (data[ptr + 4] << 8)) & 0x3fff;
    int h = (data[ptr + 5] | (data[ptr + 6] << 8)) & 0x3fff;
    // RFC 6386 §9.1: width and height are 14-bit unsigned values; reject zero
    // dimensions so downstream allocations / strides cannot divide by zero.
    if (w == 0 || h == 0) return -1;
    pc.horiz_scale = data[ptr + 4] >> 6;
    pc.vert_scale = data[ptr + 6] >> 6;
    if (pc.Width != w || pc.Height != h) {
      pc.Width = w;
      pc.Height = h;
      pc.frame_size_updated = 1;
    }
    ptr += KEYFRAME_HEADER_SZ;
    pc.mb_cols = (pc.Width + 15) >> 4;
    pc.mb_rows = (pc.Height + 15) >> 4;
  }

  vp8dx_start_decode(bc, data, ptr, first_partition_sz);
  if (pc.is_key_frame) {
    // RFC 6386 §9.2: 1 bit color_space, 1 bit clamping_type. These follow the
    // start code on key frames and live in the compressed (boolean-coded)
    // partition, not the uncompressed header.
    pc.color_space = bc.read_bit();
    pc.clamping_type = bc.read_bit();
  }

  init_frame(pbi);

  xd.enabled = bc.read_bit();
  if (xd.enabled == 1) {
    xd.update_map = bc.read_bit();
    xd.update_data = bc.read_bit();
    if (xd.update_data == 1) {
      xd.abs = bc.read_bit();
      for (int i = 0; i < MAX_MB_SEGMENTS; i++)
        xd.quant_idx[i] = bc.maybe_get_int(7);
      for (int i = 0; i < MAX_MB_SEGMENTS; i++)
        xd.lf_level[i] = bc.maybe_get_int(6);
    }
    if (xd.update_map == 1) {
      for (int i = 0; i < MB_FEATURE_TREE_PROBS; i++) {
        xd.tree_probs[i] = bc.read_bit() == 1 ? bc.get_uint(8) : 255;
      }
    }
  }

  if (pc.is_key_frame) {
    pc.filter_type = 0;
    pc.level = 0;
    pc.sharpness = 0;
    pc.delta_enabled = false;
    pc.ref_delta.fillRange(0, 4, 0);
    pc.mode_delta.fillRange(0, 4, 0);
  }

  pc.filter_type = bc.read_bit();
  pc.level = bc.get_uint(6);
  pc.sharpness = bc.get_uint(3);
  pc.delta_enabled = bc.read_bit() == 1;
  if (pc.delta_enabled && bc.read_bit() == 1) {
    for (int i = 0; i < 4; i++) pc.ref_delta[i] = bc.maybe_get_int(6);
    for (int i = 0; i < 4; i++) pc.mode_delta[i] = bc.maybe_get_int(6);
  }

  setup_token_decoder(
    pbi.token_hdr,
    data,
    ptr + first_partition_sz,
    sz - ptr - first_partition_sz,
  );

  pc.mbmi_qindex = bc.get_uint(7);
  pc.delta_update = (pc.mbmi_qindex != 0) ? 1 : 0; // Simple update flag
  pc.y1dc_delta_q = bc.maybe_get_int(4);
  pc.y2dc_delta_q = bc.maybe_get_int(4);
  pc.y2ac_delta_q = bc.maybe_get_int(4);
  pc.uvdc_delta_q = bc.maybe_get_int(4);
  pc.uvac_delta_q = bc.maybe_get_int(4);

  if (pc.is_key_frame) {
    pc.refresh_gf = true;
    pc.refresh_arf = true;
    pc.copy_gf = 0;
    pc.copy_arf = 0;
    pc.sign_bias[GOLDEN_FRAME] = 0;
    pc.sign_bias[ALTREF_FRAME] = 0;
  } else {
    pc.refresh_gf = bc.read_bit() == 1;
    pc.refresh_arf = bc.read_bit() == 1;
    if (!pc.refresh_gf) pc.copy_gf = bc.get_uint(2);
    if (!pc.refresh_arf) pc.copy_arf = bc.get_uint(2);
    pc.sign_bias[GOLDEN_FRAME] = bc.read_bit();
    pc.sign_bias[ALTREF_FRAME] = bc.read_bit();
  }

  pc.refresh_entropy_probs = bc.read_bit();
  pc.refresh_last_frame = pc.is_key_frame ? 1 : bc.read_bit();

  vp8cx_init_de_quantizer(pbi);

  // RFC 6386 §9.10 / §15: any probability updates this frame applies via
  // mb_mode_mv_init / read_mvcontexts must be discarded if
  // refresh_entropy_probs == 0. Snapshot the live FRAME_CONTEXT here and
  // restore it after the frame is fully decoded.
  final FRAME_CONTEXT? _saved_fc = pc.refresh_entropy_probs == 0
      ? (FRAME_CONTEXT()..copyFrom(pc.entropy_hdr))
      : null;

  vp8_decode_mode_mvs(pbi, pbi.bool_decoder);

  decode_mb_rows(pbi);

  if (_saved_fc != null) {
    pc.entropy_hdr.copyFrom(_saved_fc);
  }

  return 0;
}
