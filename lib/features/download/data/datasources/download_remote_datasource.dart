import 'dart:io';

import 'package:http/http.dart' as http;

class DownloadRemoteDataSource {
  Future<String> downloadZip({
    required String zipUrl,
    required String savePath,
  }) async {
    final response = await http.get(Uri.parse(zipUrl));
    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }
    final file = File(savePath);
    await file.writeAsBytes(response.bodyBytes);
    return savePath;
  }
}
