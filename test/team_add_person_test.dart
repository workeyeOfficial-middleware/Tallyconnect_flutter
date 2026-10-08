// Sales Team → Add person: every field the create-user endpoint needs
// (POST /users: email + password) is collected and sent exactly; name /
// company-role / mobile stay on this phone and label the new member.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

Future<(FakeBackend, AppController, LocalStorage)> start() async {
  final FakeBackend f = FakeBackend();
  final ApiTallyRepository r = f.repo();
  await r.login('ravi@x.in', 'secret', 'ADMIN');
  await r.refreshAll();
  final LocalStorage s = LocalStorage.memory();
  final AppController c = AppController(
    store: s,
    repo: r,
    startScreen: 'home',
  );
  return (f, c, s);
}

void fill(AppController c, {String pass = 'Welcome@1'}) {
  c.setF('nuName', 'Rohit Kumar');
  c.setF('nuEmail', ' Rohit.K@Company.com ');
  c.setF('nuRole', 'Sales Executive');
  c.setF('nuPhone', '+91 98765 43210');
  c.setF('nuPass', pass);
}

void main() {
  test('validation: name, valid email and a 6+ character password', () async {
    final (FakeBackend _, AppController c, LocalStorage _) = await start();
    c.openNewUser();
    expect(c.overlay, 'newUser');
    expect(c.newUserError, 'Enter the full name');
    c.setF('nuName', 'Rohit Kumar');
    c.setF('nuEmail', 'rohit@company');
    expect(c.newUserError, 'Enter a valid email address');
    c.setF('nuEmail', 'rohit@company.com');
    c.setF('nuPass', '12345');
    expect(c.newUserError, contains('at least 6'));
    c.suggestTempPass();
    expect(c.f('nuPass').length, 10);
    expect(c.showNuPass, isTrue);
    expect(c.newUserError, isNull);
    c.dispose();
  });

  test('creates the login with exactly email + password; shows the name', () async {
    final (FakeBackend f, AppController c, LocalStorage s) = await start();
    c.openNewUser();
    fill(c);
    await c.saveUser();
    final List<http.Request> sent = f.calls
        .where((http.Request q) => q.method == 'POST' && q.url.path == '/users')
        .toList();
    expect(sent, hasLength(1));
    expect(jsonDecode(sent.single.body), <String, Object?>{
      'email': 'rohit.k@company.com',
      'password': 'Welcome@1',
    });
    expect(f.violations, isEmpty);
    expect(c.overlay, isNull);
    expect(c.toast, contains('Rohit Kumar added'));
    expect(c.f('nuPass'), isEmpty); // not kept in the form
    // The reloaded team has the new login, labelled with the entered name
    // and role (the server only knows "rohit.k").
    final Member m = c.team.firstWhere(
      (Member x) => x.email == 'rohit.k@company.com',
    );
    expect(m.name, 'Rohit Kumar');
    expect(m.role, 'Sales Executive');
    // Kept on this phone across restarts.
    final AppController c2 = AppController(
      store: s,
      repo: c.repo,
      startScreen: 'home',
    );
    expect(
      c2.team.firstWhere((Member x) => x.email == 'rohit.k@company.com').name,
      'Rohit Kumar',
    );
    c2.dispose();
    c.dispose();
  });

  test('server errors are shown and nothing is kept', () async {
    final (FakeBackend f, AppController c, LocalStorage _) = await start();
    c.openNewUser();
    fill(c);
    c.setF('nuEmail', 'asha@x.in'); // exists on the server
    await c.saveUser();
    expect(c.toast, 'User already exists');
    expect(c.overlay, 'newUser'); // form stays open to correct
    expect(c.busy, isFalse);
    expect(f.createdUsers, isEmpty);
    c.dispose();
  });

  group('Add person sheet', () {
    setUpAll(loadFigtree);

    for (final double w in <double>[320, 390]) {
      testWidgets('all fields, no overflow at ${w.toInt()} wide', (
        WidgetTester t,
      ) async {
        t.view.physicalSize = Size(w * 3, 800 * 3);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        late FakeBackend f;
        late AppController c;
        await t.runAsync(() async {
          final (FakeBackend f0, AppController c0, LocalStorage _) =
              await start();
          f = f0;
          c = c0;
        });
        c.go('team');
        c.openNewUser();
        await t.pumpWidget(
          ProviderScope(
            overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
            child: const TallyConnectApp(),
          ),
        );
        for (int i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        for (final String l in <String>[
          'Full name',
          'Email address',
          'Company / Role',
          'Mobile number',
          'Temporary password',
        ]) {
          expect(
            find.textContaining(l, findRichText: true),
            findsWidgets,
            reason: l,
          );
        }
        expect(find.text('Create user'), findsOneWidget);
        expect(t.takeException(), isNull);
        expect(f.violations, isEmpty);
        await t.pump(const Duration(seconds: 6));
      });
    }
  });
}
