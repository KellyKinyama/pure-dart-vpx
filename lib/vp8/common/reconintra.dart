import 'dart:typed_data';
import 'idctllm.dart';
import 'blockd.dart';
import 'reconintra4x4.dart';

const int DC_PRED = 0;
const int V_PRED = 1;
const int H_PRED = 2;
const int TM_PRED = 3;
const int B_PRED = 4;

const int B_DC_PRED = 0;
const int B_TM_PRED = 1;
const int B_VE_PRED = 2;
const int B_HE_PRED = 3;
const int B_LD_PRED = 4;
const int B_RD_PRED = 5;
const int B_VR_PRED = 6;
const int B_VL_PRED = 7;
const int B_HD_PRED = 8;
const int B_HU_PRED = 9;

int CLAMP_255(int x) => x.clamp(0, 255);

void predict_intra_chroma(Uint8List predict_u, int predict_u_off, Uint8List predict_v, int predict_v_off, int stride, MODE_INFO mbi, Int32List coeffs, int coeffs_off) {
  switch (mbi.mbmi.uv_mode) {
    case DC_PRED:
      predict_dc_nxn(predict_u, predict_u_off, stride, 8);
      predict_dc_nxn(predict_v, predict_v_off, stride, 8);
      break;
    case V_PRED:
      predict_v_nxn(predict_u, predict_u_off, stride, 8);
      predict_v_nxn(predict_v, predict_v_off, stride, 8);
      break;
    case H_PRED:
      predict_h_nxn(predict_u, predict_u_off, stride, 8);
      predict_h_nxn(predict_v, predict_v_off, stride, 8);
      break;
    case TM_PRED:
      predict_tm_nxn(predict_u, predict_u_off, stride, 8);
      predict_tm_nxn(predict_v, predict_v_off, stride, 8);
      break;
  }

  int local_coeffs_off = coeffs_off + 256;
  int stride4_8 = stride * 4 - 8;

  for (int i = 16; i < 20; i++) {
    vp8_short_idct4x4llm_c(predict_u, predict_u_off, predict_u, predict_u_off, stride, coeffs, local_coeffs_off);
    local_coeffs_off += 16;
    predict_u_off += 4;
    if ((i & 1) != 0) predict_u_off += stride4_8;
  }

  for (int i = 20; i < 24; i++) {
    vp8_short_idct4x4llm_c(predict_v, predict_v_off, predict_v, predict_v_off, stride, coeffs, local_coeffs_off);
    local_coeffs_off += 16;
    predict_v_off += 4;
    if ((i & 1) != 0) predict_v_off += stride4_8;
  }
}

void predict_v_nxn(Uint8List predict, int predict_off, int stride, int n) {
  int above_off = predict_off - stride;
  for (int i = 0; i < n; i++) {
    int istride = i * stride;
    for (int j = 0; j < n; j++) {
      predict[predict_off + istride + j] = predict[above_off + j];
    }
  }
}

void predict_h_nxn(Uint8List predict, int predict_off, int stride, int n) {
  int left_off = predict_off - 1;
  for (int i = 0; i < n; i++) {
    int istride = i * stride;
    int pixel = predict[left_off + i * stride];
    for (int j = 0; j < n; j++) {
      predict[predict_off + istride + j] = pixel;
    }
  }
}

void predict_dc_nxn(Uint8List predict, int predict_off, int stride, int n) {
  int left_off = predict_off - 1;
  int above_off = predict_off - stride;
  int dc = 0;

  for (int i = 0; i < n; i++) {
    dc += predict[left_off] + predict[above_off + i];
    left_off += stride;
  }

  if (n == 16) dc = (dc + 16) >> 5;
  else if (n == 8) dc = (dc + 8) >> 4;
  else if (n == 4) dc = (dc + 4) >> 3;

  for (int i = 0; i < n; i++) {
    for (int j = 0; j < n; j++) {
      predict[predict_off + i * stride + j] = dc;
    }
  }
}

