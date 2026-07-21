import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'providers/auth_provider.dart';
import 'providers/community_provider.dart';
import 'providers/library_provider.dart';
import 'providers/player_provider.dart';
import 'screens/splash_gate.dart';
import 'services/api_service.dart';
import 'services/download_service.dart';
import 'theme/app_theme.dart';

class HarmonyApp extends StatelessWidget {
  const HarmonyApp({super.key, required this.api});

  final ApiService api;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => AuthProvider(api)),
        ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
        ChangeNotifierProvider(create: (_) => CommunityProvider(api)),
        ChangeNotifierProvider.value(value: DownloadService.instance),
        ChangeNotifierProxyProvider<LibraryProvider, PlayerProvider>(
          create: (ctx) => PlayerProvider(ctx.read<LibraryProvider>()),
          update: (ctx, library, previous) => previous ?? PlayerProvider(library),
        ),
      ],
      child: Consumer<AppState>(
        builder: (context, appState, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'ReyMusic',
            theme: appState.themeOption.themeData,
            home: const SplashGate(),
          );
        },
      ),
    );
  }
}
