# HostPort Flip Book

A Flutter LMS player that downloads encrypted media packages from a remote ZIP, decrypts AES-256-CBC content at runtime, and plays it through a WebView with native video fallback.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App                          │
│  ┌──────────────────┐   ┌────────────────────────────┐ │
│  │   DownloadBloc    │   │        PlayerBloc          │ │
│  │  ───────────────  │   │  ────────────────────────  │ │
│  │  Idle             │   │  Initial → Loading         │ │
│  │  InProgress(progress)│ │  → Ready (WebView)         │ │
│  │  Success(config)   │   │  → NativeActive (video)   │ │
│  │  Failure(error)    │   │  → Error                   │ │
│  └────────┬─────────┘   └────────────┬───────────────┘ │
│           │                          │                  │
│  ┌────────▼─────────┐   ┌────────────▼───────────────┐ │
│  │ DownloadRepo     │   │ PlayerRepository           │ │
│  │  - HTTP stream   │   │  - WebViewDataSource        │ │
│  │  - ZIP extract   │   │  - CryptoLocalDataSource    │ │
│  │  - Config parse  │   │  - JS bridge injection      │ │
│  └──────────────────┘   └────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

The app uses **flutter_bloc** with **Clean Architecture** (data / domain / presentation layers) separated by feature.

---

## How It Works — Step by Step

### 1. Package Download

1. User taps **"Download Player Package"** on the home screen.
2. `DownloadBloc` starts, emitting `DownloadInProgress(0%)`.
3. `DownloadRepositoryImpl` streams the ZIP via HTTP with byte-level progress tracking (0–50%).
4. On completion, the ZIP is extracted file-by-file (50–85%) with per-file progress.
5. `config.json` is parsed (85–100%) to extract the AES key, IV, and encrypted media list.
6. `DownloadSuccess(config, packageDirPath)` is emitted — the app navigates to the player page.

### 2. WebView Initialization

1. `PlayerPage` creates the `PlayerBloc` and dispatches `PlayerInitialized`.
2. A **new `WebViewController`** is created with:
   - `JavaScriptMode.unrestricted`
   - `FlutterChannel` JS bridge channel
3. A `NavigationDelegate` is attached:
   - `onPageFinished` → dispatches `PlayerPageLoaded`
   - `onWebResourceError` → dispatches `PlayerPageError`
   - `onNavigationRequest` → blocks all URLs except `file://` and `about:`
4. The local `index.html` is loaded via `loadFile()` (Android) or `loadRequest()` (iOS).

### 3. JavaScript Bridge Injection

Once the page finishes loading, the bridge script is injected:

```javascript
// Save originals for later delegation
var originalOpenMediaModal = window.openMediaModal;
var originalCloseMediaModal = window.closeMediaModal;

// Expose originals for Flutter to call
window.openMediaModalOriginal = originalOpenMediaModal;

// Intercept media clicks — forward to Flutter
window.openMediaModal = function(type, title, src, fallback) {
  FlutterChannel.postMessage(JSON.stringify({
    action: "openMediaModal", type, title, src, fallback
  }));
};

// Cleanup helper
function stopModalMedia() {
  var modal = document.getElementById('mediaModal');
  if (modal) {
    modal.querySelectorAll('video, audio').forEach(function(el) {
      el.pause(); el.src = ''; el.load();
    });
    var content = document.getElementById('modalContent');
    if (content) content.innerHTML = '';
  }
}

// MutationObserver — catches ALL modal close methods
var modalEl = document.getElementById('mediaModal');
if (modalEl) {
  var observer = new MutationObserver(function() {
    if (!modalEl.classList.contains('open')) stopModalMedia();
  });
  observer.observe(modalEl, { attributes: true, attributeFilter: ['class'] });
}

// pagehide / visibilitychange — pause media on navigation / background
document.addEventListener('pagehide', stopAllMedia);
document.addEventListener('visibilitychange', function() {
  if (document.hidden) stopAllMedia();
});
```

Key design decisions in the bridge:

| Decision | Rationale |
|---|---|
| `MutationObserver` on class attribute, not `window.closeMediaModal` override | The page's close button / tap-outside / Escape listeners captured `closeMediaModal` by lexical scope, so a `window` override was never invoked. |
| `openMediaModalOriginal` exposed for non-encrypted media | Non-encrypted videos should use the page's built-in handler; only encrypted videos need the Flutter intercept-decrypt-play flow. |
| `stopModalMedia` clears `src` and calls `load()` | This forces the browser to release media resources, preventing background audio. |

---

## Encrypted Media Handling

### AES-256-CBC Decryption

```dart
/// Config from config.json
/// {
///   "aes": {
///     "algorithm": "aes-256-cbc",
///     "key": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
///     "iv":  "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d"
///   },
///   "encrypted_media": ["media/video/video2.mp4"]
/// }
```

The decryption process (`CryptoLocalDataSource`):

1. Read the encrypted file from the extracted package.
2. Decrypt using **PointyCastle** with AES-256-CBC:
   - Key: 32 bytes (64 hex chars from config)
   - IV: 15 bytes (30 hex chars — used as-is with PointyCastle, no padding needed since the plaintext length is implicit)
3. Write the decrypted bytes to a **temporary file** in `_temp/` within the extracted directory.
4. Return the temp file path for native video playback.

**Important**: The decrypted file is **never stored permanently**. It is deleted when:
- The native player is closed (`PlayerNativePlayerClosed` → `cleanupTempFile()`)
- A new initialization starts (`_onInitialized` → `cleanupTempFile()`)

### Encrypted Video Playback Flow

