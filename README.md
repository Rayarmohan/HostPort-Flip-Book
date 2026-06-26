# LMS Player — Flutter Assessment

A Flutter application that downloads a ZIP-packaged web player, extracts it to device storage, loads it inside a WebView, prevents background media playback, and plays AES-encrypted video/audio files by decrypting them at runtime only.

---

## Project Structure

```
lib/
├── main.dart
├── models/
│   └── player_config.dart      # Parses config.json
├── services/
│   ├── download_service.dart   # ZIP download + extraction
│   ├── config_service.dart     # Reads config.json
│   ├── crypto_service.dart     # AES-CBC decryption (runtime only)
│   └── webview_service.dart    # WebView controller + JS bridge
└── screens/
    ├── home_screen.dart        # Download UI with progress indicator
    └── player_screen.dart      # WebView host with lifecycle management
```

---

## Implementation Approach

### 1. Package Download & Storage

**Service:** `DownloadService`

- Downloads `player.zip` from `https://tech-lms.adurox.com/flutter/player.zip` using **Dio** (with progress callbacks).
- Stores the ZIP temporarily at:
  ```
  <getApplicationDocumentsDirectory()>/lms_player/player.zip
  ```
- Extracts all contents to:
  ```
  <getApplicationDocumentsDirectory()>/lms_player/package/
  ```
- Deletes the ZIP after successful extraction to conserve space.
- The `package/` directory contains:
  - `index.html` — the web player entry point
  - `config.json` — media manifest with encryption keys
  - `media/` — encrypted video/audio files (stay encrypted on disk permanently)

**Why app documents directory?**
- Private to the app (no `READ_EXTERNAL_STORAGE` permission needed).
- Persists across app restarts.
- Not backed up to cloud (which is appropriate for DRM content).
- Works on Android 10+ scoped storage without any extra permissions.

---

### 2. WebView Integration

**Service:** `WebViewService` | **Screen:** `PlayerScreen`

- Uses `webview_flutter ^4.7.0` (the official Flutter plugin backed by `WebKitView` on iOS and `WebChromeClient` on Android).
- The extracted `index.html` is loaded via:
  - **Android:** `controller.loadFile(absolutePath)` — serves from `file://` origin, giving full access to sibling files in the same directory.
  - **iOS:** `controller.loadRequest(Uri.file(path))` — equivalent.
- JavaScript is fully enabled (`JavaScriptMode.unrestricted`).
- External navigation is blocked (`NavigationDecision.prevent`) for all non-`file://` URLs — security hardening.

#### JavaScript Bridge

A bidirectional bridge is injected after each page load:

**Flutter → JS (injected after `onPageFinished`):**
```javascript
window.flutterBridge = {
  requestEncryptedMedia(mediaId) { ... },  // page calls this to request decryption
  onMediaEnded() { ... }                    // page signals playback finished
};
```

**JS → Flutter (via `JavaScriptChannel` named `FlutterChannel`):**
```json
{ "action": "playEncrypted", "mediaId": "video1" }
{ "action": "mediaEnded" }
```

When the page requests encrypted media, Flutter decrypts the file to a temp path and sends the `file://` URL back via:
```javascript
element.src = "<temp file url>";
element.play();
```

---

### 3. Background Playback Prevention

**Requirement:** Audio/video must NOT continue playing when the user navigates away. Handled entirely in Flutter code.

Three complementary layers:

#### Layer 1 — `WidgetsBindingObserver` in `PlayerScreen`
```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused ||
      state == AppLifecycleState.inactive ||
      state == AppLifecycleState.hidden) {
    _webViewService.pauseMedia();
  }
}
```
Fires when the app is backgrounded, another app comes to front, or the notification shade is pulled down.

#### Layer 2 — `dispose()` / `PopScope`
```dart
@override
void dispose() {
  _webViewService.dispose(); // calls pauseMedia() + cleanup
  super.dispose();
}
```
Fires whenever the `PlayerScreen` widget is removed from the tree — including when the user presses Back to return to `HomeScreen`. The `PopScope` also explicitly calls `pauseMedia()` before allowing the back-navigation.

#### Layer 3 — JavaScript execution in `pauseMedia()`
```javascript
document.querySelectorAll('video, audio').forEach(el => el.pause());
if (navigator.mediaSession) navigator.mediaSession.playbackState = 'paused';
```
Directly pauses every HTML5 media element in the page and updates the Media Session API state.

