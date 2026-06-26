sealed class Failure {
  final String message;
  const Failure(this.message);
}

class DownloadFailure extends Failure {
  const DownloadFailure(super.message);
}

class ExtractionFailure extends Failure {
  const ExtractionFailure(super.message);
}

class ConfigParseFailure extends Failure {
  const ConfigParseFailure(super.message);
}

class DecryptionFailure extends Failure {
  const DecryptionFailure(super.message);
}

class WebViewFailure extends Failure {
  const WebViewFailure(super.message);
}
