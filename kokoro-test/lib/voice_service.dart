import 'dart:io';
import 'dart:typed_data';
// import 'package:flutter_kokoro_tts/flutter_kokoro_tts.dart';
import 'package:path_provider/path_provider.dart';

import 'kokoro_test.dart';
import 'package:test/test.dart';

class KokoroVoiceService {
  final KokoroTts _tts = KokoroTts();
  bool _isInitialized = false;

  /// Initialize the engine (call this during app splash/startup)
  Future<void> init() async {
    if (_isInitialized) return;
    await _tts.initialize(
      onProgress: (progress, status) =>
          print('TTS Init: $status ${(progress * 100).round()}%'),
    );
    _isInitialized = true;
  }

  /// Converts a string (e.g., from Oracle) to a playable .wav file
  Future<File> synthesizeToWav(String text, {String voice = 'Bella'}) async {
    if (!_isInitialized) await init();

    // 1. Generate Raw PCM (Float32, 24kHz)
    final Float32List rawPcm = await _tts.generate(text, voice: voice);

    // 2. Convert to WAV Bytes
    final Uint8List wavBytes = _buildWavHeader(rawPcm, 24000);

    // 3. Save to temporary storage
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/speech_output.wav');
    return await file.writeAsBytes(wavBytes);
  }

  /// Minimal WAV Header Builder (PCM 16-bit Mono)
  Uint8List _buildWavHeader(Float32List pcmData, int sampleRate) {
    final int frameCount = pcmData.length;
    final int byteCount = frameCount * 2; // 16-bit = 2 bytes per sample
    final byteData = ByteData(44 + byteCount);

    // RIFF header
    byteData.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    byteData.setUint32(4, 36 + byteCount, Endian.little);
    byteData.setUint32(8, 0x57415645, Endian.big); // "WAVE"

    // fmt chunk
    byteData.setUint32(12, 0x666d7420, Endian.big); // "fmt "
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size
    byteData.setUint16(20, 1, Endian.little); // AudioFormat (PCM)
    byteData.setUint16(22, 1, Endian.little); // NumChannels (Mono)
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
    byteData.setUint16(32, 2, Endian.little); // BlockAlign
    byteData.setUint16(34, 16, Endian.little); // BitsPerSample

    // data chunk
    byteData.setUint32(36, 0x64617461, Endian.big); // "data"
    byteData.setUint32(40, byteCount, Endian.little);

    // Convert Float32 (-1.0 to 1.0) to Int16 (-32768 to 32767)
    for (int i = 0; i < frameCount; i++) {
      int sample = (pcmData[i] * 32767).clamp(-32768, 32767).toInt();
      byteData.setInt16(44 + (i * 2), sample, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }

  void dispose() => _tts.dispose();
}

// import 'dart:io';
// import 'dart:typed_data';
// import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';

// void main() async {
//   print('--- ZESCO CCIVR V2: Voice Engine (Console Mode) ---');

//   // 1. Configure paths to your local model files
//   // No "assets" folder required, just absolute paths on your Windows/Linux server
//   final config = KokoroConfig(
//     modelPath: 'C:/zesco_tts/assets/kokoro-v1.0.onnx',
//     voicesPath: 'C:/zesco_tts/assets/voices.json',
//   );

//   final kokoro = Kokoro(config);

//   try {
//     print('Loading ONNX Runtime and Model...');
//     await kokoro.initialize();

//     // 2. Define the Oracle message
//     String message = "Your ZESCO balance is four hundred and fifty Kwacha.";
//     print('Synthesizing: "$message"');

//     // 3. Generate Audio
//     // This returns a Float32List (24kHz Mono)
//     final audio = await kokoro.generate(
//       message,
//       voice: 'af_bella', // Use the internal voice key
//       speed: 1.0,
//     );

//     // 4. Convert to Int16 and Save to File
//     // Since this is a console app, we save it so the PBX/IVR can pick it up
//     final file = File('output_voice.raw');
//     final pcmBytes = _convertTo16BitPCM(audio);
//     await file.writeAsBytes(pcmBytes);

//     print('Success! Audio saved to ${file.absolute.path}');
//     print('Format: 24kHz, 16-bit PCM, Mono');
//   } catch (e) {
//     print('Critical Error: $e');
//   } finally {
//     exit(0);
//   }
// }

/// Simple conversion from Float32 (-1.0 to 1.0) to Int16 Bytes
Uint8List _convertTo16BitPCM(Float32List floatList) {
  final intList = Int16List(floatList.length);
  for (int i = 0; i < floatList.length; i++) {
    intList[i] = (floatList[i] * 32767).clamp(-32768, 32767).toInt();
  }
  return intList.buffer.asUint8List();
}

// import 'dart:io';
// import 'dart:typed_data';
// import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';

// import 'package:test/test.dart';
// import 'package:flutter_kokoro_tts/flutter_kokoro_tts.dart';

void main() {
  // NOTE: In pure Dart console, we don't call TestWidgetsFlutterBinding.
  // We rely on standard Dart environment initialization.

  group('KokoroTts Console Unit Tests', () {
    test('exposes availableVoices and sampleRate', () {
      final tts = KokoroTts();
      expect(tts.availableVoices, isNotEmpty);
      expect(tts.availableVoices, contains('Default'));
      expect(tts.sampleRate, 24000);
    });

    test('availableVoices are unique and non-empty', () {
      final tts = KokoroTts();
      final uniqueVoices = tts.availableVoices.toSet();
      expect(uniqueVoices.length, tts.availableVoices.length);
      for (final voice in tts.availableVoices) {
        expect(voice.isNotEmpty, isTrue);
      }
    });

    test(
      'generate with empty string returns empty audio without initializing',
      () async {
        final tts = KokoroTts();
        // This is a safe test because it returns early before hitting Flutter-specific code
        final audio = await tts.generate('');
        expect(audio, isEmpty);
      },
    );

    test('generate with whitespace-only string returns empty audio', () async {
      final tts = KokoroTts();
      final audio = await tts.generate('   \n\t   ');
      expect(audio, isEmpty);
    });

    test('dispose does not throw when not initialized', () async {
      final tts = KokoroTts();
      await expectLater(tts.dispose(), completes);
    });

    test('all expected ZESCO-standard voices are present', () {
      final tts = KokoroTts();
      const expected = [
        'Default',
        'Bella',
        'Nicole',
        'Sarah',
        'Adam',
        'Michael',
      ];
      for (final name in expected) {
        expect(tts.availableVoices, contains(name));
      }
    });

    // We keep this skipped because console environments often lack the
    // binary dependencies (ONNX Runtime) required for the actual model run.
    test(
      'generate with invalid voice throws Exception',
      () async {
        final tts = KokoroTts();
        await expectLater(
          tts.generate('ZESCO Test', voice: 'InvalidVoice'),
          throwsA(predicate((e) => e.toString().contains('Invalid voice'))),
        );
      },
      skip: 'Requires native ONNX binaries and model files',
    );
  });
}
