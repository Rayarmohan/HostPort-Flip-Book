import 'dart:io';

import 'package:archive/archive.dart';

class ExtractLocalDataSource {
  Future<String> extractZip({
    required String zipPath,
    required String extractDirPath,
  }) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final extractDir = Directory(extractDirPath);
    if (extractDir.existsSync()) {
      extractDir.deleteSync(recursive: true);
    }
    extractDir.createSync(recursive: true);

    for (final entry in archive) {
      final filePath = '$extractDirPath/${entry.name}';
      if (entry.isFile) {
        final file = File(filePath);
        file.createSync(recursive: true);
        await file.writeAsBytes(entry.content as List<int>);
      }
    }

    return extractDirPath;
  }
}
