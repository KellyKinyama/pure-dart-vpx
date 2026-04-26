import 'dart:typed_data';
import '../common/findnearmv.dart' hide B_PRED;
import '../common/mv.dart';
import '../common/vp8_entropymodedata.dart';
import '../common/coefupdateprobs.dart';
import '../common/entropymode.dart';
import '../common/modecont.dart';
import '../../vpx_dsp/bitreader.dart';
import './treereader.dart';
import '../common/entropymv.dart';
import '../common/onyxc_int.dart';
import '../common/blockd.dart';
import 'dboolhuff.dart';
import 'onyxd_int.dart';

const int CURRENT_FRAME = 0;
const int MV_PROB_CNT = 19;
const int INTRA_FRAME = 0;

const int CNT_BEST = 0;
const int CNT_ZEROZERO = 0;
const int CNT_INTRA = 0;
const int CNT_NEAREST = 1;
const int CNT_NEAR = 2;
const int CNT_SPLITMV = 3;

final Uint8List mbsplit_fill_count = Uint8List.fromList([8, 8, 4, 1]);

void read_mb_features(VpxReader r, MODE_INFO mi, MACROBLOCKD x) {
  if (x.enabled == 1 && x.update_map == 1) {
    if (vpx_read(r, x.tree_probs[0]) == 1) {
      mi.mbmi.segment_id = 2 + vpx_read(r, x.tree_probs[2]);
    } else {
      mi.mbmi.segment_id = vpx_read(r, x.tree_probs[1]);
    }
  }
}

/**
 * static MB_PREDICTION_MODE
 */
int read_kf_ymode(VpxReader bc, Uint8List p) {
  return vp8_treed_read(bc, vp8_kf_ymode_tree, p, 0);
}

/*
 * static B_PREDICTION_MODE
 */
int read_bmode(VpxReader bc, Uint8List p, int p_ptr) {
  return vp8_treed_read(bc, vp8_bmode_tree, p, p_ptr);
}

/**
 * static MB_PREDICTION_MODE
 */
int read_uv_mode(VpxReader bc, Uint8List p) {
  return vp8_treed_read(bc, vp8_uv_mode_tree, p, 0);
}

/**
 * @param {type} pbi
 * @param {type} mi
 * @param {type} this_off
 * @param {type} bool
 * @returns {undefined}
 */
void read_kf_modes(VP8D_COMP pbi, List<MODE_INFO> mi, int this_off, VpxReader bool) {
  // var uv_mode = 0;
  var mis = pbi.common.mode_info_stride;
  var mi_cache = mi[this_off];
  
  // Add split mode dynamically to block info
  mi_cache.init_split_mode();
  
  var modes_cache = mi_cache.bmi!.modes;
  mi_cache.mbmi.ref_frame = INTRA_FRAME;
  mi_cache.mbmi.y_mode = read_kf_ymode(bool, vp8_kf_ymode_prob);

  if (mi_cache.mbmi.y_mode == B_PRED) {
    int i = 0;
    mi_cache.mbmi.is_4x4 = 1;
    do {
      int A = above_block_mode(mi, this_off, i, mis);
      int L = left_block_mode(mi, this_off, i);
      modes_cache[i] = read_bmode(bool, vp8_kf_bmode_prob, (A * 90) + L * 9);
    } while (++i < 16);
  }

  mi_cache.mbmi.uv_mode = read_uv_mode(bool, vp8_kf_uv_mode_prob);
}

void vp8_clamp_mv2(MotionVector mv, dynamic bounds) {
  if (mv.col < bounds.mb_to_left_edge) {
    mv.col = bounds.mb_to_left_edge;
  } else if (mv.col > bounds.mb_to_right_edge) {
    mv.col = bounds.mb_to_right_edge;
  }

  if (mv.row < bounds.mb_to_top_edge) {
    mv.row = bounds.mb_to_top_edge;
  } else if (mv.row > bounds.mb_to_bottom_edge) {
    mv.row = bounds.mb_to_bottom_edge;
  }
}

void read_mv(VpxReader bool, MotionVector mv, List<Uint8List> mvc) {
  mv.col = read_mv_component(bool, mvc[0]);
  mv.row = read_mv_component(bool, mvc[1]);
}

