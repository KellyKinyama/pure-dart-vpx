import 'dart:io';
import 'dart:typed_data';

// import 'package:flutter/foundation.dart';
// import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
// import 'package:onnxruntime/onnxruntime.dart';
import '../onnx/onnx_runtime.dart';
import 'model_manager.dart';
import 'phonemizer.dart';
import 'text_cleaner.dart';
import 'text_preprocessor.dart';

const List<String> kokoroVoices = [
  'Default', // af.bin
  'Bella', // af_bella.bin
  'Nicole', // af_nicole.bin
  'Sarah', // af_sarah.bin
  'Adam', // am_adam.bin
  'Michael', // am_michael.bin
];

/// Map of voice names to their corresponding file names
const Map<String, String> _kokoroVoiceMap = {
  'Default': 'af.bin',
  'Bella': 'af_bella.bin',
  'Nicole': 'af_nicole.bin',
  'Sarah': 'af_sarah.bin',
  'Adam': 'am_adam.bin',
  'Michael': 'am_michael.bin',
};

const Map<String, double> _speedPriors = {
  'Default': 0.8,
  'Bella': 0.8,
  'Nicole': 0.8,
  'Sarah': 0.8,
  'Adam': 0.8,
  'Michael': 0.8,
};

class KokoroTts {
  final KokoroModelManager _modelManager = KokoroModelManager();
  final Phonemizer _phonemizer = Phonemizer();
  final TextCleaner _textCleaner = TextCleaner();
  final TextPreprocessor _textPreprocessor = TextPreprocessor();
  static const int _maxTokens = 500;

  OrtSession? _session;
  bool _isInitialized = false;
  Future<void>? _initializing;

  /// Output sample rate (always 24 000 Hz)
  int sampleRate = 24000;

  /// Name of available voices.
  List<String> get availableVoices => List.unmodifiable(kokoroVoices);

  /// Voice cache
  final Map<String, Float32List> _voiceCache = {};

  /// Initialize the Kokoro TTS engine.
  ///
  /// [espeakDataPath] Optional. Directory that contains espeak-ng-data (with
  /// phontab, etc.), or the espeak-ng-data directory itself. If null, uses
  /// the kokoro base dir (parent of the model dir); you must place
  /// espeak-ng-data there or pass a valid path. See README for obtaining data.
  Future<void> initialize({
    void Function(double progress, String status)? onProgress,
    String? espeakDataPath,
  }) {
    // If already initialized → return completed future
    if (_isInitialized) return Future.value();

    // If initialization is in progress → return same future
    if (_initializing != null) return _initializing!;

    _initializing = _doInitialize(onProgress, espeakDataPath);

    return _initializing!;
  }

  Future<void> _doInitialize(
    void Function(double progress, String status)? onProgress,
    String? espeakDataPath,
  ) async {
    try {
      onProgress?.call(0.0, 'Downloading model...');

      await _modelManager.download(
        onProgress: (p, status) {
          onProgress?.call(p, status);
        },
      );

      if (espeakDataPath == null) {
        onProgress?.call(0.9, 'Ensuring espeak-ng data...');
        await _modelManager.ensureEspeakData();
      }
      final dataPath = espeakDataPath ?? _modelManager.kokoroBaseDir;
      _phonemizer.initialize(dataPath: dataPath);

      onProgress?.call(0.97, 'Loading ONNX session...');
      final ort = OnnxRuntime();
      _session = await ort.createSession(_modelManager.modelPath);

      _isInitialized = true;
      onProgress?.call(1.0, 'Ready');
    } catch (e) {
      _initializing = null; // allow retry if failed
      rethrow;
    }
  }

  Future<Float32List> _getVoice(String voice) async {
    if (_voiceCache.containsKey(voice)) {
      return _voiceCache[voice]!;
    }

    final path = '${_modelManager.modelDir}/voices/${_kokoroVoiceMap[voice]!}';

    final bytes = await File(path).readAsBytes();
    final embedding = bytes.buffer.asFloat32List();

    _voiceCache[voice] = embedding;
    return embedding;
  }

