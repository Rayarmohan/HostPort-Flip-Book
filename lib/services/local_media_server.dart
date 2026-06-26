import 'dart:io';

class LocalMediaServer {
  HttpServer? _server;
  int _port = 0;
  String _servedPath = '';

  String get baseUrl => 'http://127.0.0.1:$_port';
  String get videoUrl => '$baseUrl/video.mp4';

  Future<void> start(String filePath) async {
    await stop();
    _servedPath = filePath;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen(_handleRequest);
  }

  void _handleRequest(HttpRequest request) {
    final file = File(_servedPath);
    if (!file.existsSync()) {
      request.response.statusCode = 404;
      request.response.close();
      return;
    }

    final fileSize = file.lengthSync();
    final rangeHeader = request.headers.value('range');

    request.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Range')
      ..contentType = ContentType('video', 'mp4')
      ..set('Accept-Ranges', 'bytes');

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final range = rangeHeader.substring(6);
      final parts = range.split('-');
      final start = int.parse(parts[0]);
      final end = parts.length > 1 && parts[1].isNotEmpty
          ? int.parse(parts[1])
          : fileSize - 1;
      final contentLength = end - start + 1;

      request.response.statusCode = 206;
      request.response.headers
        ..set('Content-Range', 'bytes $start-$end/$fileSize')
        ..set('Content-Length', contentLength.toString());

      file.openRead(start, end + 1).pipe(request.response);
    } else {
      request.response.headers.set('Content-Length', fileSize.toString());
      file.openRead().pipe(request.response);
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
