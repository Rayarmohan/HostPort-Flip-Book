import 'package:equatable/equatable.dart';
import 'package:lms_player/core/entities/player_config.dart';

sealed class PlayerEvent extends Equatable {
  const PlayerEvent();

  @override
  List<Object?> get props => [];
}

class PlayerInitialized extends PlayerEvent {
  final PlayerConfig config;
  final String packageDirPath;

  const PlayerInitialized({
    required this.config,
    required this.packageDirPath,
  });

  @override
  List<Object?> get props => [config, packageDirPath];
}

class PlayerPageLoaded extends PlayerEvent {
  const PlayerPageLoaded();
}

class PlayerPageError extends PlayerEvent {
  final String error;
  const PlayerPageError({required this.error});

  @override
  List<Object?> get props => [error];
}

class PlayerMediaRequested extends PlayerEvent {
  final String src;
  final String type;
  final String title;
  final String fallback;

  const PlayerMediaRequested({
    required this.src,
    required this.type,
    required this.title,
    required this.fallback,
  });

  @override
  List<Object?> get props => [src, type, title, fallback];
}

class PlayerNativePlayerClosed extends PlayerEvent {
  const PlayerNativePlayerClosed();
}

class PlayerBackPressed extends PlayerEvent {
  const PlayerBackPressed();
}
