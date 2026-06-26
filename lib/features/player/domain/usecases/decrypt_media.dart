import 'package:lms_player/core/entities/player_config.dart';
import 'package:lms_player/features/player/domain/repositories/player_repository.dart';

class DecryptMedia {
  final PlayerRepository repository;

  DecryptMedia(this.repository);

  Future<String> call({
    required String src,
    required String packageDirPath,
    required PlayerConfig config,
  }) {
    return repository.decryptMedia(
      src: src,
      packageDirPath: packageDirPath,
      config: config,
    );
  }
}
