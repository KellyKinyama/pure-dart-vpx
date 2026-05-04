import 'dart:typed_data';
import 'mv.dart';

// left_context_index
final Uint8List vp8_block2left = Uint8List.fromList([
  0,
  0,
  0,
  0,
  1,
  1,
  1,
  1,
  2,
  2,
  2,
  2,
  3,
  3,
  3,
  3,
  4,
  4,
  5,
  5,
  6,
  6,
  7,
  7,
  8,
]);

// above_context_index
final Uint8List vp8_block2above = Uint8List.fromList([
  0,
  1,
  2,
  3,
  0,
  1,
  2,
  3,
  0,
  1,
  2,
  3,
  0,
  1,
  2,
  3,
  4,
  5,
  4,
  5,
  6,
  7,
  6,
  7,
  8,
]);

const int MAX_PARTITIONS = 8;

// NOTE: The real `FRAGMENT_DATA` (libvpx `vp8/decoder/onyxd_int.h`) lives in
// `decoder/onyxd_int.dart` with a typed back-pointer to `VP8D_COMP`. The stub
// that used to live here held a `dynamic decoder` and was unused (decodeframe
// imports this file with `hide FRAGMENT_DATA`).

class MB_MODE_INFO {
  int y_mode = 0;
  int uv_mode = 0;
  int ref_frame = 0;
  int is_4x4 = 0;
  final MotionVector mv = MotionVector();
  int partitioning = 0;
  int mb_skip_coeff = 0;
  int need_mc_border = 0;
  int segment_id = 0;
  int eob_mask = 0;
}

class BMI {
  late final List<MotionVector> mvs;
  late final Uint8List modes;

  BMI() {
    mvs = List.generate(16, (_) => MotionVector());
    modes = Uint8List(16);
  }
}

/*
 * likely MB_MODE_INFO
 */
class MODE_INFO {
  final MB_MODE_INFO mbmi = MB_MODE_INFO();
  BMI? bmi;

  void init_split_mode() {
    bmi = BMI();
  }
}

/// libvpx `MACROBLOCKD` (vp8/common/blockd.h). The real C struct holds a
/// pointer to its enclosing `VP8D_COMP`; in this port the field is unused, so
/// the typed back-pointer is omitted to avoid a `blockd <-> onyxd_int` import
/// cycle. Reintroduce as `final VP8D_COMP decoder;` if needed.
class MACROBLOCKD {
  int enabled = 0;
  int update_data = 0;
  int update_map = 0;
  int abs = 0;
  final Uint32List tree_probs = Uint32List(3);
  final Int32List lf_level = Int32List(4);
  final Int32List quant_idx = Int32List(4);

  MACROBLOCKD();

  Float64List get lf_level_64 => lf_level.buffer.asFloat64List();
  Float64List get quant_idx_64 => quant_idx.buffer.asFloat64List();
}
