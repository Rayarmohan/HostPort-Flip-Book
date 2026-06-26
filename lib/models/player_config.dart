// Represents the structure of config.json found inside the player ZIP.
//
// {
//   "aes": {
//     "algorithm": "aes-256-cbc",
//     "key": "hex-256-bit-key",
//     "iv": "hex-128-bit-iv"
//   },
//   "encrypted_media": ["media/video/video2.mp4"]
// }

class PlayerConfig {
  final String algorithm;
  final String key;
  final String? iv;
  final List<String> encryptedMedia;

  const PlayerConfig({
    required this.algorithm,
    required this.key,
    this.iv,
    required this.encryptedMedia,
  });

  factory PlayerConfig.fromJson(Map<String, dynamic> json) {
    final aes = json['aes'] as Map<String, dynamic>? ?? {};
    final encryptedMedia = (json['encrypted_media'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [];
    return PlayerConfig(
      algorithm: (aes['algorithm'] as String?) ?? 'aes-256-cbc',
      key: (aes['key'] as String?) ?? '',
      iv: aes['iv'] as String?,
      encryptedMedia: encryptedMedia,
    );
  }

  /// Returns true if the given relative path matches an encrypted media file.
  bool isEncrypted(String relativePath) =>
      encryptedMedia.any((e) => e == relativePath);
}