```
User clicks video in WebView
         │
         ▼
JS bridge intercepts openMediaModal
         │
         ▼
Flutter receives "openMediaModal" message
         │
         ▼
PlayerBloc._onMediaRequested()
         │
         ├── isEncrypted? ──► YES
         │                      │
         │                      ├── JS: Show "Decrypting video…" modal
         │                      ├── Run AES-256-CBC decryption
         │                      ├── Emit PlayerNativePlayerActive(tempPath)
         │                      │
         │                      ▼
         │              BlocConsumer listener
         │                      │
         │                      ▼
         │              VideoPlayerController initialized with temp file
         │              Native player overlay appears
         │                      │
         │              User watches video natively
         │                      │
         │              User taps close button
         │                      │
         │                      ▼
         │              PlayerNativePlayerClosed dispatched
         │                      │
         │                      ├── JS: closeMediaModal()
         │                      ├── Cleanup temp file (secureDelete)
         │                      └── Emit PlayerReady (WebView returns)
         │
         └── isEncrypted? ──► NO
                                │
                                └── JS: openMediaModalOriginal(type, title, src, fallback)
                                    Page handles it natively
```

### Non-Encrypted Video

Non-encrypted videos are **not intercepted**. Flutter calls the page's original `openMediaModalOriginal` function, which opens the modal and plays the video directly in the WebView. The bridge only intercepts encrypted media to route it through the native player pipeline.

---

## Media Pausing on Close / Navigation

### WebView Media

The `MutationObserver` on `#mediaModal`'s `class` attribute catches ALL close mechanisms:

| Close Method | Detection | Action |
|---|---|---|
| Close button | `class` changes → observer fires | Pause all video/audio, clear `src`, empty content |
| Tap outside modal | `class` changes → observer fires | Same |
| Escape key | `class` changes → observer fires | Same |
| `closeMediaModal()` JS call | `class` changes → observer fires | Same |

Additionally, `pagehide` and `visibilitychange` events pause all media when:
- The user navigates away from the page
- The app goes to the background
- The browser tab is hidden

### Native Player (Decrypted Video)

Closing the native player overlay:

1. `VideoControls.onClose` → `_closeNativePlayer()`
2. Dispatches `PlayerNativePlayerClosed`
3. `_onNativePlayerClosed` handler:
   - Runs JS `closeMediaModal()` in the WebView (cleanup + MutationObserver trigger)
   - Deletes the temp decrypted file via `secureDelete()`
   - Emits `PlayerReady` — WebView becomes interactive again

### App Lifecycle (Background)

```dart
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused ||
      state == AppLifecycleState.inactive ||
      state == AppLifecycleState.hidden) {
    _playerBloc.add(const PlayerBackPressed());
  }
}
```

`PlayerBackPressed` calls `repository.pauseMedia()` which:
1. Runs JS to pause all `<video>` / `<audio>` elements
2. Sets `navigator.mediaSession.playbackState = 'paused'`
3. Fires `window.onblur` (Android) to release audio focus

The WebView is **kept alive** in its current state — when the user returns, the page is exactly as they left it (no reload, no state loss).

---

## Storage Locations

| Data | Location | Lifetime |
|---|---|---|
| Downloaded ZIP | `<tempDir>/player_package.zip` | Deleted after extraction |
| Extracted package | `<tempDir>/player_extracted/` | Until app cache cleared or re-download |
| Decrypted temp files | `<tempDir>/player_extracted/_temp/` | Deleted on native player close or re-init |
| `config.json` | `<tempDir>/player_extracted/config.json` | Part of extracted package |

On Android, `<tempDir>` is `getTemporaryDirectory()` → `/data/user/0/com.example.lms_player/cache/`.

On iOS, `<tempDir>` is `NSTemporaryDirectory()`.

**No decrypted content is ever written to permanent storage** — it exists only in the `_temp/` subdirectory and is deleted immediately after use.

---

## Folder Structure

```
lib/
├── core/
│   ├── constants/
│   │   └── app_constants.dart          # ZIP URL, file names
│   ├── entities/
│   │   └── player_config.dart          # PlayerConfig model (key, iv, encryptedMedia)
│   └── errors/
│       └── failures.dart               # Failure types
│
├── features/
│   ├── download/
│   │   ├── data/repositories/download_repository_impl.dart
│   │   ├── domain/repositories/download_repository.dart
│   │   ├── presentation/
│   │   │   ├── bloc/   (download_bloc, download_event, download_state)
│   │   │   └── pages/home_page.dart
│   │
│   └── player/
│       ├── data/
│       │   ├── datasources/
│       │   │   ├── webview_datasource.dart       # WebViewController, JS bridge, load/decrypt
│       │   │   └── crypto_local_datasource.dart  # AES-256-CBC decryption
│       │   └── repositories/player_repository_impl.dart
│       ├── domain/repositories/player_repository.dart
│       └── presentation/
│           ├── bloc/   (player_bloc, player_event, player_state)
│           ├── pages/player_page.dart
│           └── widgets/video_controls.dart       # Native player play/pause/seek/close
│
├── main.dart
```

---

## Permissions

### Android (`AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

- `INTERNET` — required for downloading the ZIP and WebView content.
- `ACCESS_NETWORK_STATE` — allows checking network connectivity.
- `usesCleartextTraffic="false"` — only HTTPS is allowed for remote connections; cleartext is permitted only for `localhost` / `10.0.2.2` (emulator) via `network_security_config.xml`.
- `FileProvider` — enables WebView file access on Android 10+.

### iOS (`Info.plist`)

No additional permissions required — all network requests use HTTPS. The temporary directory is accessible without special entitlements.

---

## Building

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# iOS (requires macOS with Xcode)
flutter build ios
```

The release APK is output to `build/app/outputs/flutter-apk/app-release.apk`.