void decode_split_mv(MODE_INFO mi, MODE_INFO left_mb, MODE_INFO above_mb, FRAME_CONTEXT hdr, MotionVector best_mv, VpxReader bool) {
  int j = 0;
  int k = 0;
  int s = 3;
  int num_p = 16;

  if (vpx_read(bool, 110) == 1) {
    s = 2;
    num_p = 4;
    if (vpx_read(bool, 111) == 1) {
      s = vpx_read(bool, 150);
      num_p = 2;
    }
  }

  Int32List partition = vp8_mbsplits[s];
  var mvs = mi.bmi!.mvs;

  do {
    MotionVector blockmv = MotionVector();
    MotionVector left_mv = MotionVector();
    MotionVector above_mv = MotionVector();

    /* Find the first subblock in this partition. */
    for (k = 0; j != partition[k]; k++) ;

    /* Decode the next MV */
    if ((k & 3) == 0) {
      if (left_mb.mbmi.y_mode == SPLITMV) {
        left_mv.row = left_mb.bmi!.mvs[k + 3].row;
        left_mv.col = left_mb.bmi!.mvs[k + 3].col;
      } else {
        left_mv.row = left_mb.mbmi.mv.row;
        left_mv.col = left_mb.mbmi.mv.col;
      }
    } else {
      left_mv.row = mi.bmi!.mvs[k - 1].row;
      left_mv.col = mi.bmi!.mvs[k - 1].col;
    }

    if (k < 4) {
      if (above_mb.mbmi.y_mode == SPLITMV) {
        above_mv.row = above_mb.bmi!.mvs[k + 12].row;
        above_mv.col = above_mb.bmi!.mvs[k + 12].col;
      } else {
        above_mv.row = above_mb.mbmi.mv.row;
        above_mv.col = above_mb.mbmi.mv.col;
      }
    } else {
      above_mv.row = mi.bmi!.mvs[k - 4].row;
      above_mv.col = mi.bmi!.mvs[k - 4].col;
    }

    Uint8List prob = get_sub_mv_ref_prob(left_mv, above_mv);

    if (vpx_read(bool, prob[0]) == 1) {
      if (vpx_read(bool, prob[1]) == 1) {
        if (vpx_read(bool, prob[2]) == 1) {
          read_mv(bool, blockmv, hdr.mv_probs);
          blockmv.row += best_mv.row;
          blockmv.col += best_mv.col;
        }
      } else {
        blockmv.row = above_mv.row;
        blockmv.col = above_mv.col;
      }
    } else {
      blockmv.row = left_mv.row;
      blockmv.col = left_mv.col;
    }

    // var fill_count = mbsplit_fill_count[s];
    /* Fill the MV's for this partition */
    for (; k < 16; k++) {
      if (j == partition[k]) {
        mvs[k].row = blockmv.row;
        mvs[k].col = blockmv.col;
      }
    }
  } while (++j < num_p);

  mi.mbmi.partitioning = s;
}

Uint8List get_sub_mv_ref_prob(MotionVector left, MotionVector above) {
  bool lez = (left.row == 0 && left.col == 0);
  bool aez = (above.row == 0 && above.col == 0);
  bool lea = (left.row == above.row && left.col == above.col);

  return vp8_sub_mv_ref_prob3[(aez ? 4 : 0) | (lez ? 2 : 0) | (lea ? 1 : 0)];
}

final List<Uint8List> vp8_sub_mv_ref_prob3 = [
  Uint8List.fromList([147, 136, 18]), /* SUBMVREF_NORMAL          */
  Uint8List.fromList([223, 1, 34]),   /* SUBMVREF_LEFT_ABOVE_SAME */
  Uint8List.fromList([106, 145, 1]),  /* SUBMVREF_LEFT_ZED        */
  Uint8List.fromList([208, 1, 1]),    /* SUBMVREF_LEFT_ABOVE_ZED  */
  Uint8List.fromList([179, 121, 1]),  /* SUBMVREF_ABOVE_ZED       */
  Uint8List.fromList([223, 1, 34]),   /* SUBMVREF_LEFT_ABOVE_SAME */
  Uint8List.fromList([179, 121, 1]),  /* SUBMVREF_ABOVE_ZED       */
  Uint8List.fromList([208, 1, 1])     /* SUBMVREF_LEFT_ABOVE_ZED  */
];