void predict_tm_nxn(Uint8List predict, int predict_off, int stride, int n) {
  int left_off = predict_off - 1;
  int above_off = predict_off - stride;
  int top_left = predict[above_off - 1];

  for (int j = 0; j < n; j++) {
    for (int i = 0; i < n; i++) {
      predict[predict_off + i] = CLAMP_255(predict[left_off] + predict[above_off + i] - top_left);
    }
    predict_off += stride;
    left_off += stride;
  }
}

void predict_intra_luma(Uint8List predict, int predict_off, int stride, MODE_INFO mbi, Int32List coeffs, int coeffs_off) {
  if (mbi.mbmi.y_mode == B_PRED) {
    b_pred(predict, predict_off, stride, mbi, coeffs, coeffs_off);
  } else {
    switch (mbi.mbmi.y_mode) {
      case DC_PRED:
        predict_dc_nxn(predict, predict_off, stride, 16);
        break;
      case V_PRED:
        predict_v_nxn(predict, predict_off, stride, 16);
        break;
      case H_PRED:
        predict_h_nxn(predict, predict_off, stride, 16);
        break;
      case TM_PRED:
        predict_tm_nxn(predict, predict_off, stride, 16);
        break;
    }

    vp8_short_inv_walsh4x4_c(coeffs, coeffs_off + 384, coeffs_off);

    int local_predict_off = predict_off;
    int local_coeffs_off = coeffs_off;
    for (int i = 0; i < 16; i++) {
      vp8_short_idct4x4llm_c(predict, local_predict_off, predict, local_predict_off, stride, coeffs, local_coeffs_off);
      local_coeffs_off += 16;
      local_predict_off += 4;
      if ((i & 3) == 3) local_predict_off += (stride << 2) - 16;
    }
  }
}

void b_pred(Uint8List predict, int predict_off, int stride, MODE_INFO mbi, Int32List coeffs, int coeffs_off) {
  intra_prediction_down_copy(predict, predict_off, stride);
  List<int> modes = mbi.bmi!.modes;
  int local_coeffs_off = coeffs_off;

  for (int i = 0; i < 16; i++) {
    int b_predict_off = predict_off + ((i & 3) << 2) + ((i >> 2) * stride << 2); 
    // Wait, row calculation: (i >> 2) * stride * 4
    
    switch (modes[i]) {
      case B_DC_PRED: predict_dc_nxn(predict, b_predict_off, stride, 4); break;
      case B_TM_PRED: predict_tm_nxn(predict, b_predict_off, stride, 4); break;
      case B_VE_PRED: predict_ve_4x4(predict, b_predict_off, stride); break;
      case B_HE_PRED: predict_he_4x4(predict, b_predict_off, stride); break;
      case B_LD_PRED: predict_ld_4x4(predict, b_predict_off, stride); break;
      case B_RD_PRED: predict_rd_4x4(predict, b_predict_off, stride); break;
      case B_VR_PRED: predict_vr_4x4(predict, b_predict_off, stride); break;
      case B_VL_PRED: predict_vl_4x4(predict, b_predict_off, stride); break;
      case B_HD_PRED: predict_hd_4x4(predict, b_predict_off, stride); break;
      case B_HU_PRED: predict_hu_4x4(predict, b_predict_off, stride); break;
    }

    vp8_short_idct4x4llm_c(predict, b_predict_off, predict, b_predict_off, stride, coeffs, local_coeffs_off);
    local_coeffs_off += 16;
  }
}

void predict_ve_4x4(Uint8List predict, int predict_off, int stride) {
  int above_off = predict_off - stride;
  int a_m1 = predict[above_off - 1];
  int a0 = predict[above_off];
  int a1 = predict[above_off + 1];
  int a2 = predict[above_off + 2];
  int a3 = predict[above_off + 3];
  int a4 = predict[above_off + 4];

  int p1 = (a_m1 + (a0 << 1) + a1 + 2) >> 2;
  int p2 = (a0 + (a1 << 1) + a2 + 2) >> 2;
  int p3 = (a1 + (a2 << 1) + a3 + 2) >> 2;
  int p4 = (a2 + (a3 << 1) + a4 + 2) >> 2;

  predict[predict_off] = p1;
  predict[predict_off + 1] = p2;
  predict[predict_off + 2] = p3;
  predict[predict_off + 3] = p4;

  for (int i = 1; i < 4; i++) {
    int istride = i * stride;
    for (int j = 0; j < 4; j++) {
      predict[predict_off + istride + j] = predict[predict_off + j];
    }
  }
}

