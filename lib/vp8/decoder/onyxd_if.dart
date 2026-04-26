import 'dart:typed_data';
import 'decodeframe.dart';
import 'onyxd_int.dart';

const int CURRENT_FRAME = 0;
const int LAST_FRAME = 1;
const int GOLDEN_FRAME = 2;
const int ALTREF_FRAME = 3;

void vp8_dixie_release_ref_frame(RefCntImg? rcimg) {
  if (rcimg != null) {
    if (rcimg.ref_cnt == 0) throw "ERROR :(";
    rcimg.ref_cnt--;
  }
}

RefCntImg vp8_dixie_ref_frame(RefCntImg rcimg) {
  rcimg.ref_cnt++;
  return rcimg;
}

void vp8dx_receive_compressed_data(VP8D_COMP pbi, int size, Uint8List source, dynamic time_stamp) {
  vp8_decode_frame(source, pbi);
  swap_frame_buffers(pbi);
}

void swap_frame_buffers(VP8D_COMP cm) {
  final common = cm.common;
  
  if (common.copy_arf == 1) {
    vp8_dixie_release_ref_frame(cm.frame_buffers[ALTREF_FRAME]);
    cm.frame_buffers[ALTREF_FRAME] = vp8_dixie_ref_frame(cm.frame_buffers[LAST_FRAME]);
  } else if (common.copy_arf == 2) {
    vp8_dixie_release_ref_frame(cm.frame_buffers[ALTREF_FRAME]);
    cm.frame_buffers[ALTREF_FRAME] = vp8_dixie_ref_frame(cm.frame_buffers[GOLDEN_FRAME]);
  }

  if (common.copy_gf == 1) {
    vp8_dixie_release_ref_frame(cm.frame_buffers[GOLDEN_FRAME]);
    cm.frame_buffers[GOLDEN_FRAME] = vp8_dixie_ref_frame(cm.frame_buffers[LAST_FRAME]);
  } else if (common.copy_gf == 2) {
    vp8_dixie_release_ref_frame(cm.frame_buffers[GOLDEN_FRAME]);
    cm.frame_buffers[GOLDEN_FRAME] = vp8_dixie_ref_frame(cm.frame_buffers[ALTREF_FRAME]);
  }

  if (common.refresh_gf) {
    vp8_dixie_release_ref_frame(cm.frame_buffers[GOLDEN_FRAME]);
    cm.frame_buffers[GOLDEN_FRAME] = vp8_dixie_ref_frame(cm.frame_buffers[CURRENT_FRAME]);
  }

  if (common.refresh_arf) {
    vp8_dixie_release_ref_frame(cm.frame_buffers[ALTREF_FRAME]);
    cm.frame_buffers[ALTREF_FRAME] = vp8_dixie_ref_frame(cm.frame_buffers[CURRENT_FRAME]);
  }

  if (common.refresh_last_frame != 0) {
    vp8_dixie_release_ref_frame(cm.frame_buffers[LAST_FRAME]);
    cm.frame_buffers[LAST_FRAME] = vp8_dixie_ref_frame(cm.frame_buffers[CURRENT_FRAME]);
  }
}