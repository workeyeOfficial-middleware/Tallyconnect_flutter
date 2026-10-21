// Voice search in every search field (Items, Party, Outstanding, Team, pick
// sheets, Configure User): the mic fills that field and runs its own search
// as typing does; one field listens at a time; leaving the screen stops it.
// Plus the Home header: compact action buttons, profile for team members.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/voice/voice_input.dart';
import 'package:tallyconnect_ui/main.dart';

import 'screens_test.dart' show loadFigtree;
import 'voice_search_test.dart' show FakeVoice;

AppController _c(FakeVoice v) =>
    AppController(store: LocalStorage.memory(), startScreen: 'home', voice: v);

void main() {
  group('voice in search fields (controller)', () {
    test('each field gets the words and runs its own search', () async {
      final FakeVoice v = FakeVoice();
      final AppController c = _c(v);
      // Items / Party (debounced search, as typing).
      for (final String k in <String>[
        'itemQ',
        'partyQ',
        'pq',
        'pickQ',
        'tsQ',
      ]) {
        await c.toggleVoiceFor(k);
        expect(c.voiceOnFor(k), isTrue, reason: k);
        expect(c.voiceNoteFor(k), AppController.kVoiceListening, reason: k);
        expect(c.voiceNoteFor('q'), isNull, reason: k); // not another field's
        v.session!.onWords('Wire', true);
        expect(c.f(k), 'Wire', reason: k);
        expect(c.voiceOn, isFalse, reason: k);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(c.q(k), 'Wire', reason: k);
      }
      // Outstanding (its own filter) and the Team page.
      await c.toggleVoiceFor('outQuery');
      v.session!.onWords('Mehta', true);
      expect(c.outQuery, 'Mehta');
      await c.toggleVoiceFor('teamQ');
      v.session!.onWords('Asha', true);
      expect(c.f('teamQ'), 'Asha');
      c.dispose();
    });

    test(
      'another field\'s mic moves the listening; leaving stops it',
      () async {
        final FakeVoice v = FakeVoice();
        final AppController c = _c(v);
        c.go('items');
        await c.toggleVoiceFor('itemQ');
        await c.toggleVoiceFor('partyQ');
        expect(v.stops, 1);
        expect(c.voiceOnFor('partyQ'), isTrue);
        expect(c.voiceOnFor('itemQ'), isFalse);
        // Leaving the screen ends listening and its note.
        c.back();
        await Future<void>.delayed(Duration.zero);
        expect(v.stops, 2);
        expect(c.voiceOn, isFalse);
        expect(c.voiceNoteFor('partyQ'), isNull);
        c.dispose();
      },
    );

    test('permission denied: the note shows under that field only', () async {
      final FakeVoice v = FakeVoice(VoiceStart.denied);
      final AppController c = _c(v);
      await c.toggleVoiceFor('itemQ');
      expect(c.voiceNoteFor('itemQ'), AppController.kVoiceDenied);
      expect(c.voiceNoteFor('partyQ'), isNull);
      c.dispose();
    });
  });

  group('screens', () {
    setUpAll(loadFigtree);

    for (final double w in <double>[320, 360, 412]) {
      testWidgets('mics in Items, Party, Outstanding at ${w.toInt()} px', (
        WidgetTester t,
      ) async {
        t.view.physicalSize = Size(w * 3, 800 * 3);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        final FakeVoice v = FakeVoice();
        final AppController c = _c(v);
        await t.pumpWidget(
          ProviderScope(
            overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
            child: const TallyConnectApp(),
          ),
        );
        Future<void> settle() async {
          for (int i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        // Home header: compact 38 px actions (the wordmark leads).
        await settle();
        expect(
          t.getSize(find.byKey(const ValueKey<String>('feedbackBtn'))).width,
          closeTo(38, .5),
        );
        expect(t.takeException(), isNull);

        for (final (String, String) s in <(String, String)>[
          ('items', 'itemQ'),
          ('party', 'partyQ'),
        ]) {
          c.go(s.$1);
          await settle();
          final Finder mic = find.byKey(ValueKey<String>('voiceBtn-${s.$2}'));
          expect(mic, findsOneWidget, reason: s.$1);
          await t.tap(mic);
          await settle();
          expect(c.voiceOnFor(s.$2), isTrue, reason: s.$1);
          expect(find.text('Listening…'), findsOneWidget, reason: s.$1);
          v.session!.onWords('Wire', true);
          await t.pump(const Duration(milliseconds: 400));
          await settle();
          expect(c.q(s.$2), 'Wire', reason: s.$1);
          expect(t.takeException(), isNull, reason: s.$1);
        }
        // Outstanding: open its search, mic next to the close button.
        c.go('outHub');
        await settle();
        if (!c.outSearch) c.toggleOutSearch();
        await settle();
        expect(
          find.byKey(const ValueKey<String>('voiceBtn-outQuery')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 3));
      });
    }
  });
}