bool need_mc_border(MotionVector mv, int l, int t, int b_w, int w, int h) {
  int rb = 0;
  int bb = 0;

  // Get distance to edge for top-left pixel 
  l += (mv.col >> 3);
  t += (mv.row >> 3);

  // Get distance to edge for bottom-right pixel 
  rb = w - (l + b_w);
  bb = h - (t + b_w);

  return (l >> 1 < 2 || rb >> 1 < 3 || t >> 1 < 2 || bb >> 1 < 3);
}

int read_mv_component(VpxReader bool, Uint8List mvc) {
  const int IS_SHORT = 0, SIGN = 1, SHORT = 2, BITS = SHORT + 7, LONG_WIDTH = 10;
  int x = 0;

  if (vpx_read(bool, mvc[IS_SHORT]) == 1) // Large 
  {
    for (int i = 0; i < 3; i++) {
        x += vpx_read(bool, mvc[BITS + i]) << i;
    }

    /* Skip bit 3, which is sometimes implicit */
    for (int i = LONG_WIDTH - 1; i > 3; i--) {
        x += vpx_read(bool, mvc[BITS + i]) << i;
    }

    if ((x & 0xFFF0) == 0 || vpx_read(bool, mvc[BITS + 3]) == 1) {
        x += 8;
    }
  } else { /* small */
    x = vp8_treed_read(bool, vp8_small_mvtree, mvc, SHORT);
  }

  if (x != 0 && vpx_read(bool, mvc[SIGN]) == 1) {
    x = -x;
  }

  return (x << 1);
}

final List<MotionVector> near_mvs = List.generate(4, (_) => MotionVector());
final MotionVector near_mvs_best = MotionVector();
final List<MotionVector> chroma_mv = List.generate(4, (_) => MotionVector());
final Int32List cnt = Int32List(4);
final MotionVector this_mv_tmp = MotionVector();

