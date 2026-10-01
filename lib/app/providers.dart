// Riverpod wiring. The controller instance is created in main() (after the
// storage is opened) and injected with an override.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_state.dart';

final ChangeNotifierProvider<AppController> appProvider =
    ChangeNotifierProvider<AppController>(
      (Ref ref) =>
          throw UnimplementedError('appProvider must be overridden in main()'),
    );
