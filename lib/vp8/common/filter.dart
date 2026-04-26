import 'dart:typed_data';
import 'dart:math' as math;
import 'mv.dart';

class FilterWithShape {
  final Int16List filter;
  int shape = 0;
  FilterWithShape(List<int> f, this.shape) : filter = Int16List.fromList(f);
}

final List<FilterWithShape> vp8_bilinear_filters = [
  FilterWithShape([0, 0, 128, 0, 0, 0], 1),
  FilterWithShape([0, 0, 112, 16, 0, 0], 1),
  FilterWithShape([0, 0, 96, 32, 0, 0], 1),
  FilterWithShape([0, 0, 80, 48, 0, 0], 1),
  FilterWithShape([0, 0, 64, 64, 0, 0], 1),
  FilterWithShape([0, 0, 48, 80, 0, 0], 1),
  FilterWithShape([0, 0, 32, 96, 0, 0], 1),
  FilterWithShape([0, 0, 16, 112, 0, 0], 1)
];

final List<FilterWithShape> vp8_sub_pel_filters = [
  FilterWithShape([0, 0, 128, 0, 0, 0], 1),
  FilterWithShape([0, -6, 123, 12, -1, 0], 2),
  FilterWithShape([2, -11, 108, 36, -8, 1], 0),
  FilterWithShape([0, -9, 93, 50, -6, 0], 2),
  FilterWithShape([3, -16, 77, 77, -16, 3], 0),
  FilterWithShape([0, -6, 50, 93, -9, 0], 2),
  FilterWithShape([1, -8, 36, 108, -11, 2], 0),
  FilterWithShape([0, -1, 12, 123, -6, 0], 2)
];

const int VP8_FILTER_SHIFT = 7;

void filter_block2d_first_pass(Uint8List output, Uint8List src, int src_ptr, int reference_stride, Int16List vp8_filter) {
  int r = 0, c = 0;
  int temp = 0;
  int output_off = 0;

  int filter0 = vp8_filter[0];
  int filter1 = vp8_filter[1];
  int filter2 = vp8_filter[2];
  int filter3 = vp8_filter[3];
  int filter4 = vp8_filter[4];
  int filter5 = vp8_filter[5];

  for (r = 0; r < 9; r++) {
    for (c = 0; c < 4; c++) {
      temp = (src[src_ptr - 2] * filter0) +
             (src[src_ptr - 1] * filter1) +
             (src[src_ptr] * filter2) +
             (src[src_ptr + 1] * filter3) +
             (src[src_ptr + 2] * filter4) +
             (src[src_ptr + 3] * filter5) +
             64;
      temp >>= VP8_FILTER_SHIFT;
      temp = temp.clamp(0, 255);
      output[output_off + c] = temp;
      src_ptr++;
    }
    src_ptr += reference_stride - 4;
    output_off += 16;
  }
}

void filter_block2d_first_pass_shape_2(Uint8List output, Uint8List src, int src_ptr, int reference_stride, Int16List vp8_filter) {
  int r = 0, c = 0;
  int temp = 0;
  int output_off = 0;

  int filter1 = vp8_filter[1];
  int filter2 = vp8_filter[2];
  int filter3 = vp8_filter[3];
  int filter4 = vp8_filter[4];

  for (r = 0; r < 9; r++) {
    for (c = 0; c < 4; c++) {
      temp = (src[src_ptr - 1] * filter1) +
             (src[src_ptr] * filter2) +
             (src[src_ptr + 1] * filter3) +
             (src[src_ptr + 2] * filter4) +
             64;
      temp >>= VP8_FILTER_SHIFT;
      temp = temp.clamp(0, 255);
      output[output_off + c] = temp;
      src_ptr++;
    }
    src_ptr += reference_stride - 4;
    output_off += 16;
  }
}

void filter_block2d_first_pass_shape_1(Uint8List output, Uint8List src, int src_ptr, int reference_stride, Int16List vp8_filter) {
  int r = 0, c = 0;
  int temp = 0;
  int output_off = 0;

  int filter2 = vp8_filter[2];
  int filter3 = vp8_filter[3];

  for (r = 0; r < 9; r++) {
    for (c = 0; c < 4; c++) {
      temp = (src[src_ptr] * filter2) +
             (src[src_ptr + 1] * filter3) +
             64;
      temp >>= VP8_FILTER_SHIFT;
      temp = temp.clamp(0, 255);
      output[output_off + c] = temp;
      src_ptr++;
    }
    src_ptr += reference_stride - 4;
    output_off += 16;
  }
}

