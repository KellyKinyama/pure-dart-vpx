import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'integrity_verifier.dart';

class KokoroModelManager {
  static const _revision = 'f46687f7e41512228ae953af24a11b2640ea0f22';
  static const _hfBase =
      'https://huggingface.co/onnx-community/Kokoro-82M-ONNX/resolve/$_revision';
  static const _modelSha256 =
      '0d55b15d4b735d61a21b0105136bc81b8768c4db94753193c19354fa863cd556';

  static const Map<String, String> _voiceHashes = {
    'af.bin':
        'a4f11d9d055a12bfa0db2668a3e4f0ef8fd1f1ccca69494479718e44dbf9e41a',
    'af_bella.bin':
        '38e12d4b9b31a751282ab9154fb083dad3df3a749772687cde7873da107160fa',
    'af_nicole.bin':
        'f27666996f2d227711e97ff27374099df6f619f3bfb60cd67fc0d114f5384d13',
    'af_sarah.bin':
        'fe4f8b49c272dc5e484ae31a39004fd4ee2b1afc28cbed75da44fc3510b9f984',
    'am_adam.bin':
        '6d5255a4b4803f594bfa0c0d7539c4d8bb0829c7f190f0f6a8fa0afa0023b6e4',
    'am_michael.bin':
        '9c3be118019ddb41b6b529a7f75c7a3dc92613f573ca03b037748b9383b0d9d0',
  };
  static const _modelDirName = 'Kokoro-82M-ONNX';
  static const _readyMarker = '.ready';

  String? _modelDir;

  String get modelDir => _modelDir ?? '';
  String get modelPath => p.join(modelDir, 'model_quantized.onnx');

  /// Base directory for kokoro assets (parent of [modelDir]). Use this as
  /// the path for espeak-ng when espeak-ng-data is placed next to the model.
  String get kokoroBaseDir {
    if (_modelDir == null || _modelDir!.isEmpty) return '';
    final dir = Directory(_modelDir!);
    return dir.parent.path;
  }

  static const _espeakDataAssetKey =
      'packages/flutter_kokoro_tts/assets/espeak_ng_data.zip';

  /// Ensures espeak-ng-data exists under [kokoroBaseDir]. If not present,
  /// tries to extract from the package asset zip (when available).
  /// Does nothing if [kokoroBaseDir] is empty or if espeak-ng-data/phontab already exists.
  Future<void> ensureEspeakData() async {
    final base = kokoroBaseDir;
    if (base.isEmpty) return;
    final phontabPath = p.join(base, 'espeak-ng-data', 'phontab');
    if (File(phontabPath).existsSync()) return;
    try {
      final data = await rootBundle.load(_espeakDataAssetKey);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final targetDir = Directory(base);
      if (!targetDir.existsSync()) targetDir.createSync(recursive: true);
      for (final file in archive) {
        final name = file.name.replaceAll('\\', '/').trim();
        if (name.isEmpty) continue;
        final path = p.join(base, name);
        if (file.isFile) {
          final out = File(path);
          out.parent.createSync(recursive: true);
          out.writeAsBytesSync(file.content as List<int>);
        } else {
          Directory(path).createSync(recursive: true);
        }
      }
    } catch (_) {
      // Asset missing or invalid; phonemizer will throw with clear message
    }
  }

  Future<bool> isReady() async {
    final dir = await _getModelDir();
    final marker = File(p.join(dir.path, _readyMarker));

    if (!marker.existsSync()) return false;

    try {
      await _verifyHash(p.join(dir.path, 'model_quantized.onnx'));

      for (final entry in _voiceHashes.keys) {
        await _verifyHash(p.join(dir.path, 'voices', entry));
      }

      return true;
    } catch (_) {
      await marker.delete();
      await _deleteModelAndVoices(dir.path);
      return false;
    }
  }

  /// Removes the model and voice files so [download] will re-download them.
  Future<void> _deleteModelAndVoices(String dirPath) async {
    final modelFile = File(p.join(dirPath, 'model_quantized.onnx'));
    if (await modelFile.exists()) await modelFile.delete();

    final voiceDir = Directory(p.join(dirPath, 'voices'));
    if (await voiceDir.exists()) {
      await for (final entity in voiceDir.list()) {
        if (entity is File) await entity.delete();
      }
    }
  }

  Future<void> download({
    void Function(double progress, String status)? onProgress,
  }) async {
    final dir = await _getModelDir();
    _modelDir = dir.path;
    final marker = File(p.join(dir.path, _readyMarker));
    if (marker.existsSync()) {
      onProgress?.call(1.0, 'Ready');
      return;
    }

    // Download ONNX Model (file lives under onnx/ in the repo)
    await _downloadFile(
      url: '$_hfBase/onnx/model_quantized.onnx',
      destination: p.join(dir.path, 'model_quantized.onnx'),
      onProgress: (p) => onProgress?.call(p * 0.6, 'Downloading model...'),
    );

    // Download Voices
    final voices = [
      'af.bin',
      'af_bella.bin',
      'af_nicole.bin',
      'af_sarah.bin',
      'am_adam.bin',
      'am_michael.bin',
    ];

    final voiceDir = Directory(p.join(dir.path, 'voices'));
    if (!voiceDir.existsSync()) await voiceDir.create(recursive: true);

    for (int i = 0; i < voices.length; i++) {
      final voice = voices[i];
      await _downloadFile(
        url: '$_hfBase/voices/$voice',
        destination: p.join(voiceDir.path, voice),
        onProgress: (p) {
          final overall = 0.6 + ((i + p) / voices.length) * 0.4;
          onProgress?.call(overall, 'Downloading voice $voice...');
        },
      );
    }

    await marker.create();
    onProgress?.call(1.0, 'Ready');
  }

  Future<void> _downloadFile({
    required String url,
    required String destination,
    required void Function(double progress)? onProgress,
  }) async {
    final finalFile = File(destination);
    if (finalFile.existsSync()) return;

    final tempPath = '$destination.part';
    final tempFile = File(tempPath);

    final client = http.Client();

    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      final sink = tempFile.openWrite();

      var received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;

        if (total > 0) {
          onProgress?.call(received / total);
        }
      }

      await sink.close();

      if (total > 0 && received != total) {
        throw Exception('Incomplete download');
      }

      await tempFile.rename(destination);

      // 🔐 VERIFY HASH
      await _verifyHash(destination);
    } catch (e) {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> _verifyHash(String path) async {
    final fileName = p.basename(path);

    if (fileName == 'model_quantized.onnx') {
      await IntegrityVerifier.verify(path: path, expectedSha256: _modelSha256);
    } else if (_voiceHashes.containsKey(fileName)) {
      await IntegrityVerifier.verify(
        path: path,
        expectedSha256: _voiceHashes[fileName]!,
      );
    }
  }

  Future<Directory> _getModelDir() async {
    if (_modelDir != null) return Directory(_modelDir!);

    final appDir = await getApplicationDocumentsDirectory();
    final modelPath = p.join(appDir.path, 'kokoro', _modelDirName);
    final dir = Directory(modelPath);
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }
}
