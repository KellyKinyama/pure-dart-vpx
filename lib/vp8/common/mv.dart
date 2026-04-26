import 'dart:typed_data';

class MotionVector {
  final Int16List as_row_col;
  late final Uint32List as_int;

  MotionVector() : as_row_col = Int16List(2) {
    as_int = as_row_col.buffer.asUint32List();
  }

  /// Create a motion vector structure as used in the original JS code
  static Map<String, dynamic> create() {
    final as_row_col = Int16List(2);
    final as_int = as_row_col.buffer.asUint32List();
    return {
      'as_row_col': as_row_col,
      'as_int': as_int,
    };
  }

  // Convenient accessors
  int get row => as_row_col[0];
  set row(int val) => as_row_col[0] = val.toSigned(16);
  
  int get col => as_row_col[1];
  set col(int val) => as_row_col[1] = val.toSigned(16);

  int get integer => as_int[0];
  set integer(int val) => as_int[0] = val.toUnsigned(32);
}