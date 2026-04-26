import 'dart:typed_data';
import '../../vpx/vpx_image.dart';
import 'mv.dart';
import 'filter.dart';
import 'idctllm.dart';
import '../decoder/onyxd_int.dart';
// import '../vpx/vpx_image.dart';
import 'blockd.dart';

const int SPLITMV = 9;

final List<MotionVector> chroma_mv = List.generate(4, (_) => MotionVector());

void predict_inter_emulated_edge(
  VP8D_COMP pbi,
  vpx_image_t img,
  Int32List coeffs,
  int coeffs_off,
  MODE_INFO mbi,
  int mb_col,
  int mb_row,
) {
  Uint8List emul_block = pbi.frame_buffers[0].img.img_data!;
  int emul_block_off = 0; // img_data is usually from index 0 in our case

  int x = mb_col << 4;
  int y = mb_row << 4;
  int w = pbi.common.mb_cols << 4;
  int h = pbi.common.mb_rows << 4;

  Uint8List dst_y = img.img_data!;
  int dst_y_off =
      img.planes_off[PLANE_Y] +
      (img.stride[PLANE_Y] * mb_row * 16) +
      (mb_col * 16);
  int stride = img.stride[PLANE_Y];

  int ref_frame = mbi.mbmi.ref_frame;
  int reference_offset = pbi.ref_frame_offsets[ref_frame];
  Uint8List reference =
      img.img_data!; // Assuming all ref frames are in same img_data buffer

  int mode = mbi.mbmi.y_mode;
  List<MotionVector>? mvs = mbi.bmi?.mvs;

  // Luma
  for (int b = 0; b < 16; b++) {
    MotionVector ymv;
    if (mode != SPLITMV) {
      ymv = mbi.mbmi.mv;
    } else {
      ymv = mvs![b];
    }

    recon_1_edge_block(
      dst_y,
      dst_y_off,
      emul_block,
      emul_block_off,
      reference,
      dst_y_off + reference_offset,
      stride,
      ymv,
      pbi.subpixel_filters,
      coeffs,
      coeffs_off,
      mbi,
      x,
      y,
      w,
      h,
      b,
    );

    x += 4;
    dst_y_off += 4;
    if ((b & 3) == 3) {
      x -= 16;
      y += 4;
      dst_y_off += (stride << 2) - 16;
    }
  }

  // Chroma
  x = mb_col << 3;
  y = mb_row << 3;
  w >>= 1;
  h >>= 1;
  int uv_stride = img.stride[PLANE_U];
  int dst_u_off =
      img.planes_off[PLANE_U] + (uv_stride * mb_row * 8) + (mb_col * 8);
  int dst_v_off =
      img.planes_off[PLANE_V] + (uv_stride * mb_row * 8) + (mb_col * 8);

  for (int b = 0; b < 4; b++) {
    recon_1_edge_block(
      img.img_data!,
      dst_u_off,
      emul_block,
      emul_block_off,
      reference,
      dst_u_off + reference_offset,
      uv_stride,
      chroma_mv[b],
      pbi.subpixel_filters,
      coeffs,
      coeffs_off,
      mbi,
      x,
      y,
      w,
      h,
      b + 16,
    );
    recon_1_edge_block(
      img.img_data!,
      dst_v_off,
      emul_block,
      emul_block_off,
      reference,
      dst_v_off + reference_offset,
      uv_stride,
      chroma_mv[b],
      pbi.subpixel_filters,
      coeffs,
      coeffs_off,
      mbi,
      x,
      y,
      w,
      h,
      b + 20,
    );

    dst_u_off += 4;
    dst_v_off += 4;
    x += 4;
    if ((b & 1) == 1) {
      x -= 8;
      y += 4;
      dst_u_off += (uv_stride << 2) - 8;
      dst_v_off += (uv_stride << 2) - 8;
    }
  }
}

