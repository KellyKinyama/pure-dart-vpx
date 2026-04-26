import 'dart:typed_data';
import 'onyxc_int.dart';

const int DC_PRED = 0;
const int V_PRED = 1;
const int H_PRED = 2; /* horizontal prediction */
const int TM_PRED = 3; /* Truemotion prediction */
const int B_PRED = 4; /* block based prediction, each block has its own prediction mode */
const int NEARESTMV = 5;
const int NEARMV = 6;
const int ZEROMV = 7;
const int NEWMV = 8;
const int SPLITMV = 9;
const int MB_MODE_COUNT = 10;

const int B_DC_PRED = 0; /* average of above and left pixels */
const int B_TM_PRED = 1;
const int B_VE_PRED = 2; /* vertical prediction */
const int B_HE_PRED = 3; /* horizontal prediction */

const int B_LD_PRED = 4;
const int B_RD_PRED = 5;
const int B_VR_PRED = 6;
const int B_VL_PRED = 7;
const int B_HD_PRED = 8;
const int B_HU_PRED = 9;
const int LEFT4X4 = 10;
const int ABOVE4X4 = 11;
const int ZERO4X4 = 12;
const int NEW4X4 = 13;
const int B_MODE_COUNT = 14;

// b_mode_tree in dixie version
final Int32List vp8_bmode_tree = Int32List.fromList([
  -B_DC_PRED, 2, /* 0 = DC_NODE */
  -B_TM_PRED, 4, /* 1 = TM_NODE */
  -B_VE_PRED, 6, /* 2 = VE_NODE */
  8, 12, /* 3 = COM_NODE */
  -B_HE_PRED, 10, /* 4 = HE_NODE */
  -B_RD_PRED, -B_VR_PRED, /* 5 = RD_NODE */
  -B_LD_PRED, 14, /* 6 = LD_NODE */
  -B_VL_PRED, 16, /* 7 = VL_NODE */
  -B_HD_PRED, -B_HU_PRED /* 8 = HD_NODE */
]);

// kf_y_mode_tree in dixie version
final Int32List vp8_kf_ymode_tree = Int32List.fromList([
  -B_PRED, 2,
  4, 6,
  -DC_PRED, -V_PRED,
  -H_PRED, -TM_PRED
]);

final Int32List vp8_ymode_tree = Int32List.fromList([
  -DC_PRED, 2,
  4, 6,
  -V_PRED, -H_PRED,
  -TM_PRED, -B_PRED
]);

final Int32List vp8_uv_mode_tree = Int32List.fromList([
  -DC_PRED, 2,
  -V_PRED, 4,
  -H_PRED, -TM_PRED
]);

final Int32List vp8_mv_ref_tree = Int32List.fromList([
  -ZEROMV, 2,
  -NEARESTMV, 4,
  -NEARMV, 6,
  -NEWMV, -SPLITMV
]);

final Int32List vp8_sub_mv_ref_tree = Int32List.fromList([
  -LEFT4X4, 2,
  -ABOVE4X4, 4,
  -ZERO4X4, -NEW4X4
]);

final Int32List vp8_small_mvtree = Int32List.fromList([
  2, 8,
  4, 6,
  -0, -1,
  -2, -3,
  10, 12,
  -4, -5,
  -6, -7
]);

final Int32List vp8_mbsplit_tree = Int32List.fromList([
  -3, 2,
  -2, 4,
  -0, -1
]);

final List<Int32List> vp8_mbsplits = [
  Int32List.fromList([0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1]),
  Int32List.fromList([0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1]),
  Int32List.fromList([0, 0, 1, 1, 0, 0, 1, 1, 2, 2, 3, 3, 2, 2, 3, 3]),
  Int32List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
];

final List<Int32List> vp8_sub_mv_ref_prob2 = [
  Int32List.fromList([147, 136, 18]),
  Int32List.fromList([106, 145, 1]),
  Int32List.fromList([179, 121, 1]),
  Int32List.fromList([223, 1, 34]),
  Int32List.fromList([208, 1, 1])
];

// vp8_mbsplit_probs
final Uint8List vp8_mbsplit_probs = Uint8List.fromList([110, 111, 150]);

// k_default_y_mode_probs
final Uint8List vp8_ymode_prob = Uint8List.fromList([112, 86, 140, 37]);

// k_default_uv_mode_probs
final Uint8List vp8_uv_mode_prob = Uint8List.fromList([162, 101, 204]);

// kf_uv_mode_probs
final Uint8List vp8_kf_uv_mode_prob = Uint8List.fromList([142, 114, 183]);

// kf_y_mode_probs
final Uint8List vp8_kf_ymode_prob = Uint8List.fromList([145, 156, 163, 128]);

// default_b_mode_probs
final Uint8List vp8_bmode_prob = Uint8List.fromList([120, 90, 79, 133, 87, 85, 80, 111, 151]);

void vp8_init_mbmode_probs(VP8_COMMON pc) {
  pc.entropy_hdr.y_mode_probs.setRange(0, 4, vp8_ymode_prob);
  pc.entropy_hdr.uv_mode_probs.setRange(0, 3, vp8_uv_mode_prob);
}