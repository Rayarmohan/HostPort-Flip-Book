import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/export.dart';

/// Handles runtime AES-CBC decryption of encrypted media files.
///
/// Security model:
/// ─────────────────────────────────────────────────────────────────────────────
/// • Encrypted files live on disk permanently (never stored decrypted).
/// • Decryption happens entirely in memory at playback time.
/// • The decrypted bytes are written to a TEMP file that is:
///     – located in the OS temp directory (not app documents)
///     – deleted immediately after the player is dismissed
/// • No decryption key is ever written to disk.
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Supported: AES-128/256 CBC with PKCS7 padding.
/// The [key] and [iv] are expected as lowercase hex strings.
/// If [iv] is null, the first 16 bytes of the file are treated as the IV
/// (a common convention for self-contained encrypted blobs).
class CryptoService {
  // ── Public API ──────────────────────────────────────────────────────────────

  /// Decrypts [encryptedFile] in memory and writes the plaintext to a temp
  /// file. Returns the path of the temp file.
  ///
  /// [tempDir] specifies the output directory; defaults to system temp.
  /// Caller is responsible for deleting the temp file after use.
  Future<String> decryptToTemp({
    required File encryptedFile,
    required String hexKey,
    String? hexIv,
    Directory? tempDir,
  }) async {
    final encryptedBytes = await encryptedFile.readAsBytes();

    Uint8List iv;
    Uint8List ciphertext;

    if (hexIv != null && hexIv.isNotEmpty) {
      iv = Uint8List.fromList(hex.decode(hexIv));
      ciphertext = encryptedBytes;
    } else {
      // IV prepended: first 16 bytes are the IV
      iv = encryptedBytes.sublist(0, 16);
      ciphertext = encryptedBytes.sublist(16);
    }

    final keyBytes = Uint8List.fromList(hex.decode(hexKey));
    final decrypted = _aesCbcDecrypt(keyBytes, iv, ciphertext);

    // Write to a temp file
    final outDir = tempDir ?? await Directory.systemTemp.createTemp('lms_');
    final ext = _extensionFromName(encryptedFile.path);
    final tempFile = File('${outDir.path}/decrypted$ext');
    await tempFile.writeAsBytes(decrypted);

    return tempFile.path;
  }

  /// Deletes the decrypted temp file securely (overwrites with zeros first).
  Future<void> secureDelete(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) return;

    // Overwrite with zeros before deleting to reduce forensic recovery risk.
    final length = await file.length();
    await file.writeAsBytes(List.filled(length, 0));
    await file.delete();

    // Also try to delete the parent temp dir
    try {
      await file.parent.delete(recursive: true);
    } catch (_) {}
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  Uint8List _aesCbcDecrypt(
      Uint8List key, Uint8List iv, Uint8List ciphertext) {
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );

    cipher.init(
      false, // decrypt
      PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
        null,
      ),
    );

    return cipher.process(ciphertext);
  }

  String _extensionFromName(String path) {
    final name = path.split('/').last.split('\\').last;
    final dotIdx = name.lastIndexOf('.');
    if (dotIdx < 0) return '';
    // Strip .enc if present; return the real extension underneath
    var ext = name.substring(dotIdx);
    if (ext == '.enc') {
      final withoutEnc = name.substring(0, dotIdx);
      final secondDot = withoutEnc.lastIndexOf('.');
      return secondDot >= 0 ? withoutEnc.substring(secondDot) : '';
    }
    return ext;
  }
}
