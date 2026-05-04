import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _EspeakInitializeC =
    Int32 Function(
      Int32 output,
      Int32 buflength,
      Pointer<Utf8> path,
      Int32 options,
    );

typedef _EspeakInitializeDart =
    int Function(int output, int buflength, Pointer<Utf8> path, int options);

typedef _EspeakSetVoiceByNameC = Int32 Function(Pointer<Utf8> name);

typedef _EspeakSetVoiceByNameDart = int Function(Pointer<Utf8> name);

typedef _EspeakTextToPhonemesC =
    Pointer<Utf8> Function(
      Pointer<Pointer<Void>> textptr,
      Int32 textmode,
      Int32 phonememode,
    );

typedef _EspeakTextToPhonemesDart =
    Pointer<Utf8> Function(
      Pointer<Pointer<Void>> textptr,
      int textmode,
      int phonememode,
    );

typedef _EspeakTerminateC = Int32 Function();

typedef _EspeakTerminateDart = int Function();

/// Low-level FFI wrapper around the espeak-ng C library.
class EspeakFfi {
  DynamicLibrary? _lib;
  _EspeakInitializeDart? _espeakInitialize;
  _EspeakSetVoiceByNameDart? _espeakSetVoiceByName;
  _EspeakTextToPhonemesDart? _espeakTextToPhonemes;
  _EspeakTerminateDart? _espeakTerminate;

  bool _loaded = false;
  bool _ready = false;
  bool get isReady => _ready;

  void load() {
    if (_loaded) return;
    if (Platform.isIOS || Platform.isMacOS) {
      _lib = DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libespeak-ng.so');
    } else if (Platform.isLinux) {
      _lib = DynamicLibrary.open('libespeak-ng.so');
    } else if (Platform.isWindows) {
      _lib = DynamicLibrary.open('espeak-ng.dll');
    } else {
      throw UnsupportedError(
        'Unsupported platform: ${Platform.operatingSystem}',
      );
    }

    _espeakInitialize = _lib!
        .lookupFunction<_EspeakInitializeC, _EspeakInitializeDart>(
          'espeak_Initialize',
        );
    _espeakSetVoiceByName = _lib!
        .lookupFunction<_EspeakSetVoiceByNameC, _EspeakSetVoiceByNameDart>(
          'espeak_SetVoiceByName',
        );
    _espeakTextToPhonemes = _lib!
        .lookupFunction<_EspeakTextToPhonemesC, _EspeakTextToPhonemesDart>(
          'espeak_TextToPhonemes',
        );
    _espeakTerminate = _lib!
        .lookupFunction<_EspeakTerminateC, _EspeakTerminateDart>(
          'espeak_Terminate',
        );
    _loaded = true;
  }

  // Initialize the espeak-ng library with the path to the directory containing the espeak-ng-data directory
  void init({required String dataPath}) {
    final pathPtr = dataPath.toNativeUtf8();
    try {
      // AUDIO_OUTPUT_RETRIEVAL = 0x002, DONT_EXIT = 0X8000
      final result = _espeakInitialize!(0x002, 0, pathPtr, 0x8000);
      if (result < 0) {
        throw Exception('Failed to initialize espeak-ng: $result');
      }
      final voicePtr = 'en-us'.toNativeUtf8();
      try {
        final result = _espeakSetVoiceByName!(voicePtr);
        if (result < 0) {
          throw Exception('Failed to set voice: $result');
        }
      } finally {
        calloc.free(voicePtr);
      }
      _ready = true;
    } finally {
      calloc.free(pathPtr);
    }
  }

  String phonemize(String text) {
    if (!_ready) throw Exception('Espeak-ng not initialized');
    final textPtr = text.toNativeUtf8();
    final ptrToPtr = calloc<Pointer<Void>>();
    ptrToPtr.value = textPtr.cast<Void>();
    try {
      final buffer = StringBuffer();

      while (true) {
        // textmode = 1 (UTF-8), phonemode = 0x02 (IPA)
        final phonemesPtr = _espeakTextToPhonemes!(ptrToPtr, 1, 0x02);
        if (phonemesPtr == nullptr) break;
        final phonemes = phonemesPtr.toDartString();
        if (phonemes.isEmpty) break;
        buffer.write(phonemes);
        buffer.write(' ');
      }
      return buffer.toString().trim();
    } finally {
      calloc.free(ptrToPtr);
      calloc.free(textPtr);
    }
  }

  void dispose() {
    if (_ready) {
      _espeakTerminate!.call();
      _ready = false;
    }
  }
}
