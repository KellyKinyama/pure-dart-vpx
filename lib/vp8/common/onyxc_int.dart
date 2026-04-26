import 'dart:typed_data';

const int MV_PROB_CNT = 19;

class FRAME_CONTEXT {
  late final Uint8List coeff_probs;
  late final List<Uint8List> mv_probs;
  
  int coeff_skip_enabled = 0;
  int coeff_skip_prob = 0;
  late final Uint8List y_mode_probs;
  late final Uint8List uv_mode_probs;
  
  int prob_inter = 0;
  int prob_last = 0;
  int prob_gf = 0;

  FRAME_CONTEXT() {
    coeff_probs = Uint8List(1056);
    mv_probs = [
      Uint8List(MV_PROB_CNT),
      Uint8List(MV_PROB_CNT)
    ];
    y_mode_probs = Uint8List(4);
    uv_mode_probs = Uint8List(3);
  }
}

const int RECON_CLAMP_NOTREQUIRED = 0;
const int RECON_CLAMP_REQUIRED = 1;

const int NORMAL_LOOPFILTER = 0;
const int SIMPLE_LOOPFILTER = 1;

const int NUM_YV12_BUFFERS = 4;

class VP8_COMMON {
  int Width = 0;
  int Height = 0;
  int horiz_scale = 0;
  int vert_scale = 0;

  int mb_cols = 0;
  int mb_rows = 0;

  bool is_key_frame = false;
  int show_frame = 0;
  int version = 0;

  int mbmi_qindex = 0;
  int delta_update = 0;
  int y1dc_delta_q = 0;
  int y2dc_delta_q = 0;
  int y2ac_delta_q = 0;
  int uvdc_delta_q = 0;
  int uvac_delta_q = 0;

  bool refresh_gf = false;
  bool refresh_arf = false;
  int copy_gf = 0;
  int copy_arf = 0;
  final List<int> sign_bias = List.filled(4, 0);
  int refresh_entropy_probs = 0;
  int refresh_last_frame = 0;

  int filter_type = 0;
  int level = 0;
  int sharpness = 0;
  bool delta_enabled = false;
  final Int32List ref_delta = Int32List(4);
  final Int32List mode_delta = Int32List(4);

  int mode_info_stride = 0;

  late FRAME_CONTEXT entropy_hdr;
  int frame_size_updated = 0;

  VP8_COMMON() {
    entropy_hdr = FRAME_CONTEXT();
  }
}