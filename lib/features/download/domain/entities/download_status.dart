import 'package:equatable/equatable.dart';

class DownloadStatus extends Equatable {
  final bool isCompleted;
  final double progress;
  final String currentTask;

  const DownloadStatus({
    this.isCompleted = false,
    this.progress = 0.0,
    this.currentTask = '',
  });

  DownloadStatus copyWith({
    bool? isCompleted,
    double? progress,
    String? currentTask,
  }) {
    return DownloadStatus(
      isCompleted: isCompleted ?? this.isCompleted,
      progress: progress ?? this.progress,
      currentTask: currentTask ?? this.currentTask,
    );
  }

  @override
  List<Object?> get props => [isCompleted, progress, currentTask];
}
