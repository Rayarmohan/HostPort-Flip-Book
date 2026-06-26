import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:lms_player/features/player/data/datasources/crypto_local_datasource.dart';

class WebViewDataSource {
  WebViewController? _controller;

  WebViewController? get controller => _controller;
  final CryptoLocalDataSource _crypto = CryptoLocalDataSource();
  String? _currentTempFile;

  /// Called when an encrypted media file is ready for native playback.
  void Function(String filePath)? onPlayMedia;

  /// Called when the WebView page has finished loading.
  VoidCallback? onPageLoaded;

  /// Called on any WebView error.
  void Function(String error)? onError;

  /// Called when the JS bridge sends a debug message.
  void Function(String message)? onDebugMessage;

  WebViewController createController() {
    final controller = WebViewController();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (message) =>
            _handleJsMessage(message.message, controller),
      )
      ..addJavaScriptChannel(
        'LMSDebug',
        onMessageReceived: (message) =>
            onDebugMessage?.call(message.message),
      );

    _controller = controller;
    return controller;
  }

  Future<void> loadPlayer(
    WebViewController controller,
    String indexPath,
  ) async {
    final indexFile = File(indexPath);
    if (!indexFile.existsSync()) {
      throw StateError('index.html not found at $indexPath');
    }
    if (Platform.isAndroid) {
      await controller.loadFile(indexPath);
    } else {
      await controller.loadRequest(Uri.file(indexPath));
    }
  }

  Future<void> injectBridge() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.runJavaScript('''
        (function() {
          var originalOpenMediaModal = window.openMediaModal;
          var originalCloseMediaModal = window.closeMediaModal;

          if (typeof originalOpenMediaModal !== 'function') {
            FlutterChannel.postMessage(JSON.stringify({action:"debug",msg:"bridge_abort no openMediaModal"}));
            return;
          }
          window._pendingModal = null;

          function stopModalMedia() {
            var modal = document.getElementById('mediaModal');
            if (modal) {
              modal.querySelectorAll('video, audio').forEach(function(el) {
                el.pause();
                el.src = '';
                el.load();
              });
              var content = document.getElementById('modalContent');
              if (content) content.innerHTML = '';
            }
          }

          var modalEl = document.getElementById('mediaModal');
          if (modalEl) {
            var observer = new MutationObserver(function() {
              if (!modalEl.classList.contains('open')) {
                stopModalMedia();
              }
            });
            observer.observe(modalEl, { attributes: true, attributeFilter: ['class'] });
          }

          window.openMediaModalOriginal = originalOpenMediaModal;

          window.openMediaModal = function(type, title, src, fallback) {
            FlutterChannel.postMessage(JSON.stringify({action:"openMediaModal",type:type,title:title,src:src,fallback:fallback}));
          };

          window._onDecrypted = function(src, fileUrl) {
            if (window._pendingModal) {
              var p = window._pendingModal;
              window._pendingModal = null;
              originalOpenMediaModal(p.type, p.title, fileUrl, p.fallback);
              setTimeout(function() {
                var el = document.getElementById('videoPlayer');
                if (el) { el.muted = true; el.play().catch(function(e) {}); }
              }, 100);
            }
          };

          window._onDecryptError = function(src, errorMsg) {
            window._pendingModal = null;
            var el = document.getElementById('modalContent');
            if (el) el.innerHTML = '<p style="color:red;padding:20px">[LMS Error] ' + errorMsg + '</p>';
          };

          window.closeMediaModal = function() {
            stopModalMedia();
            if (typeof originalCloseMediaModal === 'function') originalCloseMediaModal();
          };

          document.addEventListener('pagehide', function() {
            document.querySelectorAll('video, audio').forEach(function(el) { el.pause(); });
          });
          document.addEventListener('visibilitychange', function() {
            if (document.hidden) {
              document.querySelectorAll('video, audio').forEach(function(el) { el.pause(); });
            }
          });

          FlutterChannel.postMessage(JSON.stringify({action:"debug",msg:"bridge_ok"}));
        })();
      ''');
    } catch (e) {
      onError?.call('injectBridge: $e');
    }
  }

  Future<void> pauseMedia() async {
    await _controller?.runJavaScript('''
      (function() {
        document.querySelectorAll('video, audio').forEach(function(el) {
          el.pause();
        });
        if (navigator.mediaSession) {
          navigator.mediaSession.playbackState = 'paused';
        }
      })();
    ''');
    if (Platform.isAndroid) {
      await _controller?.runJavaScript('window.onblur && window.onblur();');
    }
  }

  Future<String> decryptMedia({
    required String src,
    required String packageDirPath,
    required String hexKey,
    required String hexIv,
  }) async {
    await _cleanupTempFile();

    final encryptedFile = File('$packageDirPath/$src');
    if (!encryptedFile.existsSync()) {
      throw Exception('Encrypted file not found: $src');
    }

    final tempDir = Directory('$packageDirPath/_temp');
    if (!tempDir.existsSync()) await tempDir.create(recursive: true);

    final tempPath = await _crypto.decryptToTemp(
      encryptedFile: encryptedFile,
      hexKey: hexKey,
      hexIv: hexIv,
      tempDir: tempDir,
    );
    _currentTempFile = tempPath;
    return tempPath;
  }

  Future<void> _cleanupTempFile() async {
    if (_currentTempFile != null) {
      await _crypto.secureDelete(_currentTempFile!);
      _currentTempFile = null;
    }
  }

  Future<void> cleanupTempFile() => _cleanupTempFile();

  Future<void> dispose() async {
    await pauseMedia();
    await _cleanupTempFile();
  }

  void _handleJsMessage(String message, WebViewController controller) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final action = data['action'] as String?;

      switch (action) {
        case 'openMediaModal':
          final src = data['src'] as String? ?? '';
          final type = data['type'] as String? ?? 'video';
          final title = data['title'] as String? ?? 'Media';
          final fallback = data['fallback'] as String? ?? '';
          onOpenMediaModal?.call(src, type, title, fallback);
          break;
        case 'debug':
          onDebugMessage?.call(data['msg'] as String? ?? '');
          break;
        default:
          break;
      }
    } catch (_) {}
  }

  /// Called when the JS bridge intercepts an openMediaModal call.
  /// Parameters: (src, type, title, fallback)
  void Function(String src, String type, String title, String fallback)?
      onOpenMediaModal;
}
