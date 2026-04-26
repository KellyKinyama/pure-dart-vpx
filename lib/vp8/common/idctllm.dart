import 'dart:typed_data';

int CLAMP_255(int x) => x.clamp(0, 255);

const int cospi8sqrt2minus1 = 20091;
const int sinpi8sqrt2 = 35468;

final Int16List output_buffer = Int16List(16);

void vp8_short_inv_walsh4x4_c(Int32List input, int input_off, int mb_dqcoeff_ptr) {
  int i;
  int a1, b1, c1, d1;
  int a2, b2, c2, d2;

  int ip0 = 0;
  int ip4 = 0;
  int ip8 = 0;
  int ip12 = 0;

  int ip_off = input_off;
  int op_off = 0;

  for (i = 0; i < 4; i++) {
    ip0 = input[ip_off];
    ip4 = input[ip_off + 4];
    ip8 = input[ip_off + 8];
    ip12 = input[ip_off + 12];

    a1 = (ip0 + ip12);
    b1 = (ip4 + ip8);
    c1 = (ip4 - ip8);
    d1 = (ip0 - ip12);

    output_buffer[op_off] = a1 + b1;
    output_buffer[op_off + 4] = c1 + d1;
    output_buffer[op_off + 8] = a1 - b1;
    output_buffer[op_off + 12] = d1 - c1;
    ip_off++;
    op_off++;
  }

  // Second pass
  Uint32List data_32 = output_buffer.buffer.asUint32List();
  for (i = 0; i < 4; i++) {
    int ip_32 = data_32[i * 2];
    int ip_low = (ip_32 & 0xFFFF).toSigned(16);
    int ip_high = (ip_32 >> 16).toSigned(16);
    
    int current_ip_0 = ip_low;
    int current_ip_1 = ip_high;

    ip_32 = data_32[i * 2 + 1];
    ip_low = (ip_32 & 0xFFFF).toSigned(16);
    ip_high = (ip_32 >> 16).toSigned(16);
    
    int current_ip_2 = ip_low;
    int current_ip_3 = ip_high;

    a1 = current_ip_0 + current_ip_3;
    b1 = current_ip_1 + current_ip_2;
    c1 = current_ip_1 - current_ip_2;
    d1 = current_ip_0 - current_ip_3;

    a2 = a1 + b1;
    b2 = c1 + d1;
    c2 = a1 - b1;
    d2 = d1 - c1;

    data_32[i * 2] = (((a2 + 3) >> 3) & 0xFFFF) | ((((b2 + 3) >> 3) & 0xFFFF) << 16);
    data_32[i * 2 + 1] = (((c2 + 3) >> 3) & 0xFFFF) | ((((d2 + 3) >> 3) & 0xFFFF) << 16);
  }

  for (i = 0; i < 16; i++) {
    input[mb_dqcoeff_ptr + (i << 4)] = output_buffer[i];
  }
}

final Int16List tmp_buffer = Int16List(16);

void vp8_short_idct4x4llm_c(Uint8List recon, int recon_off, Uint8List predict, int predict_off, int stride, Int32List coeffs, int coeffs_off) {
  int i = 0;
  int a1 = 0, b1 = 0, c1 = 0, d1 = 0, temp1 = 0, temp2 = 0;

  // Horizontal IDCT
  int ip_off = coeffs_off;
  int op_off = 0;

  for (i = 0; i < 4; i++) {
    int ip_0 = coeffs[ip_off];
    int ip_4 = coeffs[ip_off + 4];
    int ip_8 = coeffs[ip_off + 8];
    int ip_12 = coeffs[ip_off + 12];

    a1 = ip_0 + ip_8;
    b1 = ip_0 - ip_8;

    temp1 = (ip_4 * sinpi8sqrt2) >> 16;
    temp2 = ip_12 + ((ip_12 * cospi8sqrt2minus1) >> 16);
    c1 = temp1 - temp2;

    temp1 = ip_4 + ((ip_4 * cospi8sqrt2minus1) >> 16);
    temp2 = (ip_12 * sinpi8sqrt2) >> 16;
    d1 = temp1 + temp2;

    tmp_buffer[op_off] = a1 + d1;
    tmp_buffer[op_off + 12] = a1 - d1;
    tmp_buffer[op_off + 4] = b1 + c1;
    tmp_buffer[op_off + 8] = b1 - c1;

    ip_off++;
    op_off++;
  }

  // Vertical IDCT and combined with prediction
  int c_off = 0;
  for (i = 0; i < 4; i++) {
    int coeff_0 = tmp_buffer[c_off];
    int coeff_1 = tmp_buffer[c_off + 1];
    int coeff_2 = tmp_buffer[c_off + 2];
    int coeff_3 = tmp_buffer[c_off + 3];

    a1 = coeff_0 + coeff_2;
    b1 = coeff_0 - coeff_2;

    temp1 = (coeff_1 * sinpi8sqrt2) >> 16;
    temp2 = coeff_3 + ((coeff_3 * cospi8sqrt2minus1) >> 16);
    c1 = temp1 - temp2;

    temp1 = coeff_1 + ((coeff_1 * cospi8sqrt2minus1) >> 16);
    temp2 = (coeff_3 * sinpi8sqrt2) >> 16;
    d1 = temp1 + temp2;

    int p0 = predict[predict_off];
    int p1 = predict[predict_off + 1];
    int p2 = predict[predict_off + 2];
    int p3 = predict[predict_off + 3];

    recon[recon_off] = CLAMP_255(p0 + ((a1 + d1 + 4) >> 3));
    recon[recon_off + 1] = CLAMP_255(p1 + ((b1 + c1 + 4) >> 3));
    recon[recon_off + 2] = CLAMP_255(p2 + ((b1 - c1 + 4) >> 3));
    recon[recon_off + 3] = CLAMP_255(p3 + ((a1 - d1 + 4) >> 3));

    c_off += 4;
    recon_off += stride;
    predict_off += stride;
  }
}
