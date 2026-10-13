// Voice search in the global search sheet: the mic fills the existing
// search field and the existing search shows the results; permission,
// unavailable and error states; typing keeps working.
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

class FakeVoice implements VoiceInput {
  FakeVoice([this.start = VoiceStart.ok]);
  VoiceStart start;
  VoiceSession? session;
  int prepares = 0, listens = 0, stops = 0;

  @override
  Future<VoiceStart> prepare() async {
    prepares++;
    return start;
  }

  @override
  Future<void> listen(VoiceSession s) async {
    listens++;
    session = s;
  }

  @override
  Future<void> stop() async => stops++;
}

AppController _c(FakeVoice v) => AppController(
  store: LocalStorage.memory(),
  startScreen: 'home',
  voice: v,
);

void main() {
  group('voice search (controller)', () {
    test('spoken words fill the field and run the normal search', () async {
      final FakeVoice v = FakeVoice();
      final AppController c = _c(v)..openOverlay('search');
      await c.toggleVoiceSearch();
      expect(c.voiceOn, isTrue);
      expect(c.voiceNote, AppController.kVoiceListening);
      v.session!.onWords('Mehta', false); // partial
      expect(c.f('q'), 'Mehta'); // shown in the field at once
      v.session!.onWords('Mehta Electricals', true); // final
      expect(c.f('q'), 'Mehta Electricals');
      expect(c.voiceOn, isFalse); // a final result ends listening
      // Same 350 ms debounce as typing, then the existing search.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(c.q('q'), 'Mehta Electricals');
      expect(
        c.searchHits(c.q('q')).map((SearchHit h) => h.t),
        contains('Mehta Electricals'),
      );
      c.dispose();
    });

    test('tapping the mic again stops listening', () async {
      final FakeVoice v = FakeVoice();
      final AppController c = _c(v)..openOverlay('search');
      await c.toggleVoiceSearch();
      await c.toggleVoiceSearch();
      expect(v.stops, 1);
      expect(c.voiceOn, isFalse);
      expect(c.voiceNote, isNull);
      c.dispose();
    });

    test('permission denied: clear message, typing still works', () async {
      final FakeVoice v = FakeVoice(VoiceStart.denied);
      final AppController c = _c(v)..openOverlay('search');
      await c.toggleVoiceSearch();
      expect(c.voiceOn, isFalse);
      expect(c.voiceNote, AppController.kVoiceDenied);
      expect(v.listens, 0);
      c.setQuery('q', 'Wire');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(c.q('q'), 'Wire');
      c.dispose();
    });

    test('unsupported device (no speech service)', () async {
      final AppController c = AppController(
        store: LocalStorage.memory(),
        startScreen: 'home',
      )..openOverlay('search'); // default: NoVoiceInput
      await c.toggleVoiceSearch();
      expect(c.voiceOn, isFalse);
      expect(c.voiceNote, AppController.kVoiceUnavailable);
      c.dispose();
    });

    test('recognition errors become actionable messages', () async {
      final FakeVoice v = FakeVoice();
      final AppController c = _c(v)..openOverlay('search');
      for (final (String code, String want) in <(String, String)>[
        ('error_no_match', AppController.kVoiceNoMatch),
        ('error_speech_timeout', AppController.kVoiceNoMatch),
        ('error_network', AppController.kVoiceNetwork),
        ('error_insufficient_permissions', AppController.kVoiceDenied),
      ]) {
        await c.toggleVoiceSearch();
        v.session!.onError(code, true);
        expect(c.voiceOn, isFalse, reason: code);
        expect(c.voiceNote, want, reason: code);
      }
      await c.toggleVoiceSearch();
      v.session!.onError('error_client', false);
      expect(c.voiceNote, contains('error_client'));
      c.dispose();
    });

    test('closing search stops listening and clears the note', () async {
      final FakeVoice v = FakeVoice();
      final AppController c = _c(v)..openOverlay('search');
      await c.toggleVoiceSearch();
      c.closeOv();
      await Future<void>.delayed(Duration.zero);
      expect(v.stops, 1);
      expect(c.voiceOn, isFalse);
      expect(c.voiceNote, isNull);
      c.dispose();
    });
  });

  group('voice search (screen)', () {
    setUpAll(loadFigtree);

    testWidgets('mic in the search field at 320 px; words appear, results show', (
      WidgetTester t,
    ) async {
      t.view.physicalSize = const Size(320 * 3, 720 * 3);
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

      c.openOverlay('search');
      await settle();
      final Finder mic = find.byKey(const ValueKey<String>('voiceSearchBtn'));
      expect(mic, findsOneWidget);
      await t.tap(mic);
      await settle();
      expect(find.text(AppController.kVoiceListening), findsOneWidget);
      v.session!.onWords('Mehta Electricals', true);
      await settle();
      expect(
        find.descendant(
          of: find.byType(TextField),
          matching: find.text('Mehta Electricals'),
        ),
        findsWidgets,
      );
      expect(find.text('Mehta Electricals'), findsWidgets); // a result row
      expect(find.text(AppController.kVoiceListening), findsNothing);
      // Denied state is shown without breaking the sheet.
      v.start = VoiceStart.denied;
      await t.tap(mic);
      await settle();
      expect(find.text(AppController.kVoiceDenied), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
