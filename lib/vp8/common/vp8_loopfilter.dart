import 'dart:typed_data';
import '../../vpx/vpx_image.dart';
import 'loopfilter_filters.dart';
// import '../vpx/vpx_image.dart';
import 'blockd.dart';
import '../decoder/onyxd_int.dart';

const int CURRENT_FRAME = 0;
const int B_PRED = 4;
const int ZEROMV = 7;
const int SPLITMV = 9;

class FilterParams {
  int edge_limit = 0;
  int interior_limit = 0;
  int hev_threshold = 0;
}

void vp8_loop_filter_row_simple(VP8D_COMP pbi, int row) {
  vpx_image_t img = pbi.frame_buffers[CURRENT_FRAME].img;
  int stride = img.stride[PLANE_Y];
  Uint8List y = img.img_data!;
  int y_off = img.planes_off[PLANE_Y] + (stride * row * 16);

  List<MODE_INFO> mbi = pbi.mb_info_rows;
  int mbi_off = pbi.mb_info_rows_off[1 + row];
  int mb_cols = pbi.common.mb_cols;

  FilterParams params = FilterParams();

  for (int col = 0; col < mb_cols; col++) {
    calculate_filter_parameters(pbi, mbi[mbi_off], params);

    if (params.edge_limit != 0) {
      bool filter_subblocks = (mbi[mbi_off].mbmi.eob_mask != 0 ||
          mbi[mbi_off].mbmi.y_mode == SPLITMV ||
          mbi[mbi_off].mbmi.y_mode == B_PRED);

      int mb_limit = (params.edge_limit + 2) * 2 + params.interior_limit;
      int b_limit = params.edge_limit * 2 + params.interior_limit;

      if (col > 0) {
        vp8_loop_filter_simple_vertical_edge_c(y, y_off, stride, mb_limit);
      }

      if (filter_subblocks) {
        vp8_loop_filter_bvs_c(y, y_off, stride, b_limit);
      }

      if (row > 0) {
        vp8_loop_filter_simple_horizontal_edge_c(y, y_off, stride, mb_limit);
      }

      if (filter_subblocks) {
        vp8_loop_filter_bhs_c(y, y_off, stride, b_limit);
      }
    }

    y_off += 16;
    mbi_off++;
  }
}

void vp8_loop_filter_row_normal(VP8D_COMP pbi, int row, int start_col, int num_cols) {
  vpx_image_t img = pbi.frame_buffers[CURRENT_FRAME].img;
  int stride = img.stride[PLANE_Y];
  int uv_stride = img.stride[PLANE_U];
  Uint8List yuv = img.img_data!;

  int y_off = img.planes_off[PLANE_Y] + (stride * row * 16);
  int u_off = img.planes_off[PLANE_U] + (uv_stride * row * 8);
  int v_off = img.planes_off[PLANE_V] + (uv_stride * row * 8);

  List<MODE_INFO> mbi = pbi.mb_info_rows;
  int mbi_off = pbi.mb_info_rows_off[1 + row] + start_col;

  FilterParams params = FilterParams();

  for (int col = 0; col < num_cols; col++) {
    calculate_filter_parameters(pbi, mbi[mbi_off], params);

    if (params.edge_limit != 0) {
      bool use_filter = (mbi[mbi_off].mbmi.eob_mask != 0 ||
          mbi[mbi_off].mbmi.y_mode == SPLITMV ||
          mbi[mbi_off].mbmi.y_mode == B_PRED);

      if (col > 0 + start_col) {
        vp8_loop_filter_mbv(yuv, y_off, u_off, v_off, stride, uv_stride, params.edge_limit, params.interior_limit, params.hev_threshold);
      }

      if (use_filter) {
        vp8_loop_filter_bv_c(yuv, y_off, u_off, v_off, stride, uv_stride, params.edge_limit, params.interior_limit, params.hev_threshold);
      }

      if (row > 0) {
        filter_mb_h_edge(yuv, y_off, stride, params.edge_limit + 2, params.interior_limit, params.hev_threshold, 2);
        filter_mb_h_edge(yuv, u_off, uv_stride, params.edge_limit + 2, params.interior_limit, params.hev_threshold, 1);
        filter_mb_h_edge(yuv, v_off, uv_stride, params.edge_limit + 2, params.interior_limit, params.hev_threshold, 1);
      }

      if (use_filter) {
        filter_subblock_h_edge(yuv, y_off + 4 * stride, stride, params.edge_limit, params.interior_limit, params.hev_threshold, 2);
        filter_subblock_h_edge(yuv, y_off + 8 * stride, stride, params.edge_limit, params.interior_limit, params.hev_threshold, 2);
        filter_subblock_h_edge(yuv, y_off + 12 * stride, stride, params.edge_limit, params.interior_limit, params.hev_threshold, 2);
        filter_subblock_h_edge(yuv, u_off + 4 * uv_stride, uv_stride, params.edge_limit, params.interior_limit, params.hev_threshold, 1);
        filter_subblock_h_edge(yuv, v_off + 4 * uv_stride, uv_stride, params.edge_limit, params.interior_limit, params.hev_threshold, 1);
      }
    }

    y_off += 16;
    u_off += 8;
    v_off += 8;
    mbi_off++;
  }
}

