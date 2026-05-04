import 'dart:typed_data';
import 'decoder/onyxd_int.dart';
import 'decoder/onyxd_if.dart';
import '../vpx/vpx_codec.dart';
import '../vpx/vpx_image.dart';

class vpx_codec_alg_priv extends VpxCodecAlgPriv {
  VP8D_COMP? temp_pbi;
  vpx_codec_alg_priv();
}

int vp8_init(vpx_codec_ctx_t ctx, VpxCodecPrivCfg? data) {
  final priv = vpx_codec_alg_priv();
  ctx.priv = priv;
  priv.temp_pbi = VP8D_COMP();
  return 0;
}

int vp8_decode(
  VpxCodecAlgPriv? priv,
  Uint8List data,
  int data_sz,
  VpxUserPriv? user_priv,
  int deadline,
) {
  if (priv is vpx_codec_alg_priv) {
    vp8dx_receive_compressed_data(priv.temp_pbi!, data_sz, data, deadline);
    return 0;
  }
  return -1;
}

vpx_image_t? vp8_get_frame(VpxCodecAlgPriv? priv, Iterator iter) {
  if (priv is vpx_codec_alg_priv) {
    if (priv.temp_pbi!.common.show_frame != 0) {
      return priv.temp_pbi!.frame_buffers[0].img;
    }
  }
  return null;
}

final vpx_codec_iface_t vpx_codec_vp8_pure_dart = vpx_codec_iface_t(
  name: "Pure Dart VP8 Decoder",
  init: vp8_init,
  decode: vp8_decode,
  get_frame: vp8_get_frame,
);
