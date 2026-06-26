import 'dart:ui';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:lms_player/core/entities/player_config.dart';

abstract class PlayerRepository {
  void Function(String filePath)? onPlayMedia;
  VoidCallback? onStopMedia;
  void Function(String error)? onError;

  WebViewController createController({
    required String packageDirPath,
    required PlayerConfig config,
  });

  Future<void> loadPlayer(
    WebViewController controller,
    String packageDirPath,
  );

  Future<void> injectBridge();

  Future<void> pauseMedia();

  Future<String> decryptMedia({
    required String src,
    required String packageDirPath,
    required PlayerConfig config,
  });

  Future<void> cleanupTempFile();

  Future<void> dispose();
}