void build_4x4uvmvs(MODE_INFO mbi, bool full_pixel) {
  List<MotionVector> mvs = mbi.bmi!.mvs;
  for (int i = 0; i < 2; ++i) {
    for (int j = 0; j < 2; ++j) {
      int b = (i << 3) + (j << 1);
      int chroma_ptr = (i << 1) + j;
      MotionVector cmv = chroma_mv[chroma_ptr];

      int temp_row =
          mvs[b].row + mvs[b + 1].row + mvs[b + 4].row + mvs[b + 5].row;
      if (temp_row < 0)
        temp_row -= 4;
      else
        temp_row += 4;
      cmv.row = (temp_row ~/ 8);

      int temp_col =
          mvs[b].col + mvs[b + 1].col + mvs[b + 4].col + mvs[b + 5].col;
      if (temp_col < 0)
        temp_col -= 4;
      else
        temp_col += 4;
      cmv.col = (temp_col ~/ 8);

      if (full_pixel) {
        cmv.integer &= 0xFFF8FFF8;
      }
    }
  }
}

void build_mc_border(
  Uint8List dst,
  int dst_off,
  Uint8List src,
  int src_off,
  int stride,
  int x,
  int y,
  int b_w,
  int b_h,
  int w,
  int h,
) {
  int ref_row_off = src_off - x - y * stride;
  if (y >= h)
    ref_row_off += (h - 1) * stride;
  else if (y > 0)
    ref_row_off += y * stride;

  do {
    int left = (x < 0) ? -x : 0;
    if (left > b_w) left = b_w;
    int right = (x + b_w > w) ? (x + b_w - w) : 0;
    if (right > b_w) right = b_w;
    int copy = b_w - left - right;

    if (left > 0) dst.fillRange(dst_off, dst_off + left, src[ref_row_off]);
    if (copy > 0)
      dst.setRange(
        dst_off + left,
        dst_off + left + copy,
        src,
        ref_row_off + x + left,
      );
    if (right > 0)
      dst.fillRange(
        dst_off + left + copy,
        dst_off + left + copy + right,
        src[ref_row_off + w - 1],
      );

    dst_off += stride;
    y++;
    if (y < h && y > 0) ref_row_off += stride;
  } while (--b_h > 0);
}

void predict_inter(
  VP8D_COMP pbi,
  vpx_image_t img,
  Int32List coeffs,
  int coeffs_off,
  MODE_INFO mbi,
  int mb_col,
  int mb_row,
) {
  int y_off =
      img.planes_off[PLANE_Y] +
      (img.stride[PLANE_Y] * mb_row * 16) +
      (mb_col * 16);
  int u_off =
      img.planes_off[PLANE_U] +
      (img.stride[PLANE_U] * mb_row * 8) +
      (mb_col * 8);
  int v_off =
      img.planes_off[PLANE_V] +
      (img.stride[PLANE_V] * mb_row * 8) +
      (mb_col * 8);

  int ref_frame = mbi.mbmi.ref_frame;
  int reference_offset = pbi.ref_frame_offsets[ref_frame];
  Uint8List reference = img.img_data!;
  int stride = img.stride[PLANE_Y];
  int uv_stride = img.stride[PLANE_U];

  int mode = mbi.mbmi.y_mode;
  List<MotionVector>? mvs = mbi.bmi?.mvs;
  MotionVector mv = mbi.mbmi.mv;

  for (int b = 0; b < 16; b++) {
    MotionVector ymv = (mode != SPLITMV) ? mv : mvs![b];
    recon_1_block(
      img.img_data!,
      y_off,
      reference,
      y_off + reference_offset,
      stride,
      ymv,
      pbi.subpixel_filters,
      coeffs,
      coeffs_off,
      mbi,
      b,
    );
    y_off += 4;
    if ((b & 3) == 3) y_off += (stride << 2) - 16;
  }

  for (int b = 0; b < 4; b++) {
    recon_1_block(
      img.img_data!,
      u_off,
      reference,
      u_off + reference_offset,
      uv_stride,
      chroma_mv[b],
      pbi.subpixel_filters,
      coeffs,
      coeffs_off,
      mbi,
      b + 16,
    );
    recon_1_block(
      img.img_data!,
      v_off,
      reference,
      v_off + reference_offset,
      uv_stride,
      chroma_mv[b],
      pbi.subpixel_filters,
      coeffs,
      coeffs_off,
      mbi,
      b + 20,
    );
    u_off += 4;
    v_off += 4;
    if ((b & 1) == 1) {
      u_off += (uv_stride << 2) - 8;
      v_off += (uv_stride << 2) - 8;
    }
  }
}

