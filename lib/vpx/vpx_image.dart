import 'dart:typed_data';

const int VPX_IMG_FMT_PLANAR = 0x100;
const int VPX_IMG_FMT_UV_FLIP = 0x200;
const int VPX_IMG_FMT_HAS_ALPHA = 0x400;

// Image format codes
const int VPX_IMG_FMT_NONE = 0;
const int VPX_IMG_FMT_RGB24 = 1;
const int VPX_IMG_FMT_RGB32 = 2;
const int VPX_IMG_FMT_RGB565 = 3;
const int VPX_IMG_FMT_RGB555 = 4;
const int VPX_IMG_FMT_UYVY = 5;
const int VPX_IMG_FMT_YUY2 = 6;
const int VPX_IMG_FMT_YVYU = 7;
const int VPX_IMG_FMT_BGR24 = 8;
const int VPX_IMG_FMT_RGB32_LE = 9;
const int VPX_IMG_FMT_ARGB = 10;
const int VPX_IMG_FMT_ARGB_LE = 11;
const int VPX_IMG_FMT_RGB565_LE = 12;
const int VPX_IMG_FMT_RGB555_LE = 13;
const int VPX_IMG_FMT_YV12 = VPX_IMG_FMT_PLANAR | VPX_IMG_FMT_UV_FLIP | 1;
const int VPX_IMG_FMT_I420 = VPX_IMG_FMT_PLANAR | 2;
const int VPX_IMG_FMT_VPXYV12 = VPX_IMG_FMT_PLANAR | VPX_IMG_FMT_UV_FLIP | 3;
const int VPX_IMG_FMT_VPXI420 = VPX_IMG_FMT_PLANAR | 4;

const int VPX_PLANE_PACKED = 0; /**< To be used for all packed formats */
const int VPX_PLANE_Y = 0; /**< Y (Luminance) plane */
const int VPX_PLANE_U = 1; /**< U (Chroma) plane */
const int VPX_PLANE_V = 2; /**< V (Chroma) plane */
const int VPX_PLANE_ALPHA = 3; /**< A (Transparency) plane */

const int PLANE_PACKED = VPX_PLANE_PACKED;
const int PLANE_Y = VPX_PLANE_Y;
const int PLANE_U = VPX_PLANE_U;
const int PLANE_V = VPX_PLANE_V;
const int PLANE_ALPHA = VPX_PLANE_ALPHA;

class vpx_image_t {
  int fmt = 0;

  /* Image storage dimensions */
  int w = 0;
  int h = 0;

  /* Image display dimensions */
  int d_w = 0;
  int d_h = 0;

  /* Chroma subsampling info */
  int x_chroma_shift = 0;
  int y_chroma_shift = 0;

  final Int32List planes_off = Int32List(4);
  final Int32List stride = Int32List(4);

  int bps = 0;
  int user_priv = 0;

  Uint8List? img_data;
  int img_data_off = 0;
  int img_data_owner = 0;
  int self_allocd = 0;

  // Helper getters for typed access if needed, though usually we use bitwise or other methods
  Uint32List? get img_data_32 => img_data?.buffer.asUint32List();
  Uint16List? get img_data_16 => img_data?.buffer.asUint16List();
}

int vpx_img_set_rect(vpx_image_t img, int x, int y, int w, int h) {
  int data_off = 0;

  if (x + w <= img.w && y + h <= img.h) {
    img.d_w = w;
    img.d_h = h;

    /* Calculate plane pointers */
    if ((img.fmt & VPX_IMG_FMT_PLANAR) == 0) {
      // In JS it was: img.img_data_off + (x * img.bps >> 3 + y * img.stride[VPX_PLANE_PACKED]) | 0;
      // But this line looked like a statement without assignment in the JS code original view.
      // Wait, let me check the JS code again.
    } else {
      data_off = img.img_data_off;

      if ((img.fmt & VPX_IMG_FMT_HAS_ALPHA) != 0) {
        img.planes_off[VPX_PLANE_ALPHA] = data_off + x + y * img.stride[VPX_PLANE_ALPHA];
        data_off += img.h * img.stride[VPX_PLANE_ALPHA];
      }

      img.planes_off[VPX_PLANE_Y] = data_off + x + y * img.stride[VPX_PLANE_Y];
      data_off += img.h * img.stride[VPX_PLANE_Y];

      if ((img.fmt & VPX_IMG_FMT_UV_FLIP) == 0) {
        img.planes_off[VPX_PLANE_U] = data_off +
            (x >> img.x_chroma_shift) +
            (y >> img.y_chroma_shift) * img.stride[VPX_PLANE_U];
        data_off += (img.h >> img.y_chroma_shift) * img.stride[VPX_PLANE_U];
        img.planes_off[VPX_PLANE_V] = data_off +
            (x >> img.x_chroma_shift) +
            (y >> img.y_chroma_shift) * img.stride[VPX_PLANE_V];
      } else {
        img.planes_off[VPX_PLANE_V] = data_off +
            (x >> img.x_chroma_shift) +
            (y >> img.y_chroma_shift) * img.stride[VPX_PLANE_V];
        data_off += (img.h >> img.y_chroma_shift) * img.stride[VPX_PLANE_V];
        img.planes_off[VPX_PLANE_U] = data_off +
            (x >> img.x_chroma_shift) +
            (y >> img.y_chroma_shift) * img.stride[VPX_PLANE_U];
      }
    }

    return 0;
  }

  return -1;
}

