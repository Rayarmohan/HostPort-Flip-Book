import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lms_player/core/constants/app_constants.dart';
import 'package:lms_player/features/download/presentation/bloc/download_event.dart';
import 'package:lms_player/features/download/presentation/bloc/download_state.dart';
import 'package:lms_player/features/download/domain/repositories/download_repository.dart';

class DownloadBloc extends Bloc<DownloadEvent, DownloadState> {
  final DownloadRepository repository;

  DownloadBloc({required this.repository}) : super(const DownloadIdle()) {
    on<CheckPackageRequested>(_onCheckPackage);
    on<DownloadRequested>(_onDownloadRequested);
  }

  Future<void> _onCheckPackage(
    CheckPackageRequested event,
    Emitter<DownloadState> emit,
  ) async {
    try {
      final result = await repository.loadExistingPackage(event.tempDirPath);
      emit(DownloadSuccess(
        config: result.config,
        packageDirPath: result.packageDirPath,
      ));
    } catch (_) {
      // Package not ready — stay idle
    }
  }

  Future<void> _onDownloadRequested(
    DownloadRequested event,
    Emitter<DownloadState> emit,
  ) async {
    emit(const DownloadInProgress(progress: 0.0, statusText: 'Initializing…'));

    try {
      final result = await repository.downloadAndExtract(
        zipUrl: AppConstants.playerZipUrl,
        tempDirPath: event.tempDirPath,
        onProgress: (progress, statusText) {
          if (!isClosed) {
            emit(DownloadInProgress(progress: progress, statusText: statusText));
          }
        },
      );

      await Future.delayed(const Duration(milliseconds: 300));

      emit(DownloadSuccess(
        config: result.config,
        packageDirPath: result.packageDirPath,
      ));
    } catch (e) {
      emit(DownloadFailure(error: e.toString()));
    }
  }
}