void calculate_filter_parameters(VP8D_COMP pbi, MODE_INFO mbi, FilterParams params) {
  int filter_level = pbi.common.level;

  if (pbi.segment_hdr.enabled != 0) {
    if (pbi.segment_hdr.abs == 0) {
      filter_level += pbi.segment_hdr.lf_level[mbi.mbmi.segment_id];
    } else {
      filter_level = pbi.segment_hdr.lf_level[mbi.mbmi.segment_id];
    }
  }

  if (pbi.common.delta_enabled) {
    filter_level += pbi.common.ref_delta[mbi.mbmi.ref_frame];
    if (mbi.mbmi.ref_frame == CURRENT_FRAME) {
      if (mbi.mbmi.y_mode == B_PRED) {
        filter_level += pbi.common.mode_delta[0];
      }
    } else if (mbi.mbmi.y_mode == ZEROMV) {
      filter_level += pbi.common.mode_delta[1];
    } else if (mbi.mbmi.y_mode == SPLITMV) {
      filter_level += pbi.common.mode_delta[3];
    } else {
      filter_level += pbi.common.mode_delta[2];
    }
  }

  filter_level = filter_level.clamp(0, 63);
  int interior_limit = filter_level;

  if (pbi.common.sharpness != 0) {
    interior_limit >>= (pbi.common.sharpness > 4 ? 2 : 1);
    int max1 = 9 - pbi.common.sharpness;
    if (interior_limit > max1) interior_limit = max1;
  }

  if (interior_limit < 1) interior_limit = 1;

  int hev_threshold = (filter_level >= 15) ? 1 : 0;
  if (filter_level >= 40) hev_threshold++;
  if (filter_level >= 20 && !pbi.common.is_key_frame) hev_threshold++;

  params.edge_limit = filter_level;
  params.interior_limit = interior_limit;
  params.hev_threshold = hev_threshold;
}

void filter_mb_h_edge(Uint8List src, int src_off, int stride, int edge_limit, int interior_limit, int hev_threshold, int size) {
  int length = size << 3;
  for (int i = 0; i < length; i++) {
    if (normal_threshold(src, src_off, stride, edge_limit, interior_limit)) {
      if (high_edge_variance(src, src_off, stride, hev_threshold)) {
        vp8_filter(src, src_off, stride, true);
      } else {
        filter_mb_edge(src, src_off, stride);
      }
    }
    src_off += 1;
  }
}

void filter_subblock_h_edge(Uint8List src, int src_off, int stride, int edge_limit, int interior_limit, int hev_threshold, int size) {
  int length = size << 3;
  for (int i = 0; i < length; i++) {
    if (normal_threshold(src, src_off, stride, edge_limit, interior_limit)) {
      vp8_filter(src, src_off, stride, high_edge_variance(src, src_off, stride, hev_threshold));
    }
    src_off += 1;
  }
}