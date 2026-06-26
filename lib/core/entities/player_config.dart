import 'package:equatable/equatable.dart';

class PlayerConfig extends Equatable {
  final String key;
  final String iv;
  final List<String> encryptedMedia;

  const PlayerConfig({
    required this.key,
    required this.iv,
    required this.encryptedMedia,
  });

  bool isEncrypted(String src) => encryptedMedia.contains(src);

  @override
  List<Object?> get props => [key, iv, encryptedMedia];
}
