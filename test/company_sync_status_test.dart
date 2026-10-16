// Companies screen: each company's sync line from the server, including the
// multi-company Agent's states (progress %, not open in Tally, error,
// another computer, no news) — older servers keep the old text.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/api/adapters.dart' show syncFrom;
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';

import 'api_integration_test.dart' show FakeBackend;

Future<String> lineFor(Map<String, Object?> extra) async {
  final FakeBackend f = FakeBackend()..syncExtra = extra;
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', 'ADMIN');
  await r.refreshAll();
  final AppController c = AppController(
    store: LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
  );
  c.afterRefresh(quietOk: true);
  final Company co = r.companies().firstWhere(
    (Company x) => r.syncInfo(x.id) != null,
  );
  final String s = c.syncText(co.id);
  c.dispose();
  return s;
}

void main() {
  test('server answer → SyncInfo (older servers: no extra fields)', () {
    final SyncInfo a = syncFrom(<String, Object?>{
      'last_sync_at': '2026-10-16T05:00:00.000Z',
      'sync_in_progress': true,
      'state': 'syncing',
      'percent': 45.4,
      'last_error': '  ',
    });
    expect(a.inProgress, isTrue);
    expect(a.state, 'syncing');
    expect(a.percent, 45);
    expect(a.error, isNull);
    final SyncInfo b = syncFrom(<String, Object?>{
      'last_sync_at': null,
      'sync_in_progress': false,
    });
    expect((b.state, b.percent, b.error), (null, null, null));
  });

  test('the Companies screen line for each state', () async {
    expect(await lineFor(<String, Object?>{}), startsWith('Synced '));
    expect(
      await lineFor(<String, Object?>{
        'sync_in_progress': true,
        'state': 'syncing',
        'percent': 45,
      }),
      'Syncing now · 45%',
    );
    expect(
      await lineFor(<String, Object?>{'state': 'not_open'}),
      startsWith('Not open in Tally on the sync computer · last synced'),
    );
    expect(
      await lineFor(<String, Object?>{
        'state': 'error',
        'last_error': 'Tally is not reachable',
      }),
      'Last sync failed: Tally is not reachable',
    );
    expect(
      await lineFor(<String, Object?>{'state': 'locked'}),
      startsWith('Being synced by another computer'),
    );
    expect(
      await lineFor(<String, Object?>{'state': 'stalled'}),
      startsWith('No news from the sync computer'),
    );
  });
}
