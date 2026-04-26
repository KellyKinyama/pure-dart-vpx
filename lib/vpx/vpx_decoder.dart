import 'dart:typed_data';
import 'vpx_codec.dart';
import 'vpx_image.dart';

const int VPX_CODEC_ABI_VERSION = 1;
const int VPX_DECODER_ABI_VERSION = VPX_CODEC_ABI_VERSION + 3;

int vpx_codec_dec_init(vpx_codec_ctx_t ctx, vpx_codec_iface_t iface, vpx_codec_dec_cfg? cfg, int flags) {
  return vpx_codec_dec_init_ver(ctx, iface, cfg, flags, VPX_DECODER_ABI_VERSION);
}

int vpx_codec_dec_init_ver(vpx_codec_ctx_t ctx, vpx_codec_iface_t iface, vpx_codec_dec_cfg? cfg, int flags, int ver) {
  ctx.iface = iface;
  ctx.name = iface.name;
  ctx.priv = null;
  ctx.init_flags = flags;
  ctx.config_dec = cfg;

  if (iface.init != null) {
    return iface.init!(ctx, null);
  }
  return 0;
}

int vpx_codec_decode(vpx_codec_ctx_t ctx, Uint8List data, int data_sz, dynamic user_priv, int deadline) {
  if (ctx.iface?.decode != null) {
    return ctx.iface!.decode!(ctx.priv, data, data_sz, user_priv, deadline);
  }
  return -1;
}

vpx_image_t? vpx_codec_get_frame(vpx_codec_ctx_t ctx, Iterator iter) {
  if (ctx.iface?.get_frame != null) {
    return ctx.iface!.get_frame!(ctx.priv, iter);
  }
  return null;
}