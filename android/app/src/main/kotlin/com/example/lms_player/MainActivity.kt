package com.example.lms_player

import android.media.AudioManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var audioManager: AudioManager? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
    }

    override fun onPause() {
        super.onPause()
        // Abandon audio focus so media stops when app is backgrounded.
        // The Flutter-side WebViewService.pauseMedia() handles JS pause;
        // this ensures the Android audio stack also releases the focus.
        audioManager?.abandonAudioFocus(null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
    }
}
