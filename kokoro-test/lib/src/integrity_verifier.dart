import 'dart:io';
import 'package:crypto/crypto.dart';

class IntegrityVerifier {
  static Future<void> verify({
    required String path,
    required String expectedSha256,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('File not found: $path');
    }

    final digest = await sha256.bind(file.openRead()).first;
    final actual = digest.toString();

    if (actual != expectedSha256) {
      await file.delete();
      throw Exception(
        'SHA256 mismatch for $path\nExpected: $expectedSha256\nActual:   $actual',
      );
    }
  }
}
