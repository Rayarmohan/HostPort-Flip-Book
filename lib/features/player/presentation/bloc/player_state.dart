import 'package:equatable/equatable.dart';
import 'package:webview_flutter/webview_flutter.dart';

sealed class PlayerState extends Equatable {
  const PlayerState();

  @override
  List<Object?> get props => [];
}

class PlayerInitial extends PlayerState {
  const PlayerInitial();
}

class PlayerLoading extends PlayerState {
  const PlayerLoading();
}

class PlayerReady extends PlayerState {
  final WebViewController controller;

  const PlayerReady({required this.controller});

  @override
  List<Object?> get props => [controller];
}

class PlayerNativePlayerActive extends PlayerState {
  final WebViewController controller;
  final String filePath;

  const PlayerNativePlayerActive({
    required this.controller,
    required this.filePath,
  });

  @override
  List<Object?> get props => [controller, filePath];
}

class PlayerError extends PlayerState {
  final String error;

  const PlayerError({required this.error});

  @override
  List<Object?> get props => [error];
}
