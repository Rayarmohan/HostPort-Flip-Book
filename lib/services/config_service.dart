import 'dart:convert';
import 'dart:io';

import '../models/player_config.dart';

/// Reads and parses config.json from the extracted package directory.
class ConfigService {
  static const String _configFileName = 'config.json';

  /// Loads [PlayerConfig] from [packageDirPath]/config.json.
  Future<PlayerConfig> loadConfig(String packageDirPath) async {
    final configFile = File('$packageDirPath/$_configFileName');

    if (!configFile.existsSync()) {
      throw StateError(
        'config.json not found at ${configFile.path}. '
        'Make sure the package has been extracted correctly.',
      );
    }

    final jsonString = await configFile.readAsString();
    final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
    return PlayerConfig.fromJson(jsonMap);
  }
}
