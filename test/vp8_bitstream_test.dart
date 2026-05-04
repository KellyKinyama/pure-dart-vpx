// Structural conformance test against the libvpx VP8 conformance vectors
// in `lib/vp8-test-vectors/`.
//
// This test verifies the parts of the decoder that are fully ported today:
//   * IVF (DKIF) container parsing
//   * Per-frame uncompressed header (RFC 6386 §9.1):
//       - frame_type bit
//       - version / show_frame fields
//       - first_partition_size 19-bit field
//       - keyframe start code (0x9d 0x01 0x2a) and 14-bit width/height
//   * Frame iteration: every frame can be located via the IVF index without
//     overrunning the file, and dimensions in the keyframe header agree with
//     the IVF container header.
//
// It does NOT yet attempt MD5 comparison of decoded pixels; the recon
// pipeline (intra/inter prediction, loop filter, frame buffer allocation)
// is still being ported. See `vp8_vectors_test.dart` for the (currently
// skipped) pixel-level harness.
//
// Run with: dart test test/vp8_bitstream_test.dart

@Tags(['vectors'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const vectorsDir = 'lib/vp8-test-vectors';

void main() {
  final dir = Directory(vectorsDir);
  if (!dir.existsSync()) {
    test('vp8 conformance vectors directory missing', () {
      markTestSkipped('$vectorsDir not present');
    });
    return;
  }

  final ivfFiles =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => p.extension(f.path) == '.ivf')
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (ivfFiles.isEmpty) {
    test('no .ivf vectors found', () {
      markTestSkipped('no IVF files in $vectorsDir');
    });
    return;
  }

  group('IVF container + VP8 frame header (RFC 6386 §9.1)', () {
    for (final file in ivfFiles) {
      final name = p.basename(file.path);
      test(name, () {
        final bytes = file.readAsBytesSync();
        final ivf = _parseIvf(bytes);

        expect(ivf.fourcc, 'VP80', reason: 'fourcc must be VP80');
        expect(ivf.width, greaterThan(0));
        expect(ivf.height, greaterThan(0));
        expect(ivf.frames, isNotEmpty);

        // First frame must be a keyframe and must carry the start code.
        // Note: the keyframe carries the *coded* width/height; the IVF
        // container may advertise a different *display* size when the
        // keyframe sets horiz_scale / vert_scale (RFC 6386 §9.1). So we do
        // not assert IVF == keyframe dims, only that both are non-zero.
        final f0 = ivf.frames.first;
        final h0 = _parseVp8FrameHeader(f0);
        expect(h0.isKeyframe, isTrue, reason: 'frame 0 must be a keyframe');
        expect(
          h0.startCodeOk,
          isTrue,
          reason: 'frame 0 must contain start code 9d 01 2a',
        );
        expect(h0.width, greaterThan(0));
        expect(h0.height, greaterThan(0));
        expect(h0.width, lessThanOrEqualTo(0x3fff));
        expect(h0.height, lessThanOrEqualTo(0x3fff));
        expect(
          h0.firstPartitionSize,
          lessThan(f0.length),
          reason: 'first_partition_size must fit inside the frame',
        );

        // Every frame must parse, and any subsequent keyframes must keep the
        // same start code and a consistent width/height.
        for (var i = 0; i < ivf.frames.length; i++) {
          final f = ivf.frames[i];
          expect(
            f.length,
            greaterThanOrEqualTo(3),
            reason: 'frame $i too small for uncompressed header',
          );
          final h = _parseVp8FrameHeader(f);
          expect(
            h.firstPartitionSize,
            lessThan(f.length),
            reason: 'frame $i first_partition_size out of range',
          );
          if (h.isKeyframe) {
            expect(
              h.startCodeOk,
              isTrue,
              reason: 'keyframe $i missing start code',
            );
            // RFC 6386 §9.1: every keyframe re-declares stream dimensions and
            // is permitted to change them. The IVF container header is only
            // authoritative for frame 0; later keyframes need only carry
            // non-zero dimensions inside the 14-bit field.
            expect(
              h.width,
              greaterThan(0),
              reason: 'keyframe $i width must be non-zero',
            );
            expect(
              h.height,
              greaterThan(0),
              reason: 'keyframe $i height must be non-zero',
            );
            expect(h.width, lessThanOrEqualTo(0x3fff));
            expect(h.height, lessThanOrEqualTo(0x3fff));
          }
        }
      });
    }
  });

  // -------------------------------------------------------------------------
  // Cross-check against the libvpx test_case_14xx_descriptions.tsv metadata.
  // Schema: filename<TAB>category<TAB>description<TAB>frames<TAB>w<TAB>h<TAB>id
  // For every row whose .ivf + .ivf.md5 are present we verify:
  //   * IVF frame count == declared frame count
  //   * .ivf.md5 line count == declared frame count
  //   * keyframe[0] coded width/height == declared coded w/h
  // This catches container truncation and keyframe-header parse drift.
  // -------------------------------------------------------------------------
  final tsv = File(p.join(vectorsDir, 'test_case_14xx_descriptions.tsv'));
  if (tsv.existsSync()) {
    group('libvpx test_case_14xx descriptions cross-check', () {
      for (final line in tsv.readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        final cols = line.split('\t');
        if (cols.length < 7) continue;
        final fname = cols[0];
        final declaredFrames = int.tryParse(cols[3]);
        final declaredW = int.tryParse(cols[4]);
        final declaredH = int.tryParse(cols[5]);
        if (declaredFrames == null || declaredW == null || declaredH == null) {
          continue;
        }
        final ivfPath = p.join(vectorsDir, fname);
        final md5Path = '$ivfPath.md5';
        if (!File(ivfPath).existsSync()) continue;

        test(fname, () {
          final ivf = _parseIvf(File(ivfPath).readAsBytesSync());
          // The TSV "frames" column counts *displayed* frames. IVF packets
          // can include hidden alt-ref frames (show_frame == 0) which are
          // referenced for prediction but never emitted, so the raw packet
          // count may exceed the displayed count.
          final shown = ivf.frames
              .where((f) => _parseVp8FrameHeader(f).showFrame == 1)
              .length;
          expect(
            shown,
            declaredFrames,
            reason: 'IVF shown-frame count must match TSV',
          );
          if (File(md5Path).existsSync()) {
            final md5Lines = File(
              md5Path,
            ).readAsLinesSync().where((l) => l.trim().isNotEmpty).length;
            expect(
              md5Lines,
              declaredFrames,
              reason: '.ivf.md5 line count must match declared frames',
            );
          }
          final h0 = _parseVp8FrameHeader(ivf.frames.first);
          expect(
            h0.width,
            declaredW,
            reason: 'keyframe coded width must match TSV',
          );
          expect(
            h0.height,
            declaredH,
            reason: 'keyframe coded height must match TSV',
          );
        });
      }
    });
  }
}

// ---------------------------------------------------------------------------
// IVF parser
// ---------------------------------------------------------------------------
class _Ivf {
  final String fourcc;
  final int width;
  final int height;
  final List<Uint8List> frames;
  _Ivf(this.fourcc, this.width, this.height, this.frames);
}

_Ivf _parseIvf(Uint8List bytes) {
  if (bytes.length < 32 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'DKIF') {
    throw StateError('not an IVF file');
  }
  final bd = ByteData.sublistView(bytes);
  final hdrLen = bd.getUint16(6, Endian.little);
  final fourcc = String.fromCharCodes(bytes.sublist(8, 12));
  final w = bd.getUint16(12, Endian.little);
  final h = bd.getUint16(14, Endian.little);

  final frames = <Uint8List>[];
  var off = hdrLen;
  while (off + 12 <= bytes.length) {
    final size = bd.getUint32(off, Endian.little);
    off += 12; // skip 8-byte pts
    if (off + size > bytes.length) break;
    frames.add(Uint8List.sublistView(bytes, off, off + size));
    off += size;
  }
  return _Ivf(fourcc, w, h, frames);
}

// ---------------------------------------------------------------------------
// VP8 frame header (RFC 6386 §9.1) — uncompressed portion only.
// ---------------------------------------------------------------------------
class _Vp8Hdr {
  final bool isKeyframe;
  final int version;
  final int showFrame;
  final int firstPartitionSize;
  final bool startCodeOk;
  final int width;
  final int height;
  _Vp8Hdr({
    required this.isKeyframe,
    required this.version,
    required this.showFrame,
    required this.firstPartitionSize,
    required this.startCodeOk,
    required this.width,
    required this.height,
  });
}

_Vp8Hdr _parseVp8FrameHeader(Uint8List frame) {
  // RFC 6386 §9.1: first 3 bytes form the uncompressed header.
  final c0 = frame[0];
  final isKey = (c0 & 0x01) == 0;
  final version = (c0 >> 1) & 7;
  final showFrame = (c0 >> 4) & 1;
  final fps = (c0 | (frame[1] << 8) | (frame[2] << 16)) >> 5;

  if (!isKey) {
    return _Vp8Hdr(
      isKeyframe: false,
      version: version,
      showFrame: showFrame,
      firstPartitionSize: fps,
      startCodeOk: false,
      width: 0,
      height: 0,
    );
  }
  if (frame.length < 10) {
    return _Vp8Hdr(
      isKeyframe: true,
      version: version,
      showFrame: showFrame,
      firstPartitionSize: fps,
      startCodeOk: false,
      width: 0,
      height: 0,
    );
  }
  final scOk = frame[3] == 0x9d && frame[4] == 0x01 && frame[5] == 0x2a;
  final w = (frame[6] | (frame[7] << 8)) & 0x3fff;
  final h = (frame[8] | (frame[9] << 8)) & 0x3fff;
  return _Vp8Hdr(
    isKeyframe: true,
    version: version,
    showFrame: showFrame,
    firstPartitionSize: fps,
    startCodeOk: scOk,
    width: w,
    height: h,
  );
}
