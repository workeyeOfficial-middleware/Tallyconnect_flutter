// TallyConnect — Liquid Glass. Boots local storage, restores the saved
// session, builds the repository (real backend) and the app controller, and
// runs the shell.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_state.dart';
import 'app/providers.dart';
import 'core/design/tc_kit.dart';
import 'core/storage/local_storage.dart';
import 'data/repositories/api_tally_repository.dart';
import 'data/repositories/tally_repository.dart';
import 'presentation/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Color(0x00000000),
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  final LocalStorage store = await LocalStorage.open();
  // Real backend by default; `--dart-define=TC_MOCK=true` runs on sample data.
  final TallyRepository repo = kUseMock
      ? MockTallyRepository()
      : ApiTallyRepository();
  // A saved, unexpired login opens straight to Home and reloads the data.
  final bool restored = await repo.restoreSession();
  final AppController controller = AppController(
    store: store,
    repo: repo,
    startScreen: restored ? 'home' : 'login',
  );
  if (restored) unawaited(repo.refreshAll());
  runApp(
    ProviderScope(
      overrides: <Override>[
        repositoryProvider.overrideWithValue(repo),
        appProvider.overrideWith((Ref ref) => controller),
      ],
      child: const TallyConnectApp(),
    ),
  );
}

const bool kUseMock = bool.fromEnvironment('TC_MOCK');

class TallyConnectApp extends StatelessWidget {
  const TallyConnectApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TallyConnect',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: kFont,
      scaffoldBackgroundColor: const Color(0xFFE9EDF7),
      splashFactory: NoSplash.splashFactory,
      highlightColor: const Color(0x00000000),
      splashColor: const Color(0x00000000),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8C1D3F)),
    ),
    // The prototype is designed in fixed CSS pixels; the system font-size
    // setting must not re-flow its cards.
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: child!,
    ),
    home: const Shell(),
  );
}
