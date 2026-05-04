import 'dart:typed_data';
import '../../util/c_utils.dart' as c_utils;
import '../../vpx/vpx_image.dart';

final memset = c_utils.memset;

/*
     if (start_col === 0) {
        //vp8_setup_intra_recon
        fixup_left(img.y, img.y_off, 16, img.stride, row, mbi[mbi_off].base.y_mode);
        fixup_left(img.u, img.u_off, 8, img.uv_stride, row, mbi[mbi_off].base.uv_mode);
        fixup_left(img.v, img.v_off, 8, img.uv_stride, row, mbi[mbi_off].base.uv_mode);

        //doesnt seem to do anything
        //if (row === 0)
        //  img.y[img.y_off - img.stride - 1]= 127;
        //console.warn(img.y_off - img.stride - 1);
    }
 */
//var dc_pred_set = new Uint8Array([129,129,129,129,129,129,129,129,129,129,129,129,129,129,129,129]);
// function vp8_setup_intra_recon(predict, y_off, u_off, v_off, y_stride, uv_stride) {
//The left column of out-of-frame pixels is taken to be 129,
// unless we're doing DC_PRED, in which case we duplicate the
// libvpx `vp8_setup_intra_recon` (vp8/common/setupintrarecon.c). Currently a
// no-op port; bodies remain commented out pending RFC 6386 §12 intra-recon.
void vp8_setup_intra_recon(
  Uint8List predict,
  int y_off,
  int u_off,
  int v_off,
  int y_stride,
  int uv_stride,
) {
  //The left column of out-of-frame pixels is taken to be 129,
  // unless we're doing DC_PRED, in which case we duplicate the
  // above row, unless this is also row 0, in which case we use
  // 129.
  //
  var y_buffer = predict;
  y_off = (y_off - 1);
  var i = 0;
  /* Need to re-set the above row, in case the above MB was
   * DC_PRED.
   */
  y_off -= y_stride;

  //for (i = -1; i < 16; i++) {
  //y_buffer[y_off] = 129;
  //y_buffer.set(dc_pred_set, y_off);
  //  y_off += y_stride;
  //}

  // var u_buffer = predict;
  // var u_off = (u_off - 1);

  // u_off -= uv_stride;

  // for (i = 0; i < 8; i++) {
  //     y_buffer[y_off] = 129;//*
  //     y_off += y_stride;
  // }

  // var u_buffer = predict;
  // var u_off = (u_off - 1);

  // u_off -= uv_stride;

  // for (i = -1; i < 8; i++) {
  //     u_buffer[u_off] = 129;
  //     u_off += uv_stride;
  // }
}

void vp8_setup_intra_recon_top_line(vpx_image_t ybf) {
  // libvpx accesses `ybf->u_buffer - 1 - ybf->uv_stride` and `ybf->y_width + 5`.
  // Translated to the typed `vpx_image_t` (libvpx `YV12_BUFFER_CONFIG`) the
  // chroma stride lives at `stride[VPX_PLANE_U]`. Body is a no-op for now.
  // ignore: unused_local_variable
  final data = ybf.img_data;
  // ignore: unused_local_variable
  final uv_ptr = ybf.planes_off[1] - 1 - ybf.stride[VPX_PLANE_U];
  // ignore: unused_local_variable
  final uv_length = (ybf.d_w >> 1) + 5;
  // memset(data!, ybf.planes_off[0] - 1 - ybf.stride[VPX_PLANE_Y], 127, ybf.d_w + 5);
  // memset(data!, uv_ptr, 127, uv_length);
}
// module.exports = {};
// module.exports.vp8_setup_intra_recon = vp8_setup_intra_recon;
// module.exports.vp8_setup_intra_recon_top_line = vp8_setup_intra_recon_top_line;// Dart exports are handled via `import`/`export` directives; these top-level
// functions are available to other libraries by importing this file.
    