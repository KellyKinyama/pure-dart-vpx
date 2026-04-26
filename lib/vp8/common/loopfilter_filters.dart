import 'dart:typed_data';

int saturate_int8(int x) => x.clamp(-128, 127);
int saturate_uint8(int x) => x.clamp(0, 255);

void vp8_filter(Uint8List pixels, int pixels_off, int stride, bool use_outer_taps) {
  int stride2 = 2 * stride;
  int p1 = pixels[pixels_off - stride2];
  int p0 = pixels[pixels_off - stride];
  int q0 = pixels[pixels_off];
  int q1 = pixels[pixels_off + stride];

  int a = 3 * (q0 - p0);
  if (use_outer_taps) a += saturate_int8(p1 - q1);
  a = saturate_int8(a);

  int f1, f2;
  if ((a + 4) > 127) {
    f1 = 15;
    f2 = 15;
  } else {
    f1 = (a + 4) >> 3;
    f2 = (a + 3) >> 3;
  }

  p0 = saturate_uint8(p0 + f2);
  q0 = saturate_uint8(q0 - f1);

  if (!use_outer_taps) {
    int b = (f1 + 1) >> 1;
    p1 = saturate_uint8(p1 + b);
    q1 = saturate_uint8(q1 - b);
  }

  pixels[pixels_off - stride2] = p1;
  pixels[pixels_off - stride] = p0;
  pixels[pixels_off] = q0;
  pixels[pixels_off + stride] = q1;
}

void vp8_loop_filter_bhs_c(Uint8List y, int y_ptr, int y_stride, int blimit) {
  vp8_loop_filter_simple_horizontal_edge_c(y, y_ptr + 4 * y_stride, y_stride, blimit);
  vp8_loop_filter_simple_horizontal_edge_c(y, y_ptr + 8 * y_stride, y_stride, blimit);
  vp8_loop_filter_simple_horizontal_edge_c(y, y_ptr + 12 * y_stride, y_stride, blimit);
}

void vp8_loop_filter_simple_horizontal_edge_c(Uint8List src, int src_off, int stride, int filter_limit) {
  for (int i = 0; i < 16; i++) {
    if (simple_threshold(src, src_off, stride, filter_limit)) {
      vp8_filter(src, src_off, stride, true);
    }
    src_off += 1;
  }
}

bool simple_threshold(Uint8List pixels, int pixels_off, int stride, int filter_limit) {
  int p1 = pixels[pixels_off - (stride << 1)];
  int p0 = pixels[pixels_off - stride];
  int q0 = pixels[pixels_off];
  int q1 = pixels[pixels_off + stride];
  return (((p0 - q0).abs() << 1) + ((p1 - q1).abs() >> 1)) <= filter_limit;
}

void vp8_loop_filter_bvs_c(Uint8List y, int y_off, int stride, int b_limit) {
  vp8_loop_filter_simple_vertical_edge_c(y, y_off + 4, stride, b_limit);
  vp8_loop_filter_simple_vertical_edge_c(y, y_off + 8, stride, b_limit);
  vp8_loop_filter_simple_vertical_edge_c(y, y_off + 12, stride, b_limit);
}

void vp8_loop_filter_simple_vertical_edge_c(Uint8List src, int src_off, int stride, int filter_limit) {
  for (int i = 0; i < 16; i++) {
    if (simple_threshold(src, src_off, 1, filter_limit)) {
      vp8_filter(src, src_off, 1, true);
    }
    src_off += stride;
  }
}

void vp8_loop_filter_mbv(Uint8List y, int y_off, int u_off, int v_off, int stride, int uv_stride, int edge_limit, int interior_limit, int hev_threshold) {
  filter_mb_v_edge(y, y_off, stride, edge_limit + 2, interior_limit, hev_threshold, 2);
  filter_mb_v_edge(y, u_off, uv_stride, edge_limit + 2, interior_limit, hev_threshold, 1);
  filter_mb_v_edge(y, v_off, uv_stride, edge_limit + 2, interior_limit, hev_threshold, 1);
}

