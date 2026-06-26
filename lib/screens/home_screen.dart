import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';

import '../services/download_service.dart';
import '../services/config_service.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _downloadService = DownloadService();
  final _configService = ConfigService();

  _UiState _state = _UiState.idle;
  double _progress = 0.0;
  String _statusText = '';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _checkAndLoad();
  }

  // ── Init logic ─────────────────────────────────────────────────────────────

  Future<void> _checkAndLoad() async {
    final ready = await _downloadService.isPackageReady();
    if (ready && mounted) {
      setState(() => _state = _UiState.ready);
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _startDownload() async {
    setState(() {
      _state = _UiState.downloading;
      _progress = 0.0;
      _statusText = 'Initializing…';
      _errorText = null;
    });

    try {
      await _downloadService.downloadAndExtract(
        onProgress: (p, s) {
          if (mounted) setState(() { _progress = p; _statusText = s; });
        },
      );
      if (mounted) setState(() => _state = _UiState.ready);
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _UiState.error;
          _errorText = e.toString();
        });
      }
    }
  }

  Future<void> _openPlayer() async {
    try {
      final packageDir = await _downloadService.packageDir;
      final config = await _configService.loadConfig(packageDir.path);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            packageDirPath: packageDir.path,
            config: config,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open player: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _reDownload() async {
    setState(() {
      _state = _UiState.idle;
      _errorText = null;
    });
    await _startDownload();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        title: const Text('LMS Player'),
        actions: [
          if (_state == _UiState.ready)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Re-download',
              onPressed: _reDownload,
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _UiState.idle:
        return _buildIdleView();
      case _UiState.downloading:
        return _buildDownloadingView();
      case _UiState.ready:
        return _buildReadyView();
      case _UiState.error:
        return _buildErrorView();
    }
  }

  Widget _buildIdleView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.play_circle_outline,
            size: 96, color: Color(0xFF1A73E8)),
        const SizedBox(height: 24),
        const Text(
          'LMS Player',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Download the player package to get started.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 15),
        ),
        const SizedBox(height: 40),
        ElevatedButton.icon(
          onPressed: _startDownload,
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download Player Package'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A73E8),
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularPercentIndicator(
          radius: 70,
          lineWidth: 8,
          percent: _progress.clamp(0.0, 1.0),
          center: Text(
            '${(_progress * 100).toInt()}%',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          progressColor: const Color(0xFF1A73E8),
          backgroundColor: Colors.white12,
          circularStrokeCap: CircularStrokeCap.round,
          animation: true,
          animateFromLastPercent: true,
        ),
        const SizedBox(height: 28),
        Text(
          _statusText,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildReadyView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_outline,
            size: 80, color: Colors.greenAccent),
        const SizedBox(height: 20),
        const Text(
          'Package Ready',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'The player package is downloaded and ready.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 14),
        ),
        const SizedBox(height: 36),
        ElevatedButton.icon(
          onPressed: _openPlayer,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Open Player'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent,
            foregroundColor: Colors.black87,
            padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 72, color: Colors.redAccent),
        const SizedBox(height: 20),
        const Text(
          'Download Failed',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _errorText ?? 'Unknown error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: _reDownload,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry Download'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

enum _UiState { idle, downloading, ready, error }
