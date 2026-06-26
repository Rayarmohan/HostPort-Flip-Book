import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:lms_player/features/player/presentation/bloc/player_bloc.dart';
import 'package:lms_player/features/player/presentation/bloc/player_event.dart';
import 'package:lms_player/features/player/presentation/bloc/player_state.dart';
import 'package:lms_player/features/player/presentation/widgets/video_controls.dart';
import 'package:lms_player/core/entities/player_config.dart';

class PlayerPage extends StatefulWidget {
  final String packageDirPath;
  final PlayerConfig config;

  const PlayerPage({
    super.key,
    required this.packageDirPath,
    required this.config,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _videoController;
  late final PlayerBloc _playerBloc;

  @override
  void initState() {
    super.initState();
    _playerBloc = context.read<PlayerBloc>();
    WidgetsBinding.instance.addObserver(this);
    _playerBloc.add(PlayerInitialized(
      config: widget.config,
      packageDirPath: widget.packageDirPath,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    super.didChangeAppLifecycleState(appState);
    if (appState == AppLifecycleState.paused ||
        appState == AppLifecycleState.inactive ||
        appState == AppLifecycleState.hidden) {
      _playerBloc.add(const PlayerBackPressed());
    }
  }

  Future<bool> _onWillPop() async {
    await _playerBloc.repository.pauseMedia();

    final ctrl = _getControllerFromBloc();
    if (ctrl != null) {
      final canGoBack = await ctrl.canGoBack();
      if (canGoBack) {
        await ctrl.goBack();
        return false;
      }
    }
    return true;
  }

  WebViewController? _getControllerFromBloc() {
    final s = _playerBloc.state;
    if (s is PlayerReady) return s.controller;
    if (s is PlayerNativePlayerActive) return s.controller;
    return null;
  }

  void _onNativePlayMedia(String filePath) {
    final controller = VideoPlayerController.file(File(filePath));
    controller.initialize().then((_) {
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _videoController?.dispose();
        _videoController = controller;
      });
      controller.play();
    }).catchError((e) {
      controller.dispose();
    });
  }

  void _closeNativePlayer() {
    _playerBloc.add(const PlayerNativePlayerClosed());
    setState(() {
      _videoController?.pause();
      _videoController?.dispose();
      _videoController = null;
    });
  }

  Widget _buildNativePlayerOverlay() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
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
        VideoControls(
          controller: controller,
          onClose: _closeNativePlayer,
        ),
      ],
    );
  }

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
              await _onWillPop();
              if (mounted) navigator.pop();
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload',
              onPressed: () {
                _closeNativePlayer();
                _playerBloc.add(PlayerInitialized(
                  config: widget.config,
                  packageDirPath: widget.packageDirPath,
                ));
              },
            ),
          ],
        ),
        body: BlocConsumer<PlayerBloc, PlayerState>(
          listener: (context, state) {
            if (state is PlayerNativePlayerActive) {
              _onNativePlayMedia(state.filePath);
            }
          },
          builder: (context, state) {
            WebViewController? ctrl;
            if (state is PlayerReady) ctrl = state.controller;
            if (state is PlayerNativePlayerActive) ctrl = state.controller;
            final errorText = state is PlayerError ? state.error : null;
            final isLoading = state is PlayerLoading;

            return Stack(
              children: [
                // WebView
                if (ctrl != null)
                  WebViewWidget(controller: ctrl),

                // Loading overlay
                if (isLoading)
                  Container(
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
                  ),

                // Error overlay
                if (errorText != null)
                  Container(
                    color: Colors.black,
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 64),
                          const SizedBox(height: 16),
                          const Text(
                            'Failed to load player',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            errorText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 12),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              context
                                  .read<PlayerBloc>()
                                  .add(PlayerInitialized(
                                    config: widget.config,
                                    packageDirPath: widget.packageDirPath,
                                  ));
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Native player overlay
                if (_videoController != null)
                  _buildNativePlayerOverlay(),
              ],
            );
          },
        ),
      ),
    );
  }
}
