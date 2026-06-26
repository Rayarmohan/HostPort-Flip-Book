import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:lms_player/features/player/presentation/bloc/player_event.dart';
import 'package:lms_player/features/player/presentation/bloc/player_state.dart';
import 'package:lms_player/core/entities/player_config.dart';
import 'package:lms_player/features/player/data/repositories/player_repository_impl.dart';

class PlayerBloc extends Bloc<PlayerEvent, PlayerState> {
  final PlayerRepositoryImpl repository;
  PlayerConfig? _config;
  String? _packageDirPath;
  WebViewController? _controller;

  PlayerBloc({required this.repository})
      : super(const PlayerInitial()) {
    on<PlayerInitialized>(_onInitialized);
    on<PlayerPageLoaded>(_onPageLoaded);
    on<PlayerPageError>(_onPageError);
    on<PlayerMediaRequested>(_onMediaRequested);
    on<PlayerNativePlayerClosed>(_onNativePlayerClosed);
    on<PlayerBackPressed>(_onBackPressed);
  }

  Future<void> _onInitialized(
    PlayerInitialized event,
    Emitter<PlayerState> emit,
  ) async {
    await repository.cleanupTempFile();

    // Check that the extracted package still exists
    final indexFile = File('${event.packageDirPath}/index.html');
    if (!indexFile.existsSync()) {
      emit(PlayerError(
          error:
              'Package files missing at ${event.packageDirPath}. Please go back and re-download the player package.'));
      return;
    }

    _config = event.config;
    _packageDirPath = event.packageDirPath;
    _controller = null;
    emit(const PlayerLoading());

    try {
      repository.onOpenMediaModal = (src, type, title, fallback) {
        if (!isClosed) {
          add(PlayerMediaRequested(
            src: src,
            type: type,
            title: title,
            fallback: fallback,
          ));
        }
      };

      final controller = repository.createController(
        packageDirPath: event.packageDirPath,
        config: event.config,
      );
      _controller = controller;

      controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!isClosed) add(const PlayerPageLoaded());
          },
          onWebResourceError: (error) {
            if (!isClosed) {
              add(PlayerPageError(error: error.description));
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

      await repository.loadPlayer(controller, event.packageDirPath);
    } catch (e) {
      emit(PlayerError(error: e.toString()));
    }
  }

  Future<void> _onPageLoaded(
    PlayerPageLoaded event,
    Emitter<PlayerState> emit,
  ) async {
    final ctrl = _controller;
    if (ctrl == null) {
      if (!isClosed) {
        emit(const PlayerError(error: 'Controller not available'));
      }
      return;
    }

    try {
      await repository.injectBridge();
      if (!isClosed) {
        emit(PlayerReady(controller: ctrl));
      }
    } catch (e) {
      if (!isClosed) emit(PlayerError(error: 'Bridge injection failed: $e'));
    }
  }

  Future<void> _onPageError(
    PlayerPageError event,
    Emitter<PlayerState> emit,
  ) async {
    if (!isClosed) emit(PlayerError(error: event.error));
  }

  Future<void> _onMediaRequested(
    PlayerMediaRequested event,
    Emitter<PlayerState> emit,
  ) async {
    if (_config == null || _packageDirPath == null) return;

    try {
      final ctrl = _ctrlFromState();
      if (ctrl == null) return;

      final isEnc = _config!.isEncrypted(event.src);

      if (isEnc) {
        await ctrl.runJavaScript('''
          (function() {
            window._pendingModal = { type: '${event.type}', title: '${event.title.replaceAll("'", "\\'")}', fallback: '${event.fallback.replaceAll("'", "\\'")}' };
            var mt = document.getElementById('modalTitle');
            if (mt) mt.textContent = '${event.title.replaceAll("'", "\\'")}';
            var mc = document.getElementById('modalContent');
            if (mc) mc.innerHTML = '<p style="padding:20px;text-align:center">Decrypting video\u2026</p>';
            var modal = document.getElementById('mediaModal');
            if (modal) { modal.classList.add('open'); modal.setAttribute('aria-hidden', 'false'); }
          })();
        ''');

        final tempPath = await repository.decryptMedia(
          src: event.src,
          packageDirPath: _packageDirPath!,
          config: _config!,
        );

        if (!isClosed) {
          emit(PlayerNativePlayerActive(
            controller: ctrl,
            filePath: tempPath,
          ));
        }
      } else {
        final escType = event.type.replaceAll("'", "\\'");
        final escTitle = event.title.replaceAll("'", "\\'");
        final escSrc = event.src.replaceAll("'", "\\'");
        final escFallback = event.fallback.replaceAll("'", "\\'");
        await ctrl.runJavaScript('''
          window.openMediaModalOriginal && window.openMediaModalOriginal(
            '$escType', '$escTitle', '$escSrc', '$escFallback'
          );
        ''');
      }
    } catch (e) {
      if (!isClosed) {
        emit(PlayerError(error: 'Media error: $e'));
      }
    }
  }

  Future<void> _onNativePlayerClosed(
    PlayerNativePlayerClosed event,
    Emitter<PlayerState> emit,
  ) async {
    final ctrl = _ctrlFromState();
    if (ctrl != null) {
      await ctrl.runJavaScript('closeMediaModal();');
    }
    await repository.cleanupTempFile();
    if (ctrl != null && !isClosed) {
      emit(PlayerReady(controller: ctrl));
    }
  }

  Future<void> _onBackPressed(
    PlayerBackPressed event,
    Emitter<PlayerState> emit,
  ) async {
    await repository.pauseMedia();
    final ctrl = _ctrlFromState();
    if (ctrl != null) {
      final canGoBack = await ctrl.canGoBack();
      if (canGoBack) {
        await ctrl.goBack();
        return;
      }
    }
  }

  WebViewController? _ctrlFromState() {
    final s = state;
    if (s is PlayerReady) return s.controller;
    if (s is PlayerNativePlayerActive) return s.controller;
    return _controller;
  }

  Future<void> disposeBloc() async {
    await repository.dispose();
  }
}
