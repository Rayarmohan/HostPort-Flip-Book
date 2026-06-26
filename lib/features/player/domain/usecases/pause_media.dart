import 'package:lms_player/features/player/domain/repositories/player_repository.dart';

class PauseMedia {
  final PlayerRepository repository;

  PauseMedia(this.repository);

  Future<void> call() => repository.pauseMedia();
}