  Future<Float32List> generate(
    String text, {
    String voice = 'Default',
    double speed = 1.0,
  }) async {
    if (text.trim().isEmpty) return Float32List(0);

    await initialize();

    if (!availableVoices.contains(voice)) {
      throw Exception('Invalid voice: $voice');
    }

    final chunks = _splitIntoChunks(text);
    final parts = <Float32List>[];

    for (final chunk in chunks) {
      final audio = await _generateChunk(chunk, voice: voice, speed: speed);
      if (audio.isNotEmpty) parts.add(audio);
    }

    if (parts.isEmpty) return Float32List(0);
    if (parts.length == 1) return parts.first;

    final total = parts.fold<int>(0, (sum, part) => sum + part.length);
    final result = Float32List(total);
    var offset = 0;
    for (final part in parts) {
      result.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return result;
  }

  Future<Float32List> _generateChunk(
    String chunk, {
    required String voice,
    required double speed,
  }) async {
    // --Text Cleaning & Preprocessing--
    final cleanText = _textPreprocessor.process(chunk);
    final cleanTextWithPunctuation = _addTrailingPunctuation(cleanText.trim());
    print('[kokoroTTS]: clean text: $cleanTextWithPunctuation');

    // --Phonemization--
    final phonemes = _phonemizer.phonemize(cleanTextWithPunctuation);
    print('[kokoroTTS]: phonemes: $phonemes');

    // --Encoding--
    final encodedTokens = _textCleaner.encodeAndWrap(phonemes);
    print('[kokoroTTS]: encoded: $encodedTokens');

    // -- Guard: split if tokens exceed model capacity --
    if (encodedTokens.length > _maxTokens) {
      print(
        '[kokoroTTS]: splitting chunk into multiple parts due to token limit',
      );
      final mid = encodedTokens.length ~/ 2;
      int splitAt = chunk.indexOf(RegExp(r'[.!?,;:\s]'), mid);
      if (splitAt < 0 || splitAt == chunk.length - 1) splitAt = mid;
      final firstHalf = chunk.substring(0, splitAt);
      final secondHalf = chunk.substring(splitAt);
      print('[kokoroTTS]: first half: $firstHalf');
      print('[kokoroTTS]: second half: $secondHalf');

      final parts = <Float32List>[];
      if (firstHalf.isNotEmpty) {
        parts.add(await _generateChunk(firstHalf, voice: voice, speed: speed));
      }
      if (secondHalf.isNotEmpty) {
        parts.add(await _generateChunk(secondHalf, voice: voice, speed: speed));
      }

      if (parts.isEmpty) return Float32List(0);
      if (parts.length == 1) return parts.first;

      final total = parts.fold<int>(0, (sum, part) => sum + part.length);
      final result = Float32List(total);
      var offset = 0;
      for (final part in parts) {
        result.setRange(offset, offset + part.length, part);
        offset += part.length;
      }
      return result;
    }

    // -- Voice: .bin files are (N, 256); model expects style [1, 256]. Pick row by token length.
    const styleDim = 256;
    final styleAll = await _getVoice(voice);
    final numVectors = styleAll.length ~/ styleDim;
    if (numVectors == 0) {
      throw Exception(
        'Voice file for "$voice" has no style vectors (expected multiple of $styleDim floats)',
      );
    }
    final tokenLen = encodedTokens.length.clamp(0, numVectors - 1);
    final style = Float32List.sublistView(
      styleAll,
      tokenLen * styleDim,
      (tokenLen + 1) * styleDim,
    );
    print(
      '[kokoroTTS]: style embedding: ${style.length} (row $tokenLen of $numVectors)',
    );

    // -- Speed Adjustment --
    final speedFactor = _speedPriors[voice]!;
    print('[kokoroTTS]: speed factor: $speedFactor');

    final effectiveSpeed = speed * speedFactor;

    // - ONNX inference --
    final inputIds = await OrtValue.fromList(
      Int64List.fromList(encodedTokens),
      [1, encodedTokens.length],
    );

    final styleTensor = await OrtValue.fromList(style, [1, styleDim]);

    final speedTensor = await OrtValue.fromList([effectiveSpeed], [1]);

    final outputs = await _session!.run({
      'input_ids': inputIds,
      'style': styleTensor,
      'speed': speedTensor,
    });

    // Dispose inputs
    await inputIds.dispose();
    await styleTensor.dispose();
    await speedTensor.dispose();

    // Find the audio output tensor (largest)

    OrtValue? audioOut;
    int audioLen = 0;
    for (final entry in outputs.entries) {
      final len = entry.value.shape.fold<int>(1, (a, b) => a * b);
      if (len > audioLen) {
        audioOut = entry.value;
        audioLen = len;
      }
    }

    if (audioOut == null) {
      return Float32List(0);
    }

    final rawList = await audioOut.asFlattenedList();

    // Dispose all output tensors
    for (final v in outputs.values) {
      await v.dispose();
    }

    Float32List audio;

    if (rawList is List<double>) {
      audio = Float32List.fromList(rawList.cast<double>());
    } else {
      audio = Float32List.fromList(
        rawList.map((e) => (e as num).toDouble()).toList(),
      );
    }

    // Trim trailing silence
    if (audio.length > 5000) {
      audio = Float32List.sublistView(audio, 0, audio.length - 5000);
    }

    print(
      '[kokoroTTS]: audio length: ${audio.length}, samples: ${audio.length ~/ 2}',
    );

    return audio;
  }

  // ── Helpers ──

  List<String> _splitIntoChunks(String text, {int maxLen = 200}) {
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    final chunks = <String>[];
    final buf = StringBuffer();

    for (final s in sentences) {
      final trimmed = s.trim();
      if (trimmed.isEmpty) continue;
      if (buf.length + trimmed.length + 1 > maxLen && buf.isNotEmpty) {
        chunks.add(_addTrailingPunctuation(buf.toString().trim()));
        buf.clear();
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(trimmed);
    }
    if (buf.isNotEmpty) {
      chunks.add(_addTrailingPunctuation(buf.toString().trim()));
    }
    return chunks.isEmpty ? [_addTrailingPunctuation(text.trim())] : chunks;
  }

  static String _addTrailingPunctuation(String t) {
    t = t.trim();
    if (t.isEmpty) return t;
    return '.!?,;:'.contains(t[t.length - 1]) ? t : '$t,';
  }

  // static String _trunc(String s, [int n = 60]) =>
  //     s.length <= n ? s : '${s.substring(0, n)}…';

  Future<void> dispose() async {
    if (!_isInitialized) return;

    // Dispose ONNX session
    if (_session != null) {
      await _session!.close();
      _session = null;
    }

    // Dispose phonemizer
    _phonemizer.dispose();

    // clear voice cache
    _voiceCache.clear();

    _isInitialized = false;
    _initializing = null;
  }
}