void predict_he_4x4(Uint8List predict, int predict_off, int stride) {
  int p_off = predict_off;
  int left_off = predict_off - 1;
  for (int i = 0; i < 4; i++) {
    int l_prev = predict[left_off - stride];
    int l0 = predict[left_off];
    int l_next = (i < 3) ? predict[left_off + stride] : l0;
    int temp = (l_prev + 2 * l0 + l_next + 2) >> 2;
    predict[p_off] = predict[p_off + 1] = predict[p_off + 2] = predict[p_off + 3] = temp;
    p_off += stride;
    left_off += stride;
  }
}

void predict_hd_4x4(Uint8List predict, int predict_off, int stride) {
  int above_off = predict_off - stride;
  int left_off = predict_off - 1;
  int am1 = predict[above_off - 1];
  int a0 = predict[above_off], a1 = predict[above_off + 1], a2 = predict[above_off + 2];
  int l0 = predict[left_off], l1 = predict[left_off + stride], l2 = predict[left_off + stride * 2], l3 = predict[left_off + stride * 3];

  int p0 = (l0 + am1 + 1) >> 1;
  int p1 = (l0 + 2 * am1 + a0 + 2) >> 2;
  int p2 = (am1 + 2 * a0 + a1 + 2) >> 2;
  int p3 = (a0 + 2 * a1 + a2 + 2) >> 2;
  predict[predict_off] = p0; predict[predict_off + 1] = p1; predict[predict_off + 2] = p2; predict[predict_off + 3] = p3;

  int p4 = (l1 + l0 + 1) >> 1;
  int p5 = (l1 + 2 * l0 + am1 + 2) >> 2;
  predict[predict_off + stride] = p4; predict[predict_off + stride + 1] = p5; predict[predict_off + stride + 2] = p0; predict[predict_off + stride + 3] = p1;

  int p6 = (l2 + l1 + 1) >> 1;
  int p7 = (l2 + 2 * l1 + l0 + 2) >> 2;
  predict[predict_off + stride * 2] = p6; predict[predict_off + stride * 2 + 1] = p7; predict[predict_off + stride * 2 + 2] = p4; predict[predict_off + stride * 2 + 3] = p5;

  int p8 = (l3 + l2 + 1) >> 1;
  int p9 = (l3 + 2 * l2 + l1 + 2) >> 2;
  predict[predict_off + stride * 3] = p8; predict[predict_off + stride * 3 + 1] = p9; predict[predict_off + stride * 3 + 2] = p6; predict[predict_off + stride * 3 + 3] = p7;
}

void predict_vr_4x4(Uint8List predict, int predict_off, int stride) {
  int above_off = predict_off - stride;
  int left_off = predict_off - 1;
  int am1 = predict[above_off - 1];
  int a0 = predict[above_off], a1 = predict[above_off + 1], a2 = predict[above_off + 2], a3 = predict[above_off + 3], a4 = predict[above_off + 4];
  int l0 = predict[left_off], l1 = predict[left_off + stride], l2 = predict[left_off + stride * 2];

  int p0 = (am1 + a0 + 1) >> 1;
  int p1 = (a0 + a1 + 1) >> 1;
  int p2 = (a1 + a2 + 1) >> 1;
  int p3 = (a2 + a3 + 1) >> 1;
  predict[predict_off] = p0; predict[predict_off + 1] = p1; predict[predict_off + 2] = p2; predict[predict_off + 3] = p3;

  int p4 = (l0 + 2 * am1 + a0 + 2) >> 2;
  int p5 = (am1 + 2 * a0 + a1 + 2) >> 2;
  int p6 = (a0 + 2 * a1 + a2 + 2) >> 2;
  int p7 = (a1 + 2 * a2 + a3 + 2) >> 2;
  predict[predict_off + stride] = p4; predict[predict_off + stride + 1] = p5; predict[predict_off + stride + 2] = p6; predict[predict_off + stride + 3] = p7;

  int p8 = (l1 + 2 * l0 + am1 + 2) >> 2;
  predict[predict_off + stride * 2] = p8; predict[predict_off + stride * 2 + 1] = p0; predict[predict_off + stride * 2 + 2] = p1; predict[predict_off + stride * 2 + 3] = p2;

  int p9 = (l2 + 2 * l1 + l0 + 2) >> 2;
  predict[predict_off + stride * 3] = p9; predict[predict_off + stride * 3 + 1] = p4; predict[predict_off + stride * 3 + 2] = p5; predict[predict_off + stride * 3 + 3] = p6;
}

