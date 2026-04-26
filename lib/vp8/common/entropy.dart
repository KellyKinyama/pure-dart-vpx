import 'default_coef_probs.dart';
import 'onyxc_int.dart';

void vp8_default_coef_probs(VP8_COMMON pc) {
  pc.entropy_hdr.coeff_probs.setRange(0, default_coef_probs.length, default_coef_probs);
}