void read_mb_modes_mv(VP8D_COMP pbi, List<MODE_INFO> mi, int this_off, VpxReader bool, dynamic bounds) {
  var mbmi = mi[this_off].mbmi;
  var hdr = pbi.common.entropy_hdr;
  var this_ = mi[this_off];

  if (vpx_read(bool, hdr.prob_inter) == 1) {
    // nearmvs
    var left_ = mi[this_off - 1];
    var mis = pbi.common.mode_info_stride;
    var above = mi[this_off - mis];
    var aboveleft = mi[this_off - mis - 1];
    var sign_bias = pbi.common.sign_bias;

    mbmi.ref_frame = vpx_read(bool, hdr.prob_last) == 1
        ? 2 + vpx_read(bool, hdr.prob_gf)
        : 1;

    /* Zero accumulators */
    near_mvs[0].row = near_mvs[0].col = 0;
    near_mvs[1].row = near_mvs[1].col = 0;
    near_mvs[2].row = near_mvs[2].col = 0;
    cnt[0] = cnt[1] = cnt[2] = cnt[3] = 0;

    int mv_off = 0;
    int cntx_off = 0;

    /* Process above */
    if (above.mbmi.ref_frame != INTRA_FRAME) {
      if (above.mbmi.mv.row != 0 || above.mbmi.mv.col != 0) {
        mv_off++;
        near_mvs[mv_off].row = above.mbmi.mv.row;
        near_mvs[mv_off].col = above.mbmi.mv.col;
        mv_bias(above, sign_bias, mbmi.ref_frame, near_mvs[mv_off]);
        cntx_off++;
      }
      cnt[cntx_off] += 2;
    }

    /* Process left */
    if (left_.mbmi.ref_frame != INTRA_FRAME) {
      if (left_.mbmi.mv.row != 0 || left_.mbmi.mv.col != 0) {
        this_mv_tmp.row = left_.mbmi.mv.row;
        this_mv_tmp.col = left_.mbmi.mv.col;
        mv_bias(left_, sign_bias, mbmi.ref_frame, this_mv_tmp);

        if (this_mv_tmp.row != near_mvs[mv_off].row || this_mv_tmp.col != near_mvs[mv_off].col) {
          mv_off++;
          near_mvs[mv_off].row = this_mv_tmp.row;
          near_mvs[mv_off].col = this_mv_tmp.col;
          cntx_off++;
        }
        cnt[cntx_off] += 2;
      } else {
        cnt[CNT_ZEROZERO] += 2;
      }
    }

    /* Process above left */
    if (aboveleft.mbmi.ref_frame != INTRA_FRAME) {
      if (aboveleft.mbmi.mv.row != 0 || aboveleft.mbmi.mv.col != 0) {
        this_mv_tmp.row = aboveleft.mbmi.mv.row;
        this_mv_tmp.col = aboveleft.mbmi.mv.col;
        mv_bias(aboveleft, sign_bias, mbmi.ref_frame, this_mv_tmp);

        if (this_mv_tmp.row != near_mvs[mv_off].row || this_mv_tmp.col != near_mvs[mv_off].col) {
          mv_off++;
          near_mvs[mv_off].row = this_mv_tmp.row;
          near_mvs[mv_off].col = this_mv_tmp.col;
          cntx_off++;
        }
        cnt[cntx_off] += 1;
      } else {
        cnt[CNT_ZEROZERO] += 1;
      }
    }

    /* If we have three distinct MV's ... */
    if (cnt[CNT_SPLITMV] != 0) {
      /* See if above-left MV can be merged with NEAREST */
      if (near_mvs[mv_off].row == near_mvs[CNT_NEAREST].row &&
          near_mvs[mv_off].col == near_mvs[CNT_NEAREST].col) {
        cnt[CNT_NEAREST] += 1;
      }
    }

    cnt[CNT_SPLITMV] = ((above.mbmi.y_mode == SPLITMV ? 1 : 0) + (left_.mbmi.y_mode == SPLITMV ? 1 : 0)) * 2 + (aboveleft.mbmi.y_mode == SPLITMV ? 1 : 0);

    /* Swap near and nearest if necessary */
    if (cnt[CNT_NEAR] > cnt[CNT_NEAREST]) {
      int tmp_cnt = cnt[CNT_NEAREST];
      cnt[CNT_NEAREST] = cnt[CNT_NEAR];
      cnt[CNT_NEAR] = tmp_cnt;
      
      int tmp_row = near_mvs[CNT_NEAREST].row;
      int tmp_col = near_mvs[CNT_NEAREST].col;
      near_mvs[CNT_NEAREST].row = near_mvs[CNT_NEAR].row;
      near_mvs[CNT_NEAREST].col = near_mvs[CNT_NEAR].col;
      near_mvs[CNT_NEAR].row = tmp_row;
      near_mvs[CNT_NEAR].col = tmp_col;
    }
    
    if (cnt[CNT_NEAREST] >= cnt[CNT_BEST]) {
      near_mvs[CNT_BEST].row = near_mvs[CNT_NEAREST].row;
      near_mvs[CNT_BEST].col = near_mvs[CNT_NEAREST].col;
    }

    this_.mbmi.need_mc_border = 0;
    int x = (-bounds.mb_to_left_edge - 128) >> 3;
    int y = (-bounds.mb_to_top_edge - 128) >> 3;
    int w = pbi.common.mb_cols << 4;
    int h = pbi.common.mb_rows << 4;

    if (vpx_read(bool, vp8_mode_contexts[cnt[CNT_INTRA] * 4]) == 1) {
      if (vpx_read(bool, vp8_mode_contexts[cnt[CNT_NEAREST] * 4 + 1]) == 1) {
        if (vpx_read(bool, vp8_mode_contexts[cnt[CNT_NEAR] * 4 + 2]) == 1) {
          if (vpx_read(bool, vp8_mode_contexts[cnt[CNT_SPLITMV] * 4 + 3]) == 1) {
            // splitmv
            this_.mbmi.y_mode = SPLITMV;
            chroma_mv[0].row = chroma_mv[0].col = 0;
            chroma_mv[1].row = chroma_mv[1].col = 0;
            chroma_mv[2].row = chroma_mv[2].col = 0;
            chroma_mv[3].row = chroma_mv[3].col = 0;

            MotionVector clamped_best_mv = MotionVector();
            clamped_best_mv.row = near_mvs[CNT_BEST].row;
            clamped_best_mv.col = near_mvs[CNT_BEST].col;
            vp8_clamp_mv2(clamped_best_mv, bounds);

            decode_split_mv(this_, left_, above, hdr, clamped_best_mv, bool);
            this_.mbmi.mv.row = this_.bmi!.mvs[15].row;
            this_.mbmi.mv.col = this_.bmi!.mvs[15].col;

            var this_mvs = this_.bmi!.mvs;
            for (int b = 0; b < 16; b++) {
              int chroma_idx = (b >> 1 & 1) + (b >> 2 & 2);
              chroma_mv[chroma_idx].col += this_mvs[b].col;
              chroma_mv[chroma_idx].row += this_mvs[b].row;

              if (need_mc_border(this_mvs[b], x + (b & 3) * 4, y + (b & ~3), 4, w, h)) {
                this_.mbmi.need_mc_border = 1;
              }
            }

            for (int b = 0; b < 4; b++) {
              chroma_mv[b].col += 4 + (chroma_mv[b].col >> 28);
              chroma_mv[b].row += 4 + (chroma_mv[b].row >> 28);
              chroma_mv[b].col = (chroma_mv[b].col >> 2).toInt();
              chroma_mv[b].row = (chroma_mv[b].row >> 2).toInt();

              if (need_mc_border(chroma_mv[b], x + (b & 1) * 8, y + ((b >> 1) << 3), 16, w, h)) {
                this_.mbmi.need_mc_border = 1;
              }
            }
          } else {
            // new mv
            MotionVector clamped_best_mv = MotionVector();
            clamped_best_mv.row = near_mvs[CNT_BEST].row;
            clamped_best_mv.col = near_mvs[CNT_BEST].col;
            vp8_clamp_mv2(clamped_best_mv, bounds);

            read_mv(bool, this_.mbmi.mv, hdr.mv_probs);
            this_.mbmi.mv.col += clamped_best_mv.col;
            this_.mbmi.mv.row += clamped_best_mv.row;
            this_.mbmi.y_mode = NEWMV;
          }
        } else {
          // nearmv
          this_.mbmi.mv.row = near_mvs[CNT_NEAR].row;
          this_.mbmi.mv.col = near_mvs[CNT_NEAR].col;
          vp8_clamp_mv2(this_.mbmi.mv, bounds);
          this_.mbmi.y_mode = NEARMV;
        }
      } else {
        this_.mbmi.y_mode = NEARESTMV;
        this_.mbmi.mv.row = near_mvs[CNT_NEAREST].row;
        this_.mbmi.mv.col = near_mvs[CNT_NEAREST].col;
        vp8_clamp_mv2(this_.mbmi.mv, bounds);
      }
    } else {
      this_.mbmi.y_mode = ZEROMV;
      this_.mbmi.mv.row = 0;
      this_.mbmi.mv.col = 0;
    }

    if (need_mc_border(this_.mbmi.mv, x, y, 16, w, h)) {
      this_.mbmi.need_mc_border = 1;
    }
  } else {
    // intra
    int y_mode = vp8_treed_read(bool, vp8_ymode_tree, hdr.y_mode_probs, 0);
    if (y_mode == B_PRED) {
      var modes = this_.bmi!.modes;
      var mvs = this_.bmi!.mvs;
      for (int i = 0; i < 16; i++) {
        int b = vp8_treed_read(bool, vp8_bmode_tree, vp8_bmode_prob, 0);
        modes[i] = b;
        mvs[i].row = b; // JS was doing modes[i] = mvs[i].as_row_col[0] = b
      }
    }
    mbmi.y_mode = y_mode;
    mbmi.uv_mode = vp8_treed_read(bool, vp8_uv_mode_tree, hdr.uv_mode_probs, 0);
    mbmi.mv.row = mbmi.mv.col = 0;
    mbmi.ref_frame = CURRENT_FRAME;
  }
}