#### Layer 4 (Android native) — Audio focus in `MainActivity.kt`
```kotlin
override fun onPause() {
    super.onPause()
    audioManager?.abandonAudioFocus(null)
}
```
Releases Android's audio focus at the OS level — a belt-and-suspenders approach that stops any audio the WebView might try to keep alive.

---

### 4. Encrypted Media Handling

**Service:** `CryptoService`

#### config.json format expected:
```json
{
  "index": "index.html",
  "media": [
    {
      "id": "video1",
      "type": "video",
      "file": "media/video.enc",
      "encrypted": true,
      "key": "0123456789abcdef0123456789abcdef",
      "iv": "abcdef0123456789abcdef0123456789"
    }
  ]
}
```

- `key` — 32-char hex = 128-bit AES key (or 64-char = 256-bit)
- `iv` — 32-char hex = 128-bit IV. If omitted, the first 16 bytes of the `.enc` file are treated as the IV.

#### Decryption algorithm: AES-CBC with PKCS7 padding

Implementation uses **pointycastle** (pure Dart, no native code):

```dart
final cipher = PaddedBlockCipherImpl(
  PKCS7Padding(),
  CBCBlockCipher(AESEngine()),
);
cipher.init(false, PaddedBlockCipherParameters(
  ParametersWithIV(KeyParameter(keyBytes), iv), null));
final plaintext = cipher.process(ciphertext);
```

#### Security model — encrypted files stay encrypted on disk

| Stage | File state |
|-------|-----------|
| Extracted from ZIP | `.enc` — encrypted |
| At rest on device | `.enc` — encrypted |
| During playback | Decrypted in-memory → written to **temp** dir |
| After playback ends | Temp file overwritten with zeros, then deleted |

- The decrypted temp file lives in `Directory.systemTemp` (not app documents).
- It is zero-wiped before deletion (`secureDelete()`).
- The encryption key never touches disk — it lives only in memory (read from `config.json` and used immediately).

#### Flow:
1. WebView page triggers `window.flutterBridge.requestEncryptedMedia('video1')`.
2. Flutter finds the matching `MediaItem` in the parsed `PlayerConfig`.
3. `CryptoService.decryptToTemp()` reads the `.enc` file, decrypts in memory, writes plaintext to `<tmpdir>/lms_XXXXX/decrypted.mp4`.
4. Flutter calls JS: `videoElement.src = "file:///tmp/lms_.../decrypted.mp4"; videoElement.play()`.
5. On `mediaEnded` or screen disposal: `secureDelete()` wipes and removes the temp file.

---

## Dependencies

| Package | Purpose |
|---------|---------|
| `webview_flutter ^4.7.0` | Embedded WebView |
| `dio ^5.4.3` | File download with progress |
| `archive ^3.6.1` | ZIP extraction (pure Dart) |
| `path_provider ^2.1.3` | Platform-correct storage paths |
| `pointycastle ^3.9.1` | AES-CBC decryption (pure Dart) |
| `convert ^3.1.1` | Hex decoding for keys/IVs |
| `percent_indicator ^4.2.3` | Download progress UI |
| `permission_handler ^11.3.1` | Runtime permissions (if needed) |

---

## Build Instructions

### Prerequisites
- Flutter SDK ≥ 3.0.0
- Android Studio / Xcode
- Android: `minSdk 21`, `targetSdk 34`

### Run in debug mode
```bash
flutter pub get
flutter run
```

### Build APK (release)
```bash
flutter pub get
flutter build apk --release
# APK at: build/app/outputs/flutter-apk/app-release.apk
```

### Build APK (debug, for assessment)
```bash
flutter build apk --debug
# APK at: build/app/outputs/flutter-apk/app-debug.apk
```

---

## Permissions

| Permission | Reason |
|-----------|--------|
| `INTERNET` | Download player ZIP |
| `ACCESS_NETWORK_STATE` | Check connectivity before download |

No storage permissions needed — app-private storage (`getApplicationDocumentsDirectory`) doesn't require `READ/WRITE_EXTERNAL_STORAGE` on Android 10+.

---

## Notes on the Player Page

The fetched `index.html` is a flip-book with 10 pages containing:
- **Normal video** — standard `<video>` element
- **Encrypted video** — triggered via `data-encrypted` attribute + `window.flutterBridge.requestEncryptedMedia()`
- **Audio** — standard `<audio>` element

The JS bridge supports both standard HTML5 elements and the custom `HostPort` action pattern observed in the player demo.
