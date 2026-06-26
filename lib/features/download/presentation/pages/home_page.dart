import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:lms_player/features/download/presentation/bloc/download_bloc.dart';
import 'package:lms_player/features/download/presentation/bloc/download_event.dart';
import 'package:lms_player/features/download/presentation/bloc/download_state.dart';
import 'package:lms_player/features/player/presentation/pages/player_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    _checkPackage();
  }

  Future<void> _checkPackage() async {
    final dir = await getTemporaryDirectory();
    if (!mounted) return;
    context
        .read<DownloadBloc>()
        .add(CheckPackageRequested(tempDirPath: dir.path));
  }

  Future<void> _startDownload() async {
    final dir = await getTemporaryDirectory();
    if (!mounted) return;
    context
        .read<DownloadBloc>()
        .add(DownloadRequested(tempDirPath: dir.path));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        title: const Text('HostPort Flip Book'),
        actions: [
          BlocBuilder<DownloadBloc, DownloadState>(
            builder: (context, state) {
              if (state is DownloadSuccess) {
                return IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Re-download',
                  onPressed: _startDownload,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: BlocConsumer<DownloadBloc, DownloadState>(
              listener: (context, state) {
                if (state is DownloadSuccess) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlayerPage(
                        packageDirPath: state.packageDirPath,
                        config: state.config,
                      ),
                    ),
                  ).then((_) {
                    if (mounted) _checkPackage();
                  });
                }
              },
              builder: (context, state) {
                if (state is DownloadInProgress) {
                  return _buildDownloadingView(state);
                }
                if (state is DownloadFailure) {
                  return _buildErrorView(state);
                }
                if (state is DownloadSuccess) {
                  return _buildReadyView(state);
                }
                return _buildIdleView();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdleView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.play_circle_outline,
            size: 96, color: Color(0xFF1A73E8)),
        const SizedBox(height: 24),
        const Text(
          'HostPort Flip Book',
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

  Widget _buildDownloadingView(DownloadInProgress state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularPercentIndicator(
          radius: 70,
          lineWidth: 8,
          percent: state.progress.clamp(0.0, 1.0),
          center: Text(
            '${(state.progress * 100).toInt()}%',
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
          state.statusText,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildReadyView(DownloadSuccess state) {
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
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlayerPage(
                  packageDirPath: state.packageDirPath,
                  config: state.config,
                ),
              ),
            ).then((_) {
              if (mounted) _checkPackage();
            });
          },
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

  Widget _buildErrorView(DownloadFailure state) {
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
            state.error,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: _startDownload,
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