void filter_block2d_second_pass(Uint8List output, int output_off, int output_stride, Uint8List reference, int cols, int rows, Int16List filter) {
  int reference_off = 32;
  int r = 0, c = 0, temp = 0;
  int filter0 = filter[0];
  int filter1 = filter[1];
  int filter2 = filter[2];
  int filter3 = filter[3];
  int filter4 = filter[4];
  int filter5 = filter[5];

  for (r = 0; r < rows; r++) {
    for (c = 0; c < cols; c++) {
      temp = (reference[reference_off - 32] * filter0) +
             (reference[reference_off - 16] * filter1) +
             (reference[reference_off] * filter2) +
             (reference[reference_off + 16] * filter3) +
             (reference[reference_off + 32] * filter4) +
             (reference[reference_off + 48] * filter5) +
             64;
      temp >>= 7;
      temp = temp.clamp(0, 255);
      output[output_off + c] = temp;
      reference_off++;
    }
    reference_off += 16 - cols;
    output_off += output_stride;
  }
}

void filter_block2d_second_pass_shape_1(Uint8List output, int output_off, int output_stride, Uint8List reference, int cols, int rows, Int16List filter) {
  int reference_off = 32;
  int r = 0, c = 0, temp = 0;
  int filter2 = filter[2];
  int filter3 = filter[3];

  for (r = 0; r < rows; r++) {
    for (c = 0; c < cols; c++) {
      temp = (reference[reference_off] * filter2) +
             (reference[reference_off + 16] * filter3) +
             64;
      temp >>= 7;
      temp = temp.clamp(0, 255);
      output[output_off + c] = temp;
      reference_off++;
    }
    reference_off += 16 - cols;
    output_off += output_stride;
  }
}

void filter_block2d_second_pass_shape_2(Uint8List output, int output_off, int output_stride, Uint8List reference, int cols, int rows, Int16List filter) {
  int r = 0, c = 0, temp = 0;
  int reference_off = 32;
  int filter1 = filter[1];
  int filter2 = filter[2];
  int filter3 = filter[3];
  int filter4 = filter[4];

  for (r = 0; r < rows; r++) {
    for (c = 0; c < cols; c++) {
      temp = (reference[reference_off - 16] * filter1) +
             (reference[reference_off] * filter2) +
             (reference[reference_off + 16] * filter3) +
             (reference[reference_off + 32] * filter4) +
             64;
      temp >>= 7;
      temp = temp.clamp(0, 255);
      output[output_off + c] = temp;
      reference_off++;
    }
    reference_off += 16 - cols;
    output_off += output_stride;
  }
}

final Uint8List temp_buffer = Uint8List(336);

void filter_block2d(Uint8List output, int output_off, int output_stride, Uint8List reference, int reference_off, int reference_stride, int cols, int rows, int mx, int my, List<FilterWithShape> filters) {
  if (filters[mx].shape == 1) {
    filter_block2d_first_pass_shape_1(temp_buffer, reference, reference_off - 2 * reference_stride, reference_stride, filters[mx].filter);
  } else if (filters[mx].shape == 2) {
    filter_block2d_first_pass_shape_2(temp_buffer, reference, reference_off - 2 * reference_stride, reference_stride, filters[mx].filter);
  } else {
    filter_block2d_first_pass(temp_buffer, reference, reference_off - 2 * reference_stride, reference_stride, filters[mx].filter);
  }

  if (filters[my].shape == 1) {
    filter_block2d_second_pass_shape_1(output, output_off, output_stride, temp_buffer, 4, 4, filters[my].filter);
  } else if (filters[my].shape == 2) {
    filter_block2d_second_pass_shape_2(output, output_off, output_stride, temp_buffer, 4, 4, filters[my].filter);
  } else {
    filter_block2d_second_pass(output, output_off, output_stride, temp_buffer, 4, 4, filters[my].filter);
  }
}

void filter_block(int return_off, Uint8List output, int output_off, Uint8List reference, int reference_off, int stride, MotionVector mv, List<FilterWithShape> filters) {
  if (mv.integer != 0) {
    filter_block2d(output, output_off, stride, reference, reference_off, stride, 4, 4, mv.col & 7, mv.row & 7, filters);
  }
}
