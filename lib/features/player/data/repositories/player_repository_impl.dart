import 'dart:ui';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:lms_player/core/entities/player_config.dart';
import 'package:lms_player/features/player/domain/repositories/player_repository.dart';
import 'package:lms_player/features/player/data/datasources/webview_datasource.dart';

class PlayerRepositoryImpl implements PlayerRepository {
  final WebViewDataSource _dataSource;

  PlayerRepositoryImpl({required WebViewDataSource dataSource})
      : _dataSource = dataSource;

  @override
  void Function(String filePath)? get onPlayMedia => _dataSource.onPlayMedia;

  @override
  set onPlayMedia(void Function(String filePath)? cb) {
    _dataSource.onPlayMedia = cb;
  }

  @override
  VoidCallback? get onStopMedia => null;

  @override
  set onStopMedia(VoidCallback? cb) {}

  @override
  void Function(String error)? get onError => _dataSource.onError;

  @override
  set onError(void Function(String error)? cb) {
    _dataSource.onError = cb;
  }

  void Function(String src, String type, String title, String fallback)?
      get onOpenMediaModal => _dataSource.onOpenMediaModal;

  set onOpenMediaModal(
      void Function(String src, String type, String title, String fallback)?
          cb) {
    _dataSource.onOpenMediaModal = cb;
  }

  VoidCallback? get onPageLoaded => _dataSource.onPageLoaded;

  set onPageLoaded(VoidCallback? cb) {
    _dataSource.onPageLoaded = cb;
  }

  @override
  WebViewController createController({
    required String packageDirPath,
    required PlayerConfig config,
  }) {
    return _dataSource.createController();
  }

  @override
  Future<void> loadPlayer(
    WebViewController controller,
    String packageDirPath,
  ) async {
    await _dataSource.loadPlayer(controller, '$packageDirPath/index.html');
  }

  @override
  Future<void> injectBridge() async {
    await _dataSource.injectBridge();
  }

  @override
  Future<void> pauseMedia() async {
    await _dataSource.pauseMedia();
  }

  @override
  Future<String> decryptMedia({
    required String src,
    required String packageDirPath,
    required PlayerConfig config,
  }) async {
    return _dataSource.decryptMedia(
      src: src,
      packageDirPath: packageDirPath,
      hexKey: config.key,
      hexIv: config.iv,
    );
  }

  @override
  Future<void> cleanupTempFile() async {
    await _dataSource.cleanupTempFile();
  }

  @override
  Future<void> dispose() async {
    await _dataSource.dispose();
  }
}