void decode_mb_mode_mvs(VP8D_COMP pbi, VpxReader bool, List<MODE_INFO> mi, int this_off, dynamic bounds) {
  var mi_cache = mi[this_off];
  
  if (pbi.segment_hdr.update_map == 1) {
    read_mb_features(bool, mi_cache, pbi.segment_hdr);
  } else if (pbi.common.is_key_frame && pbi.segment_hdr.update_map == 0) {
    mi_cache.mbmi.segment_id = 0;
  }

  if (pbi.common.entropy_hdr.coeff_skip_enabled == 1) {
    mi_cache.mbmi.mb_skip_coeff = vpx_read(bool, pbi.common.entropy_hdr.coeff_skip_prob);
  } else {
    mi_cache.mbmi.mb_skip_coeff = 0;
  }

  mi_cache.mbmi.is_4x4 = 0;
  if (pbi.common.is_key_frame) {
    read_kf_modes(pbi, mi, this_off, bool);
  } else {
    read_mb_modes_mv(pbi, mi, this_off, bool, bounds);
  }
}

void read_mvcontexts(BOOL_DECODER bc, List<Uint8List> mvc) {
  for (int i = 0; i < 2; i++) {
    for (int j = 0; j < MV_PROB_CNT; j++) {
      if (vpx_read(bc, vp8_mv_update_probs[i][j]) == 1) {
        int x = bc.get_uint(7);
        if (x > 0) {
          mvc[i][j] = x << 1;
        } else {
          mvc[i][j] = 1;
        }
      }
    }
  }
}

