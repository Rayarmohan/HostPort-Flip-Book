import 'package:webview_flutter/webview_flutter.dart';
import 'package:lms_player/core/entities/player_config.dart';
import 'package:lms_player/features/player/domain/repositories/player_repository.dart';

class LoadPlayer {
  final PlayerRepository repository;

  LoadPlayer(this.repository);

  WebViewController createController({
    required String packageDirPath,
    required PlayerConfig config,
  }) {
    return repository.createController(
      packageDirPath: packageDirPath,
      config: config,
    );
  }

  Future<void> loadPage(
    WebViewController controller,
    String packageDirPath,
  ) {
    return repository.loadPlayer(controller, packageDirPath);
  }

  Future<void> injectBridge() {
    return repository.injectBridge();
  }
}
