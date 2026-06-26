import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:lms_player/core/errors/failures.dart';
import 'package:lms_player/core/constants/app_constants.dart';
import 'package:lms_player/core/entities/player_config.dart';
import 'package:lms_player/features/download/domain/repositories/download_repository.dart';

class DownloadRepositoryImpl implements DownloadRepository {
  @override
  Future<({PlayerConfig config, String packageDirPath})> loadExistingPackage(
      String tempDirPath) async {
    final extractDirPath = '$tempDirPath/${AppConstants.extractedDirName}';
    final extractDir = Directory(extractDirPath);
    if (!extractDir.existsSync()) {
      throw Exception('Package not found');
    }
    final config = await _parseConfig(extractDirPath);
    return (config: config, packageDirPath: extractDirPath);
  }

  @override
  Future<({PlayerConfig config, String packageDirPath})> downloadAndExtract({
    required String zipUrl,
    required String tempDirPath,
    void Function(double progress, String statusText)? onProgress,
  }) async {
    final zipPath = '$tempDirPath/${AppConstants.zipFileName}';
    final extractDirPath = '$tempDirPath/${AppConstants.extractedDirName}';

    onProgress?.call(0.0, 'Downloading package…');

    await _downloadZip(
      zipUrl: zipUrl,
      savePath: zipPath,
      onProgress: onProgress,
    );

    await _extractZip(
      zipPath: zipPath,
      extractDirPath: extractDirPath,
      onProgress: onProgress,
    );

    onProgress?.call(0.85, 'Reading config…');

    final config = await _parseConfig(extractDirPath);

    onProgress?.call(1.0, 'Ready');

    return (config: config, packageDirPath: extractDirPath);
  }

  Future<void> _downloadZip({
    required String zipUrl,
    required String savePath,
    void Function(double progress, String statusText)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(zipUrl));
      final streamedResponse = await client.send(request);
      if (streamedResponse.statusCode != 200) {
        throw DownloadFailure(
            'Download failed: HTTP ${streamedResponse.statusCode}');
      }

      final contentLength = streamedResponse.contentLength ?? -1;
      final file = File(savePath);
      final sink = file.openWrite();
      int bytesReceived = 0;

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        bytesReceived += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          final downloadProgress = bytesReceived / contentLength;
          onProgress(downloadProgress * 0.5,
              'Downloading… ${(downloadProgress * 100).toInt()}%');
        }
      }

      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
  }

  Future<void> _extractZip({
    required String zipPath,
    required String extractDirPath,
    void Function(double progress, String statusText)? onProgress,
  }) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final totalFiles = archive.length;

    final extractDir = Directory(extractDirPath);
    if (extractDir.existsSync()) {
      extractDir.deleteSync(recursive: true);
    }
    extractDir.createSync(recursive: true);

    int extracted = 0;
    for (final entry in archive) {
      final filePath = '$extractDirPath/${entry.name}';
      if (entry.isFile) {
        final file = File(filePath);
        file.createSync(recursive: true);
        await file.writeAsBytes(entry.content as List<int>);
      }
      extracted++;
      if (onProgress != null && totalFiles > 0) {
        final extractProgress = extracted / totalFiles;
        onProgress(0.5 + extractProgress * 0.35,
            'Extracting… ${(extractProgress * 100).toInt()}%');
      }
    }
  }

  Future<PlayerConfig> _parseConfig(String packageDirPath) async {
    final configFile = File('$packageDirPath/config.json');
    if (!configFile.existsSync()) {
      throw const ConfigParseFailure('config.json not found');
    }

    final contents = await configFile.readAsString();
    final json = jsonDecode(contents) as Map<String, dynamic>;

    final aes = json['aes'] as Map<String, dynamic>?;
    if (aes == null) throw const ConfigParseFailure('Missing aes block');

    final key = aes['key'] as String?;
    final iv = aes['iv'] as String?;
    final encryptedMedia = (json['encrypted_media'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        <String>[];

    if (key == null || iv == null) {
      throw const ConfigParseFailure('Missing key or iv in aes block');
    }

    return PlayerConfig(
      key: key,
      iv: iv,
      encryptedMedia: encryptedMedia,
    );
  }
}