void predict_rd_4x4(Uint8List predict, int predict_off, int stride) {
  int above_off = predict_off - stride;
  int left_off = predict_off - 1;
  int am1 = predict[above_off - 1];
  int a0 = predict[above_off], a1 = predict[above_off + 1], a2 = predict[above_off + 2], a3 = predict[above_off + 3];
  int l0 = predict[left_off], l1 = predict[left_off + stride], l2 = predict[left_off + stride * 2], l3 = predict[left_off + stride * 3];

  int p0 = (l0 + 2 * am1 + a0 + 2) >> 2;
  int p1 = (am1 + 2 * a0 + a1 + 2) >> 2;
  int p2 = (a0 + 2 * a1 + a2 + 2) >> 2;
  int p3 = (a1 + 2 * a2 + a3 + 2) >> 2;
  predict[predict_off] = p0; predict[predict_off + 1] = p1; predict[predict_off + 2] = p2; predict[predict_off + 3] = p3;

  int p4 = (l1 + 2 * l0 + am1 + 2) >> 2;
  predict[predict_off + stride] = p4; predict[predict_off + stride + 1] = p0; predict[predict_off + stride + 2] = p1; predict[predict_off + stride + 3] = p2;

  int p5 = (l2 + 2 * l1 + l0 + 2) >> 2;
  predict[predict_off + stride * 2] = p5; predict[predict_off + stride * 2 + 1] = p4; predict[predict_off + stride * 2 + 2] = p0; predict[predict_off + stride * 2 + 3] = p1;

  int p6 = (l3 + 2 * l2 + l1 + 2) >> 2;
  predict[predict_off + stride * 3] = p6; predict[predict_off + stride * 3 + 1] = p5; predict[predict_off + stride * 3 + 2] = p4; predict[predict_off + stride * 3 + 3] = p0;
}

void predict_ld_4x4(Uint8List predict, int predict_off, int stride) {
  int above_off = predict_off - stride;
  int a0 = predict[above_off], a1 = predict[above_off + 1], a2 = predict[above_off + 2], a3 = predict[above_off + 3], a4 = predict[above_off + 4], a5 = predict[above_off + 5], a6 = predict[above_off + 6], a7 = predict[above_off + 7];

  predict[predict_off] = (a0 + 2 * a1 + a2 + 2) >> 2;
  predict[predict_off + 1] = (a1 + 2 * a2 + a3 + 2) >> 2;
  predict[predict_off + 2] = (a2 + 2 * a3 + a4 + 2) >> 2;
  predict[predict_off + 3] = (a3 + 2 * a4 + a5 + 2) >> 2;

  predict[predict_off + stride] = (a1 + 2 * a2 + a3 + 2) >> 2;
  predict[predict_off + stride + 1] = (a2 + 2 * a3 + a4 + 2) >> 2;
  predict[predict_off + stride + 2] = (a3 + 2 * a4 + a5 + 2) >> 2;
  predict[predict_off + stride + 3] = (a4 + 2 * a5 + a6 + 2) >> 2;

  predict[predict_off + stride * 2] = (a2 + 2 * a3 + a4 + 2) >> 2;
  predict[predict_off + stride * 2 + 1] = (a3 + 2 * a4 + a5 + 2) >> 2;
  predict[predict_off + stride * 2 + 2] = (a4 + 2 * a5 + a6 + 2) >> 2;
  predict[predict_off + stride * 2 + 3] = (a5 + 2 * a6 + a7 + 2) >> 2;

  predict[predict_off + stride * 3] = (a3 + 2 * a4 + a5 + 2) >> 2;
  predict[predict_off + stride * 3 + 1] = (a4 + 2 * a5 + a6 + 2) >> 2;
  predict[predict_off + stride * 3 + 2] = (a5 + 2 * a6 + a7 + 2) >> 2;
  predict[predict_off + stride * 3 + 3] = (a6 + 2 * a7 + a7 + 2) >> 2;
}

