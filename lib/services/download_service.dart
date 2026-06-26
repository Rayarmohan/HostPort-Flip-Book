import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Handles downloading the player ZIP and extracting it to local storage.
///
/// Storage layout (inside app-private storage):
///   <appDocDir>/lms_player/
///     player.zip          ← downloaded archive
///     package/            ← extracted contents
///       index.html
///       config.json
///       media/
///         video.enc       ← encrypted media (stays encrypted on disk)
class DownloadService {
  static const String _playerZipUrl =
      'https://tech-lms.adurox.com/flutter/player.zip';

  static const String _packageDirName = 'package';
  static const String _zipFileName = 'player.zip';
  static const String _rootDirName = 'lms_player';

  final Dio _dio = Dio();

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Returns the extraction directory. Creates it if it doesn't exist.
  Future<Directory> get packageDir async {
    final base = await _baseDir;
    final dir = Directory('${base.path}/$_packageDirName');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Returns true if the package has already been downloaded and extracted.
  Future<bool> isPackageReady() async {
    final dir = await packageDir;
    final indexFile = File('${dir.path}/index.html');
    return indexFile.existsSync();
  }

  /// Downloads the ZIP and extracts it, reporting progress via [onProgress].
  ///
  /// [onProgress] receives a value between 0.0 and 1.0:
  ///   0.0–0.5  →  download phase
  ///   0.5–1.0  →  extraction phase
  Future<void> downloadAndExtract({
    void Function(double progress, String status)? onProgress,
  }) async {
    final base = await _baseDir;
    final zipFile = File('${base.path}/$_zipFileName');

    // ── Step 1: Download ───────────────────────────────────────────────────
    onProgress?.call(0.0, 'Starting download…');

    await _dio.download(
      _playerZipUrl,
      zipFile.path,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final progress = (received / total) * 0.5; // first half
          final mb = (received / 1024 / 1024).toStringAsFixed(1);
          onProgress?.call(progress, 'Downloading… $mb MB');
        }
      },
      options: Options(
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(seconds: 30),
      ),
    );

    onProgress?.call(0.5, 'Download complete. Extracting…');

    // ── Step 2: Extract ────────────────────────────────────────────────────
    final extractDir = await packageDir;

    // Clear any previous extraction
    if (extractDir.existsSync()) {
      await extractDir.delete(recursive: true);
    }
    await extractDir.create(recursive: true);

    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final total = archive.files.length;

    for (var i = 0; i < total; i++) {
      final file = archive.files[i];
      final extractPath = '${extractDir.path}/${file.name}';

      if (file.isFile) {
        final outFile = File(extractPath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(extractPath).create(recursive: true);
      }

      final progress = 0.5 + ((i + 1) / total) * 0.5;
      onProgress?.call(progress, 'Extracting… ${i + 1}/$total files');
    }

    // ── Step 3: Cleanup ────────────────────────────────────────────────────
    // Delete the ZIP to free space; the encrypted media stays encrypted on disk.
    if (zipFile.existsSync()) await zipFile.delete();

    onProgress?.call(1.0, 'Ready!');
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  Future<Directory> get _baseDir async {
    final appDoc = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDoc.path}/$_rootDirName');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }
}
