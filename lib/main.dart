import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lms_player/features/download/data/repositories/download_repository_impl.dart';
import 'package:lms_player/features/download/presentation/bloc/download_bloc.dart';
import 'package:lms_player/features/download/presentation/pages/home_page.dart';
import 'package:lms_player/features/player/data/datasources/webview_datasource.dart';
import 'package:lms_player/features/player/data/repositories/player_repository_impl.dart';
import 'package:lms_player/features/player/presentation/bloc/player_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const HostPortFlipBookApp());
}

class HostPortFlipBookApp extends StatelessWidget {
  const HostPortFlipBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ── Download feature dependencies ──
    final downloadRepository = DownloadRepositoryImpl();

    // ── Player feature dependencies ──
    final webViewDataSource = WebViewDataSource();
    final playerRepository = PlayerRepositoryImpl(
      dataSource: webViewDataSource,
    );
    final playerBloc = PlayerBloc(repository: playerRepository);

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => DownloadBloc(repository: downloadRepository),
        ),
        BlocProvider.value(value: playerBloc),
      ],
      child: MaterialApp(
        title: 'HostPort Flip Book',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1A73E8),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1A73E8),
            foregroundColor: Colors.white,
            elevation: 2,
          ),
        ),
        home: const HomePage(),
      ),
    );
  }
}