void predict_vl_4x4(Uint8List predict, int predict_off, int stride) {
  int above_off = predict_off - stride;
  int a0 = predict[above_off], a1 = predict[above_off + 1], a2 = predict[above_off + 2], a3 = predict[above_off + 3], a4 = predict[above_off + 4], a5 = predict[above_off + 5], a6 = predict[above_off + 6], a7 = predict[above_off + 7];

  int p0 = (a0 + a1 + 1) >> 1;
  int p1 = (a1 + a2 + 1) >> 1;
  int p2 = (a2 + a3 + 1) >> 1;
  int p3 = (a3 + a4 + 1) >> 1;
  predict[predict_off] = p0; predict[predict_off + 1] = p1; predict[predict_off + 2] = p2; predict[predict_off + 3] = p3;

  int p4 = (a0 + 2 * a1 + a2 + 2) >> 2;
  int p5 = (a1 + 2 * a2 + a3 + 2) >> 2;
  int p6 = (a2 + 2 * a3 + a4 + 2) >> 2;
  int p7 = (a3 + 2 * a4 + a5 + 2) >> 2;
  predict[predict_off + stride] = p4; predict[predict_off + stride + 1] = p5; predict[predict_off + stride + 2] = p6; predict[predict_off + stride + 3] = p7;

  int p8 = (a4 + 2 * a5 + a6 + 2) >> 2;
  predict[predict_off + stride * 2] = p1; predict[predict_off + stride * 2 + 1] = p2; predict[predict_off + stride * 2 + 2] = p3; predict[predict_off + stride * 2 + 3] = p8;

  int p9 = (a5 + 2 * a6 + a7 + 2) >> 2;
  predict[predict_off + stride * 3] = p5; predict[predict_off + stride * 3 + 1] = p6; predict[predict_off + stride * 3 + 2] = p7; predict[predict_off + stride * 3 + 3] = p9;
}

void predict_hu_4x4(Uint8List predict, int predict_off, int stride) {
  int left_off = predict_off - 1;
  int l0 = predict[left_off], l1 = predict[left_off + stride], l2 = predict[left_off + stride * 2], l3 = predict[left_off + stride * 3];

  int p0 = (l0 + l1 + 1) >> 1;
  int p1 = (l0 + 2 * l1 + l2 + 2) >> 2;
  int p2 = (l1 + l2 + 1) >> 1;
  int p3 = (l1 + 2 * l2 + l3 + 2) >> 2;
  predict[predict_off] = p0; predict[predict_off + 1] = p1; predict[predict_off + 2] = p2; predict[predict_off + 3] = p3;

  int p4 = (l2 + l3 + 1) >> 1;
  int p5 = (l2 + 2 * l3 + l3 + 2) >> 2;
  predict[predict_off + stride] = p2; predict[predict_off + stride + 1] = p3; predict[predict_off + stride + 2] = p4; predict[predict_off + stride + 3] = p5;

  predict[predict_off + stride * 2] = p4; predict[predict_off + stride * 2 + 1] = p5; predict[predict_off + stride * 2 + 2] = l3; predict[predict_off + stride * 2 + 3] = l3;

  predict[predict_off + stride * 3] = l3; predict[predict_off + stride * 3 + 1] = l3; predict[predict_off + stride * 3 + 2] = l3; predict[predict_off + stride * 3 + 3] = l3;
}
