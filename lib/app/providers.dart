// Riverpod wiring: UI → appProvider (AppController) → repositoryProvider
// (TallyRepository: ApiTallyRepository for the real backend, or
// MockTallyRepository for sample data). Both are created in main() after
// storage and the saved session are opened, and injected with overrides.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/tally_repository.dart';
import 'app_state.dart';

final Provider<TallyRepository> repositoryProvider = Provider<TallyRepository>(
  (Ref ref) => throw UnimplementedError(
    'repositoryProvider must be overridden in main()',
  ),
);

final ChangeNotifierProvider<AppController> appProvider =
    ChangeNotifierProvider<AppController>(
      (Ref ref) =>
          throw UnimplementedError('appProvider must be overridden in main()'),
    );