void recon_1_block(
  Uint8List output,
  int output_off,
  Uint8List reference,
  int reference_off,
  int stride,
  MotionVector mv,
  List<FilterWithShape> filters,
  Int32List coeffs,
  int coeffs_off,
  MODE_INFO mbi,
  int b,
) {
  Uint8List predict = reference;
  int predict_off = reference_off;

  if (mv.integer != 0) {
    int mx = mv.row & 7; // Wait, row/col mapping might be different in JS
    int my = mv.col & 7;
    int ref_off = reference_off + ((mv.col >> 3) * stride) + (mv.row >> 3);
    filter_block2d(
      output,
      output_off,
      stride,
      reference,
      ref_off,
      stride,
      4,
      4,
      mx,
      my,
      filters,
    );
    predict = output;
    predict_off = output_off;
  }

  vp8_short_idct4x4llm_c(
    output,
    output_off,
    predict,
    predict_off,
    stride,
    coeffs,
    coeffs_off + 16 * b,
  );
}

void recon_1_edge_block(
  Uint8List output,
  int output_off,
  Uint8List emul_block,
  int emul_block_off,
  Uint8List reference,
  int reference_off,
  int stride,
  MotionVector mv,
  List<FilterWithShape> filters,
  Int32List coeffs,
  int coeffs_off,
  MODE_INFO mbi,
  int x,
  int y,
  int w,
  int h,
  int b,
) {
  int x_ref = x + (mv.row >> 3);
  int y_ref = y + (mv.col >> 3);

  Uint8List current_ref = reference;
  int current_ref_off = reference_off;

  if (x_ref < 2 || x_ref + 3 >= w || y_ref < 2 || y_ref + 3 >= h) {
    int ref_off = reference_off + (mv.row >> 3) + (mv.col >> 3) * stride;
    build_mc_border(
      emul_block,
      emul_block_off,
      reference,
      ref_off - 2 - (stride << 1),
      stride,
      x_ref - 2,
      y_ref - 2,
      9,
      9,
      w,
      h,
    );
    current_ref = emul_block;
    current_ref_off = emul_block_off + (stride << 1) + 2;
    current_ref_off -= (mv.row >> 3) + (mv.col >> 3) * stride;
  }

  recon_1_block(
    output,
    output_off,
    current_ref,
    current_ref_off,
    stride,
    mv,
    filters,
    coeffs,
    coeffs_off,
    mbi,
    b,
  );
}

void vp8_build_inter16x16_predictors_mb(MODE_INFO mbi, bool full_pixel) {
  MotionVector uvmv = MotionVector();
  uvmv.integer = mbi.mbmi.mv.integer;

  int x = uvmv.row;
  int y = uvmv.col;
  uvmv.row = (x + 1 + ((x >> 31) << 1)) ~/ 2;
  uvmv.col = (y + 1 + ((y >> 31) << 1)) ~/ 2;

  if (full_pixel) {
    uvmv.integer &= 0xFFF8FFF8;
  }

  for (int i = 0; i < 4; i++) {
    chroma_mv[i].integer = uvmv.integer;
  }
}

void vp8_build_inter_predictors_mb(
  VP8D_COMP pbi,
  vpx_image_t img,
  Int32List coeffs,
  int coeffs_off,
  MODE_INFO mbi,
  int mb_col,
  int mb_row,
) {
  bool full_pixel = (pbi.common.version == 3);

  if (mbi.mbmi.y_mode != SPLITMV) {
    vp8_short_inv_walsh4x4_c(coeffs, coeffs_off + 384, coeffs_off);
    vp8_build_inter16x16_predictors_mb(mbi, full_pixel);
  } else {
    build_4x4uvmvs(mbi, full_pixel);
  }

  if (mbi.mbmi.need_mc_border == 1) {
    predict_inter_emulated_edge(
      pbi,
      img,
      coeffs,
      coeffs_off,
      mbi,
      mb_col,
      mb_row,
    );
  } else {
    predict_inter(pbi, img, coeffs, coeffs_off, mbi, mb_col, mb_row);
  }
}
