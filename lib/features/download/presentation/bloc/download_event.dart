import 'package:equatable/equatable.dart';

sealed class DownloadEvent extends Equatable {
  const DownloadEvent();

  @override
  List<Object?> get props => [];
}

class CheckPackageRequested extends DownloadEvent {
  final String tempDirPath;

  const CheckPackageRequested({required this.tempDirPath});

  @override
  List<Object?> get props => [tempDirPath];
}

class DownloadRequested extends DownloadEvent {
  final String tempDirPath;

  const DownloadRequested({required this.tempDirPath});

  @override
  List<Object?> get props => [tempDirPath];
}