void mb_mode_mv_init(VP8D_COMP pbi) {
  var bc = pbi.bool_decoder;
  var entropy_hdr = pbi.common.entropy_hdr;
  var bool = bc;

  var coeff_probs = entropy_hdr.coeff_probs;
  /* Read coefficient probability updates */
  for (int i = 0; i < 1056; i++) {
    if (vpx_read(bool, vp8_coef_update_probs[i]) == 1) {
      coeff_probs[i] = bool.get_uint(8);
    }
  }

  /* Read coefficient skip mode probability */
  entropy_hdr.coeff_skip_enabled = vpx_read_bit(bool);

  if (entropy_hdr.coeff_skip_enabled == 1) {
    entropy_hdr.coeff_skip_prob = bool.get_uint(8);
  } else {
    entropy_hdr.coeff_skip_prob = 0;
  }

  /* Parse interframe probability updates */
  if (!pbi.common.is_key_frame) {
    entropy_hdr.prob_inter = bool.get_uint(8);
    entropy_hdr.prob_last = bool.get_uint(8);
    entropy_hdr.prob_gf = bool.get_uint(8);

    if (vpx_read_bit(bool) == 1) {
      entropy_hdr.y_mode_probs[0] = bool.get_uint(8);
      entropy_hdr.y_mode_probs[1] = bool.get_uint(8);
      entropy_hdr.y_mode_probs[2] = bool.get_uint(8);
      entropy_hdr.y_mode_probs[3] = bool.get_uint(8);
    }

    if (vpx_read_bit(bool) == 1) {
      entropy_hdr.uv_mode_probs[0] = bool.get_uint(8);
      entropy_hdr.uv_mode_probs[1] = bool.get_uint(8);
      entropy_hdr.uv_mode_probs[2] = bool.get_uint(8);
    }

    read_mvcontexts(bc, entropy_hdr.mv_probs);
  }
}

class MVBounds {
  int mb_to_left_edge = 0;
  int mb_to_right_edge = 0;
  int mb_to_top_edge = 0;
  int mb_to_bottom_edge = 0;
}

final MVBounds bounds = MVBounds();

void vp8_decode_mode_mvs(VP8D_COMP pbi, VpxReader bool) {
  int mb_row = -1;
  int mb_rows = pbi.common.mb_rows;
  int mb_cols = pbi.common.mb_cols;

  bounds.mb_to_left_edge = 0;
  bounds.mb_to_right_edge = 0;
  bounds.mb_to_top_edge = 0;
  bounds.mb_to_bottom_edge = 0;

  mb_mode_mv_init(pbi);

  bounds.mb_to_top_edge = 0;

  while (++mb_row < mb_rows) {
    int mb_col = -1;
    // int above_off = 0;
    int this_off = 0;

    List<MODE_INFO> this_ = pbi.mb_info_rows;
    this_off = pbi.mb_info_rows_off[1 + mb_row];
    // above_off = pbi.mb_info_rows_off_list[mb_row];

    // Calculate the eighth-pel MV bounds using a 1 MB border.
    bounds.mb_to_left_edge = -((1) << 7);
    bounds.mb_to_right_edge = (pbi.common.mb_cols) << 7;
    bounds.mb_to_top_edge = -((mb_row + 1) << 7);
    bounds.mb_to_bottom_edge = (pbi.common.mb_rows - mb_row) << 7;

    while (++mb_col < mb_cols) {
      decode_mb_mode_mvs(pbi, bool, this_, this_off, bounds);
      this_off++;
      bounds.mb_to_left_edge -= (16 << 3);
      bounds.mb_to_right_edge -= (16 << 3);
    }
  }
}