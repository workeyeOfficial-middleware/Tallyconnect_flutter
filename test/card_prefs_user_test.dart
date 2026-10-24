// Card preferences are kept per signed-in user on a shared phone: a card
// list's pins / order / hidden cards and the Home layout (cards placed,
// hidden) of one user never show for another; the phone's layout from
// before carries over to each user the first time.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart'
    show DataSet;
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';

import 'api_integration_test.dart' show FakeBackend;

Future<AppController> _as(String email, LocalStorage store) async {
  final FakeBackend f = FakeBackend();
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login(email, 'secret', 'ADMIN');
  await r.refreshAll();
  await r.ensure(DataSet.ledgers);
  final AppController c = AppController(
    store: store,
    repo: r,
    startScreen: 'home',
  );
  c.afterRefresh(quietOk: true);
  await pumpEventQueue();
  return c;
}

void main() {
  test('pins, Home cards and hidden cards follow the user', () async {
    final LocalStorage store = LocalStorage.memory();
    // Before anyone signs in on this build: a pin saved for the phone.
    store.save(LocalStorage.kLists, <String, Object?>{
      'teamCards': <String, Object?>{
        'pinned': <String>['leave'],
      },
    });

    final AppController a = await _as('ravi@x.in', store);
    // The phone's pin carried over to the first user.
    expect(a.listPrefs['teamCards']?.pinned, <String>['leave']);
    // Ravi pins a Sales Team card and puts Today's check-ins on Home.
    a.cmenu = const CMenu('teamCards', 'attEmployees', 0, 0);
    a.cmPin();
    expect(a.listPrefs['teamCards']!.pinned, contains('attEmployees'));
    a.toggleOnHome('attToday');
    expect(a.onHome('attToday'), isTrue);
    final List<String> home = a
        .curPages()
        .expand((List<String> p) => p)
        .toList();
    a.hideWidget(home.firstWhere((String id) => id != 'attToday'));
    final int hiddenA = a.hidList().length;
    expect(hiddenA, greaterThan(0));
    a.dispose();

    // Another user on the same phone: none of Ravi's changes.
    final AppController b = await _as('asha@x.in', store);
    expect(
      b.listPrefs['teamCards']?.pinned ?? <String>[],
      isNot(contains('attEmployees')),
    );
    expect(b.onHome('attToday'), isFalse);
    expect(b.hidList(), isEmpty);
    b.dispose();

    // Ravi again: his layout is back.
    final AppController a2 = await _as('ravi@x.in', store);
    expect(a2.listPrefs['teamCards']!.pinned, contains('attEmployees'));
    expect(a2.onHome('attToday'), isTrue);
    expect(a2.hidList(), hasLength(hiddenA));
    a2.dispose();
  });
}
