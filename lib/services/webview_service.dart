import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/player_config.dart';
import 'crypto_service.dart';
import 'local_media_server.dart';

/// Manages the [WebViewController] lifecycle and the JavaScript bridge between
/// Flutter and the player's index.html.
///
/// JavaScript → Flutter messages use postMessage with a JSON payload:
///   { "action": "decryptAndPlay", "src": "media/video/video2.mp4" }
///   { "action": "mediaEnded" }
///
/// Flutter → JavaScript calls:
///   window._onDecrypted(src, fileUrl)
///   window._onDecryptError(src, errorMsg)
class WebViewService {
  WebViewController? _controller;
  PlayerConfig? _config;
  String? _packageDirPath;
  final CryptoService _crypto = CryptoService();

  /// Temp file path for the currently decrypted media (if any).
  String? _currentTempFile;

  /// Local HTTP server serving the decrypted media.
  final LocalMediaServer _mediaServer = LocalMediaServer();

  // ── Setup ────────────────────────────────────────────────────────────────

  WebViewController createController({
    required String packageDirPath,
    required PlayerConfig config,
    required void Function(String error) onError,
  }) {
    _packageDirPath = packageDirPath;
    _config = config;

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
            // ignore: avoid_print
            print('[LMS:JS] ${message.message}'),
      );