void filter_mb_v_edge(Uint8List src, int src_off, int stride, int edge_limit, int interior_limit, int hev_threshold, int size) {
  int length = size << 3;
  for (int i = 0; i < length; i++) {
    if (normal_threshold(src, src_off, 1, edge_limit, interior_limit)) {
      if (high_edge_variance(src, src_off, 1, hev_threshold)) {
        vp8_filter(src, src_off, 1, true);
      } else {
        filter_mb_edge(src, src_off, 1);
      }
    }
    src_off += stride;
  }
}

bool normal_threshold(Uint8List pixels, int pixels_off, int stride, int E, int I) {
  if (!simple_threshold(pixels, pixels_off, stride, 2 * E + I)) return false;
  if ((pixels[pixels_off - 4 * stride] - pixels[pixels_off - 3 * stride]).abs() > I) return false;
  if ((pixels[pixels_off - 3 * stride] - pixels[pixels_off - 2 * stride]).abs() > I) return false;
  if ((pixels[pixels_off - 2 * stride] - pixels[pixels_off - stride]).abs() > I) return false;
  if ((pixels[pixels_off + 3 * stride] - pixels[pixels_off + 2 * stride]).abs() > I) return false;
  if ((pixels[pixels_off + 2 * stride] - pixels[pixels_off + stride]).abs() > I) return false;
  return (pixels[pixels_off + stride] - pixels[pixels_off]).abs() <= I;
}

void filter_mb_edge(Uint8List pixels, int pixels_off, int stride) {
  int stride2 = stride << 1;
  int stride3 = 3 * stride;

  int p2 = pixels[pixels_off - stride3];
  int p1 = pixels[pixels_off - stride2];
  int p0 = pixels[pixels_off - stride];
  int q0 = pixels[pixels_off];
  int q1 = pixels[pixels_off + stride];
  int q2 = pixels[pixels_off + stride2];

  int w = saturate_int8(saturate_int8(p1 - q1) + 3 * (q0 - p0));

  int a = (27 * w + 63) >> 7;
  p0 = saturate_uint8(p0 + a);
  q0 = saturate_uint8(q0 - a);

  a = (18 * w + 63) >> 7;
  p1 = saturate_uint8(p1 + a);
  q1 = saturate_uint8(q1 - a);

  a = (9 * w + 63) >> 7;
  p2 = saturate_uint8(p2 + a);
  q2 = saturate_uint8(q2 - a);

  pixels[pixels_off - stride3] = p2;
  pixels[pixels_off - stride2] = p1;
  pixels[pixels_off - stride] = p0;
  pixels[pixels_off] = q0;
  pixels[pixels_off + stride] = q1;
  pixels[pixels_off + stride2] = q2;
}

bool high_edge_variance(Uint8List pixels, int pixels_off, int stride, int hev_threshold) {
  if ((pixels[pixels_off - 2 * stride] - pixels[pixels_off - stride]).abs() > hev_threshold) return true;
  return (pixels[pixels_off + stride] - pixels[pixels_off]).abs() > hev_threshold;
}

void vp8_loop_filter_bv_c(Uint8List y, int y_off, int u_off, int v_off, int stride, int uv_stride, int edge_limit, int interior_limit, int hev_threshold) {
  filter_subblock_v_edge(y, y_off + 4, stride, edge_limit, interior_limit, hev_threshold, 2);
  filter_subblock_v_edge(y, y_off + 8, stride, edge_limit, interior_limit, hev_threshold, 2);
  filter_subblock_v_edge(y, y_off + 12, stride, edge_limit, interior_limit, hev_threshold, 2);
  filter_subblock_v_edge(y, u_off + 4, uv_stride, edge_limit, interior_limit, hev_threshold, 1);
  filter_subblock_v_edge(y, v_off + 4, uv_stride, edge_limit, interior_limit, hev_threshold, 1);
}

void filter_subblock_v_edge(Uint8List src, int src_off, int stride, int edge_limit, int interior_limit, int hev_threshold, int size) {
  int limit = 8 * size;
  for (int i = 0; i < limit; i++) {
    if (normal_threshold(src, src_off, 1, edge_limit, interior_limit)) {
      vp8_filter(src, src_off, 1, high_edge_variance(src, src_off, 1, hev_threshold));
    }
    src_off += stride;
  }
}