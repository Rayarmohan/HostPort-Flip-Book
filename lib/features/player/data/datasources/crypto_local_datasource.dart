import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/export.dart';

class CryptoLocalDataSource {
  Future<String> decryptToTemp({
    required File encryptedFile,
    required String hexKey,
    required String hexIv,
    required Directory tempDir,
  }) async {
    final keyBytes = _parseKey(hexKey);
    final ivBytes = Uint8List.fromList(hex.decode(hexIv));

    final encryptedBytes = await encryptedFile.readAsBytes();

    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(keyBytes), ivBytes));

    final decrypted = _processCipher(cipher, encryptedBytes);
    final unpad = _removePkcs7Padding(decrypted);

    final tempFile = File('${tempDir.path}/${encryptedFile.uri.pathSegments.last}');
    await tempFile.writeAsBytes(unpad);
    return tempFile.path;
  }

  Uint8List _parseKey(String hexKey) {
    final raw = hex.decode(hexKey);
    if (raw.length == 32) return Uint8List.fromList(raw);
    if (raw.length == 64) {
      return Uint8List.fromList(hex.decode(
          String.fromCharCodes(raw.map((e) => e))));
    }
    throw ArgumentError('Unexpected key length: ${raw.length} bytes');
  }

  Uint8List _processCipher(CBCBlockCipher cipher, Uint8List input) {
    final blockSize = cipher.blockSize;
    final output = Uint8List(input.length);
    var offset = 0;
    while (offset <= input.length - blockSize) {
      offset += cipher.processBlock(input, offset, output, offset);
    }
    return output;
  }

  Uint8List _removePkcs7Padding(Uint8List data) {
    if (data.isEmpty) return data;
    final padLen = data.last;
    if (padLen < 1 || padLen > 32) return data;
    return data.sublist(0, data.length - padLen);
  }

  Future<void> secureDelete(String path) async {
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}