    _controller = controller;
    return controller;
  }

  Future<void> loadPlayer(
      WebViewController controller, String packageDirPath) async {
    final indexPath = '$packageDirPath/index.html';
    final indexFile = File(indexPath);

    if (!indexFile.existsSync()) {
      throw StateError('index.html not found at $indexPath');
    }

    if (Platform.isAndroid) {
      await controller.loadFile(indexPath);
    } else {
      final uri = Uri.file(indexPath);
      await controller.loadRequest(uri);
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

  Future<void> resumeMedia() async {}

  /// Called when a decrypted media file is ready for native playback.
  void Function(String filePath)? onPlayMedia;

  /// Called when native playback should stop.
  VoidCallback? onStopMedia;

  Future<void> dispose() async {
    await pauseMedia();
    await _cleanupTempFile();
    await _mediaServer.stop();
  }

  // ── JavaScript bridge ────────────────────────────────────────────────────

  /// Injects the JavaScript bridge into the WebView page.
  /// Called from [PlayerScreen]'s onPageFinished callback.
  Future<void> injectBridge(WebViewController controller) async {
    await _injectBridge(controller);
  }

  Future<void> _injectBridge(WebViewController controller) async {
    // ignore: avoid_print
    print('[LMS] _injectBridge called');
    final encryptedFilesJson =
        jsonEncode(_config?.encryptedMedia ?? <String>[]);

    try {
      await controller.runJavaScript('''
        (function() {
          var encryptedFiles = $encryptedFilesJson;
          var originalOpenMediaModal = window.openMediaModal;
          var originalCloseMediaModal = window.closeMediaModal;

          if (typeof originalOpenMediaModal !== 'function') {
            FlutterChannel.postMessage(JSON.stringify({action:"debug",msg:"bridge_abort no openMediaModal"}));
            return;
          }
          window._pendingModal = null;

          // ── Media cleanup: stop every video/audio in the modal ──
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

          // ── MutationObserver: clean up whenever modal closes ──
          var modalEl = document.getElementById('mediaModal');
          if (modalEl) {
            var observer = new MutationObserver(function() {
              if (!modalEl.classList.contains('open')) {
                stopModalMedia();
              }
            });
            observer.observe(modalEl, { attributes: true, attributeFilter: ['class'] });
          }

          // ── Intercept encrypted media opens ──
          window.openMediaModal = function(type, title, src, fallback) {
            var isEnc = src && encryptedFiles.indexOf(src) !== -1;
            FlutterChannel.postMessage(JSON.stringify({action:"debug",msg:"click enc=" + isEnc + " src=" + src}));
            if (isEnc) {
              window._pendingModal = { type: type, title: title, fallback: fallback };
              var mt = document.getElementById('modalTitle');
              if (mt) mt.textContent = title;
              var mc = document.getElementById('modalContent');
              if (mc) mc.innerHTML = '<p style="padding:20px;text-align:center">Decrypting video\u2026</p>';
              var modal = document.getElementById('mediaModal');
              if (modal) { modal.classList.add('open'); modal.setAttribute('aria-hidden', 'false'); }
              FlutterChannel.postMessage(JSON.stringify({ action: "decryptAndPlay", src: src }));
              return;
            }
            originalOpenMediaModal(type, title, src, fallback);
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

          // ── Explicit close handler (for Flutter calls via runJavaScript) ──
          window.closeMediaModal = function() {
            stopModalMedia();
            if (typeof originalCloseMediaModal === 'function') originalCloseMediaModal();
          };

          // ── Pause all media when page is hidden / navigated away ──
          document.addEventListener('pagehide', function() {
            document.querySelectorAll('video, audio').forEach(function(el) { el.pause(); });
          });
          document.addEventListener('visibilitychange', function() {
            if (document.hidden) {
              document.querySelectorAll('video, audio').forEach(function(el) { el.pause(); });
            }
          });

          FlutterChannel.postMessage(JSON.stringify({action:"debug",msg:"bridge_ok encrypted=" + JSON.stringify(encryptedFiles)}));
        })();
      ''');
      // ignore: avoid_print
      print('[LMS] runJavaScript completed');
    } catch (e) {
      // ignore: avoid_print
      print('[LMS] runJavaScript error: $e');
    }
  }

  Future<void> _handleJsMessage(
      String message, WebViewController controller) async {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final action = data['action'] as String?;

      switch (action) {
        case 'decryptAndPlay':
          final src = data['src'] as String?;
          await _handleDecryptAndPlay(src, controller);
          break;
        case 'mediaEnded':
          await _cleanupTempFile();
          break;
        case 'debug':
          // ignore: avoid_print
          print('[LMS:JS] ${data['msg']}');
          break;
        default:
          break;
      }
    } catch (e) {
      // Malformed message — ignore
    }
  }

  Future<void> _handleDecryptAndPlay(
      String? src, WebViewController controller) async {
    // ignore: avoid_print
    print('[LMS] _handleDecryptAndPlay src=$src');
    if (src == null || _config == null || _packageDirPath == null) {
      await controller.runJavaScript(
          "window._onDecryptError('$src', 'Missing config or path');");
      return;
    }

    if (!_config!.isEncrypted(src)) {
      await controller.runJavaScript(
          "window._onDecryptError('$src', 'File not in encrypted list');");
      return;
    }

    await _cleanupTempFile();

    final encryptedFile = File('$_packageDirPath/$src');
    if (!encryptedFile.existsSync()) {
      await controller.runJavaScript(
          "window._onDecryptError('$src', 'Encrypted file not found');");
      return;
    }

    try {
      final tempDir = Directory('$_packageDirPath/_temp');
      if (!tempDir.existsSync()) await tempDir.create(recursive: true);
      final tempPath = await _crypto.decryptToTemp(
        encryptedFile: encryptedFile,
        hexKey: _config!.key,
        hexIv: _config!.iv,
        tempDir: tempDir,
      );
      _currentTempFile = tempPath;

      // Log verification on Dart side
      final tempFile = File(tempPath);
      final tempBytes = tempFile.lengthSync();
      if (tempBytes > 0) {
        final header = await tempFile.openRead(0, 16).first;
        final headerStr = header.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        // ignore: avoid_print
        print('[LMS] Decrypted $src -> $tempPath'
            ' ($tempBytes bytes, header: $headerStr)');
      }

      // If a native player callback is registered, use it instead of the WebView video element.
      if (onPlayMedia != null) {
        onPlayMedia!(tempPath);
      } else {
        // Fallback: serve via local HTTP server for the WebView <video> element.
        await _mediaServer.start(tempPath);
        final videoUrl = _mediaServer.videoUrl;
        await controller.runJavaScript(
            "window._onDecrypted('$src', '$videoUrl');");
      }
    } catch (e) {
      await controller.runJavaScript(
          "window._onDecryptError('$src', '${e.toString().replaceAll("'", "\\'")}');");
    }
  }

  Future<void> _cleanupTempFile() async {
    await _mediaServer.stop();
    if (_currentTempFile != null) {
      await _crypto.secureDelete(_currentTempFile!);
      _currentTempFile = null;
    }
  }

  /// Public alias for cleanup — used by [PlayerScreen] after native playback.
  Future<void> cleanupTempFile() => _cleanupTempFile();
}
