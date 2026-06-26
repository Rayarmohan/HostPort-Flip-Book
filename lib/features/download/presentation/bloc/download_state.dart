import 'package:equatable/equatable.dart';
import 'package:lms_player/core/entities/player_config.dart';

sealed class DownloadState extends Equatable {
  const DownloadState();

  @override
  List<Object?> get props => [];
}

class DownloadIdle extends DownloadState {
  const DownloadIdle();
}

class DownloadInProgress extends DownloadState {
  final double progress;
  final String statusText;

  const DownloadInProgress({this.progress = 0.0, this.statusText = ''});

  @override
  List<Object?> get props => [progress, statusText];
}

class DownloadSuccess extends DownloadState {
  final PlayerConfig config;
  final String packageDirPath;

  const DownloadSuccess({
    required this.config,
    required this.packageDirPath,
  });

  @override
  List<Object?> get props => [config, packageDirPath];
}

class DownloadFailure extends DownloadState {
  final String error;

  const DownloadFailure({required this.error});

  @override
  List<Object?> get props => [error];
}
