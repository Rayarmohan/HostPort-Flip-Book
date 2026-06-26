import 'dart:convert';
import 'dart:io';

class ConfigLocalDataSource {
  Map<String, dynamic> loadConfig(String packageDirPath) {
    final configFile = File('$packageDirPath/config.json');
    if (!configFile.existsSync()) {
      throw Exception('config.json not found at $packageDirPath');
    }
    final contents = configFile.readAsStringSync();
    return jsonDecode(contents) as Map<String, dynamic>;
  }
}