vpx_image_t? img_alloc_helper(vpx_image_t img, int fmt, int d_w, int d_h, int stride_align, Uint8List? img_data) {
  int h = 0;
  int w = 0;
  int s = 0;
  int xcs = 0;
  int ycs = 0;
  int bps = 0;
  int align = 0;

  /* Treat align==0 like align==1 */
  if (stride_align == 0) stride_align = 1;

  /* Validate alignment (must be power of 2) */
  if ((stride_align & (stride_align - 1)) != 0) {
    // console.warn('Invalid stride align');
  }

  /* Get sample size for img format */
  switch (fmt) {
    case VPX_IMG_FMT_RGB32:
    case VPX_IMG_FMT_RGB32_LE:
    case VPX_IMG_FMT_ARGB:
    case VPX_IMG_FMT_ARGB_LE:
      bps = 32;
      break;
    case VPX_IMG_FMT_RGB24:
    case VPX_IMG_FMT_BGR24:
      bps = 24;
      break;
    case VPX_IMG_FMT_RGB565:
    case VPX_IMG_FMT_RGB565_LE:
    case VPX_IMG_FMT_RGB555:
    case VPX_IMG_FMT_RGB555_LE:
    case VPX_IMG_FMT_UYVY:
    case VPX_IMG_FMT_YUY2:
    case VPX_IMG_FMT_YVYU:
      bps = 16;
      break;
    case VPX_IMG_FMT_I420:
    case VPX_IMG_FMT_YV12:
    case VPX_IMG_FMT_VPXI420:
    case VPX_IMG_FMT_VPXYV12:
      bps = 12;
      break;
    default:
      bps = 16;
      break;
  }

  /* Get chroma shift values for img format */
  switch (fmt) {
    case VPX_IMG_FMT_I420:
    case VPX_IMG_FMT_YV12:
    case VPX_IMG_FMT_VPXI420:
    case VPX_IMG_FMT_VPXYV12:
      xcs = 1;
      break;
    default:
      xcs = 0;
      break;
  }

  switch (fmt) {
    case VPX_IMG_FMT_I420:
    case VPX_IMG_FMT_YV12:
    case VPX_IMG_FMT_VPXI420:
    case VPX_IMG_FMT_VPXYV12:
      ycs = 1;
      break;
    default:
      ycs = 0;
      break;
  }

  /* Calculate storage sizes given the chroma subsampling */
  align = ((1 << xcs) - 1);
  w = ((d_w + align) & ~align);
  align = ((1 << ycs) - 1);
  h = ((d_h + align) & ~align);
  s = (((fmt & VPX_IMG_FMT_PLANAR) != 0) ? w : (bps * w) >> 3);
  s = ((s + stride_align - 1) & ~(stride_align - 1));

  /* Allocate the new image */
  img.img_data = img_data;

  if (img_data == null) {
    int size = 0;
    if ((fmt & VPX_IMG_FMT_PLANAR) == 0) {
      size = h * s;
    } else {
      size = (h * w * bps) >> 3;
    }
    img.img_data = Uint8List(size);
    img.img_data_owner = 1;
  }

  img.fmt = fmt;
  img.w = w;
  img.h = h;
  img.x_chroma_shift = xcs;
  img.y_chroma_shift = ycs;
  img.bps = bps;

  /* Calculate strides */
  img.stride[VPX_PLANE_Y] = img.stride[VPX_PLANE_ALPHA] = s;
  img.stride[VPX_PLANE_U] = img.stride[VPX_PLANE_V] = s >> xcs;

  /* Default viewport to entire image */
  if (vpx_img_set_rect(img, 0, 0, d_w, d_h) == 0) return img;
  
  return null;
}