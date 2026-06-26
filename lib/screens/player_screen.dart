import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/player_config.dart';
import '../services/webview_service.dart';

/// Hosts the WebView player. Handles the critical requirement:
///
///   ► Audio/video MUST stop when the user navigates away.
///
/// This is achieved by:
///   1. [AppLifecycleListener] — pauses media when the app goes to background.
///   2. [RouteObserver] — not needed here since we pop back to HomeScreen;
///      instead, [dispose] is called automatically when this screen is popped.
///   3. [dispose()] → [WebViewService.dispose()] → JS pause + temp cleanup.
class PlayerScreen extends StatefulWidget {
  final String packageDirPath;
  final PlayerConfig config;

  const PlayerScreen({
    super.key,
    required this.packageDirPath,
    required this.config,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late final WebViewController _webViewController;
  final WebViewService _webViewService = WebViewService();

  bool _isLoading = true;
  String? _errorText;

  // ── Native video player overlay ──────────────────────────────────────────

  VideoPlayerController? _videoController;
  bool _showNativePlayer = false;

  void _onNativePlayMedia(String filePath) {
    final controller = VideoPlayerController.file(File(filePath));
    controller.initialize().then((_) {
      if (!mounted) { controller.dispose(); return; }
      setState(() {
        _videoController?.dispose();
        _videoController = controller;
        _showNativePlayer = true;
      });
      controller.play();
    }).catchError((e) {
      controller.dispose();
      // ignore: avoid_print
      print('[LMS] Native player init failed: $e');
    });
  }

  void _closeNativePlayer() {
    // Close the WebView's modal (still showing "Decrypting video…")
    _webViewController.runJavaScript('closeMediaModal();');
    setState(() {
      _showNativePlayer = false;
    });
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
    _webViewService.cleanupTempFile();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWebView();
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Called when the app lifecycle state changes (foreground ↔ background).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      // App moved to background or another app came to front
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // CRITICAL: pause all media to prevent background audio/video playback
        _webViewService.pauseMedia();
        break;
      case AppLifecycleState.resumed:
        // Intentionally not auto-resuming — user must tap play again.
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoController?.dispose();
    _videoController = null;
    // Pause media and clean up decrypted temp files
    _webViewService.dispose();
    super.dispose();
  }

  // ── Setup ──────────────────────────────────────────────────────────────────

  Future<void> _initWebView() async {
    _webViewController = _webViewService.createController(
      packageDirPath: widget.packageDirPath,
      config: widget.config,
      onError: (error) {
        if (mounted) setState(() { _errorText = error; _isLoading = false; });
      },
    );

    // Register native video playback callback
    _webViewService.onPlayMedia = _onNativePlayMedia;

    // Register page-finished listener to hide loader
    _webViewController.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _isLoading = true);
          // ignore: avoid_print
          print('[LMS] onPageStarted');
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
          // ignore: avoid_print
          print('[LMS] onPageFinished');
          _webViewService.injectBridge(_webViewController);
        },
        onWebResourceError: (error) {
          if (mounted) {
            setState(() {
              _errorText = error.description;
              _isLoading = false;
            });
          }
        },
        onNavigationRequest: (request) {
          if (request.url.startsWith('file://') ||
              request.url.startsWith('about:')) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
      ),
    );

    try {
      await _webViewService.loadPlayer(_webViewController, widget.packageDirPath);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorText = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // ── Back navigation ────────────────────────────────────────────────────────

  Future<bool> _onWillPop() async {
    // Pause all media BEFORE leaving this screen (core requirement)
    await _webViewService.pauseMedia();

    // Check if WebView can go back within the player itself
    final canGoBack = await _webViewController.canGoBack();
    if (canGoBack) {
      await _webViewController.goBack();
      return false; // don't pop the route
    }
    return true; // pop the route (goes back to HomeScreen)
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Player'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) navigator.pop();
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload',
              onPressed: () async {
                await _webViewService.pauseMedia();
                await _webViewController.reload();
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            // WebView
            if (_errorText == null)
              WebViewWidget(controller: _webViewController),

            // Error overlay
            if (_errorText != null) _buildErrorOverlay(),

            // Loading overlay
            if (_isLoading && _errorText == null) _buildLoadingOverlay(),

            // Native video player overlay (for encrypted media)
            if (_showNativePlayer && _videoController != null)
              _buildNativePlayerOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildNativePlayerOverlay() {
    final controller = _videoController!;
    if (!controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        _VideoControls(
          controller: controller,
          onClose: _closeNativePlayer,
        ),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black87,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF1A73E8)),
            SizedBox(height: 16),
            Text(
              'Loading player\u2026',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Failed to load player',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _errorText!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() { _errorText = null; _isLoading = true; });
                _initWebView();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoControls extends StatefulWidget {
  final VideoPlayerController controller;
  final VoidCallback onClose;

  const _VideoControls({
    required this.controller,
    required this.onClose,
  });

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls> {
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onValueChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onValueChanged);
    super.dispose();
  }

  void _onValueChanged() {
    if (mounted) setState(() {});
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final value = ctrl.value;
    final pos = value.position;
    final dur = value.duration;

    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: Container(
        color: Colors.transparent,
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Column(
            children: [
              const Spacer(),
              // Bottom bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Slider
                    Row(
                      children: [
                        Text(_formatDuration(pos), style: const TextStyle(color: Colors.white, fontSize: 12)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                              overlayColor: Colors.white24,
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            ),
                            child: Slider(
                              value: dur.inMilliseconds > 0
                                  ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                                  : 0.0,
                              onChanged: (v) {
                                final newPos = Duration(milliseconds: (v * dur.inMilliseconds).round());
                                ctrl.seekTo(newPos);
                              },
                            ),
                          ),
                        ),
                        Text(_formatDuration(dur), style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                    // Play/pause + close
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 32),
                          onPressed: () {
                            value.isPlaying ? ctrl.pause() : ctrl.play();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 28),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
