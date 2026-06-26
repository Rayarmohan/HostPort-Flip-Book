import 'package:lms_player/core/entities/player_config.dart';

abstract class DownloadRepository {
  Future<({PlayerConfig config, String packageDirPath})> loadExistingPackage(
      String tempDirPath);

  Future<({PlayerConfig config, String packageDirPath})> downloadAndExtract({
    required String zipUrl,
    required String tempDirPath,
    void Function(double progress, String statusText)? onProgress,
  });
}
