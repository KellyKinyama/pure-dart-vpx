import 'dart:typed_data';
import 'vpx_image.dart';

enum vpx_codec_err_t {
  VPX_CODEC_OK,
  VPX_CODEC_ERROR,
  VPX_CODEC_MEM_ERROR,
  VPX_CODEC_ABI_MISMATCH,
  VPX_CODEC_INCAPABLE,
  VPX_CODEC_UNSUP_BITSTREAM,
  VPX_CODEC_UNSUP_FEATURE,
  VPX_CODEC_CORRUPT_FRAME,
  VPX_CODEC_INVALID_PARAM,
  VPX_CODEC_LIST_END
}

class vpx_codec_dec_cfg {
  int threads = 0;
  int w = 0;
  int h = 0;
}

typedef vpx_codec_init_fn_t = int Function(vpx_codec_ctx_t ctx, dynamic? priv);
typedef vpx_codec_decode_fn_t = int Function(dynamic? priv, Uint8List data, int data_sz, dynamic? user_priv, int deadline);
typedef vpx_codec_get_frame_fn_t = vpx_image_t? Function(dynamic? priv, Iterator iter);

class vpx_codec_iface_t {
  final String name;
  final vpx_codec_init_fn_t? init;
  final vpx_codec_decode_fn_t? decode;
  final vpx_codec_get_frame_fn_t? get_frame;

  vpx_codec_iface_t({
    required this.name,
    this.init,
    this.decode,
    this.get_frame,
  });
}

class vpx_codec_ctx_t {
  String? name;
  vpx_codec_iface_t? iface;
  vpx_codec_err_t err = vpx_codec_err_t.VPX_CODEC_OK;
  String? err_detail;
  int init_flags = 0;
  vpx_codec_dec_cfg? config_dec;
  dynamic? priv;
}