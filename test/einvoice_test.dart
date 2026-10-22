// E-invoices in the app (read only — created in TallyPrime): the report
// (counts, filters, From / To kept), an invoice's e-invoice section and its
// PDF with the QR + IRN, no access / demo / older server, and the screens at
// phone widths. Rows are shaped like Rajlaxmi's real invoices.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/share/pdf_builder.dart';
import 'package:tallyconnect_ui/core/share/share_doc.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

const String kQr = 'eyJhbGciOiJSUzI1NiIs'; // + padding below (946 chars)

Map<String, Object?> _row(
  String guid,
  String no, {
  String status = 'done',
  String date = '2026-10-02',
  List<String> alerts = const <String>[],
  int? daysLeft,
  String? ack = '2026-10-04',
}) => <String, Object?>{
  'voucher_guid': guid,
  'date': date,
  'voucher_type': 'Tally Service Invoice',
  'voucher_no': no,
  'party_name': 'Mehta Electricals',
  'party_gstin': '27AAIFM2182K1Z0',
  'registration_type': 'Regular',
  'company_gstin': '27AAFCR3058P1ZT',
  'place_of_supply': 'Maharashtra',
  'amount': 11800,
  'status': status,
  'irn': status == 'pending' ? null : '01352aca6a5d5f12468b${'0' * 44}',
  'ack_no': status == 'pending' ? null : '122528944683651',
  'ack_date': status == 'pending' ? null : ack,
  'eway_applicable': false,
  'eway': null,
  'days_since': 19,
  'days_left': daysLeft,
  'alerts': alerts,
  'signed_qr': status == 'pending' ? null : kQr + 'x' * 926,
};

void _seed(FakeBackend f) => f.einvRows.addAll(<Map<String, Object?>>[
  _row('V1', 'S/101'), // the synced Sales voucher V1: e-invoiced
  _row(
    'g-pend',
    'SRV/0130/26-27',
    status: 'pending',
    daysLeft: 5,
    alerts: <String>['due_soon'],
  ),
  _row(
    'g-cld',
    'CLD/0189/26-27',
    ack: '2024-05-28',
    alerts: <String>['ack_before_invoice'],
  ),
  _row('g-b2c', 'TSS/1000/26-27', status: 'not_needed'),
]);

Future<AppController> _start(
  FakeBackend f, {
  String as = 'ADMIN',
  LocalStorage? store,
}) async {
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', as);
  await r.refreshAll();
  final AppController c = AppController(
    store: store ?? LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
  );
  c.afterRefresh(quietOk: true);
  await c.checkFinancialAccess();
  return c;
}

ByteData _font(String w) =>
    ByteData.sublistView(File('assets/fonts/Figtree-$w.ttf').readAsBytesSync());

void main() {
  group('controller', () {
    test('report: counts, filters, From / To kept after restarting', () async {
      final FakeBackend f = FakeBackend();
      _seed(f);
      final LocalStorage store = LocalStorage.memory();
      final AppController c = await _start(f, store: store);
      c.openEinvoices();
      await pumpEventQueue();
      expect(c.screen, 'einvoices');
      final EinvList l = c.einvList!;
      expect(l.summary.done, 2);
      expect(l.summary.pending, 1);
      expect(l.summary.alerts, 2);
      expect(l.rows, hasLength(4));
      expect(l.rows.first.irn!.length, 64);
      expect(l.rows.first.signedQr, isNull); // the list never carries the QR
      // This financial year to today by default.
      final DateTime t = c.today;
      expect(
        f.einvCalls.last['from'],
        '${t.month >= 4 ? t.year : t.year - 1}-04-01',
      );

      c.setEinvStatus('pending');
      await pumpEventQueue();
      expect(f.einvCalls.last['status'], 'pending');
      expect(c.einvList!.rows.single.voucherNo, 'SRV/0130/26-27');
      expect(c.einvList!.rows.single.daysLeft, 5);
      expect(
        einvAlertLabel(c.einvList!.rows.single.alerts.single),
        contains('7 days'),
      );

      c.openEinvRange();
      expect(c.overlay, 'dateRange');
      c.setF('drFrom', '2026-10-01');
      c.setF('drTo', '2026-10-31');
      c.applyRange();
      await pumpEventQueue();
      expect(f.einvCalls.last['from'], '2026-10-01');
      c.dispose();
      final AppController d = await _start(f, store: store);
      expect(d.einvRange, (DateTime(2026, 10), DateTime(2026, 10, 31)));
      d.dispose();
    });

    test(
      'an invoice: its e-invoice section and its PDF with the QR + IRN',
      () async {
        final FakeBackend f = FakeBackend();
        _seed(f);
        final AppController c = await _start(f);
        final Voucher v = c.repo.vouchers().firstWhere(
          (Voucher x) => x.guid == 'V1',
        );
        c.go('entryDetail', <String, Object?>{'entry': v});
        await pumpEventQueue();
        expect(c.einvOf(v)!.status, EinvStatus.done);
        expect(c.einvOf(v)!.signedQr!.length, 946);
        final ShareDoc d = await c.voucherDoc(v);
        expect(d.einvoice, isNotNull);
        expect(d.einvoice!.ackNo, '122528944683651');
        expect(d.einvoice!.qr!.length, 946);
        // The real PDF builds with the QR code.
        final Uint8List b = await buildPdf(
          d,
          fonts: DocFonts.fromBytes(
            regular: _font('Regular'),
            bold: _font('Bold'),
            extraBold: _font('ExtraBold'),
          ),
          accentArgb: 0xFF8C1D3F,
        );
        expect(String.fromCharCodes(b.take(5)), '%PDF-');
        // An invoice without an e-invoice: the PDF is as before.
        f.einvRows.clear();
        c.einvSel = null;
        expect((await c.voucherDoc(v)).einvoice, isNull);
        c.dispose();
      },
    );

    test('a report row not on the phone: details sheet', () async {
      final FakeBackend f = FakeBackend();
      _seed(f);
      final AppController c = await _start(f);
      c.openEinvoices();
      await pumpEventQueue();
      c.openEinvRow(
        c.einvList!.rows.firstWhere((EinvRow r) => r.voucherGuid == 'g-cld'),
      );
      expect(c.overlay, 'einvRow');
      expect(c.einvSel!.alerts, <String>['ack_before_invoice']);
      // A row whose invoice is synced opens the invoice.
      c.closeOv();
      c.openEinvRow(
        c.einvList!.rows.firstWhere((EinvRow r) => r.voucherGuid == 'V1'),
      );
      expect(c.screen, 'entryDetail');
      c.dispose();
    });

    test('no access / demo / older server: nothing breaks', () async {
      // A team member without financial report access: no lookups at all.
      final FakeBackend f = FakeBackend()..finAllowed = false;
      _seed(f);
      final AppController c = await _start(f, as: 'USER');
      final Voucher v = c.repo.vouchers().firstWhere(
        (Voucher x) => x.guid == 'V1',
      );
      c.go('entryDetail', <String, Object?>{'entry': v});
      await pumpEventQueue();
      expect(c.einvOf(v), isNull);
      expect(f.einvCalls, isEmpty);
      expect((await c.voucherDoc(v)).einvoice, isNull);
      c.dispose();

      final FakeBackend o = FakeBackend()..einvMissing = true;
      final AppController e = await _start(o);
      e.openEinvoices();
      await pumpEventQueue();
      expect(e.einvError, contains('not available on the server yet'));
      expect(e.loggedIn, isTrue); // the missing route never signs out
      final Voucher w = e.repo.vouchers().firstWhere(
        (Voucher x) => x.guid == 'V1',
      );
      e.go('entryDetail', <String, Object?>{'entry': w});
      await pumpEventQueue();
      expect(e.einvOf(w), isNull);
      expect(
        o.einvCalls.where(
          (Map<String, Object?> x) => '${x['path']}'.contains('/voucher/V1'),
        ),
        isNotEmpty,
      );
      e.dispose();
    });
  });

  group('screens', () {
    setUpAll(loadFigtree);

    for (final double w in <double>[320, 412]) {
      testWidgets(
        'Reports tile → E-invoices → a row; invoice section at ${w.toInt()} px',
        (WidgetTester t) async {
          t.view.physicalSize = Size(w * 3, 760 * 3);
          t.view.devicePixelRatio = 3;
          addTearDown(t.view.reset);
          final FakeBackend f = FakeBackend();
          _seed(f);
          final AppController c = await _start(f);
          await t.pumpWidget(
            ProviderScope(
              overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
              child: const TallyConnectApp(),
            ),
          );
          Future<void> settle() async {
            for (int i = 0; i < 8; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
          }

          c.go('reports');
          await settle();
          final Finder tile = find.byKey(const ValueKey<String>('einvTile'));
          await t.scrollUntilVisible(
            tile,
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(tile, findsOneWidget);
          // Clear of the bottom tab bar.
          await t.drag(find.byType(Scrollable).first, const Offset(0, -160));
          await settle();
          await t.tap(tile);
          await settle();
          expect(c.screen, 'einvoices');
          expect(find.text('E-invoiced'), findsWidgets);
          expect(
            find.byKey(const ValueKey<String>('einvRow-g-pend')),
            findsOneWidget,
          );
          expect(
            find.text('5 days left', findRichText: true),
            findsNothing,
          ); // inside the line
          expect(find.textContaining('5 days left'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.tap(find.byKey(const ValueKey<String>('einvFilter-alerts')));
          await settle();
          expect(
            find.byKey(const ValueKey<String>('einvRow-g-b2c')),
            findsNothing,
          );
          final Finder cld = find.byKey(
            const ValueKey<String>('einvRow-g-cld'),
          );
          await t.ensureVisible(cld);
          await t.tap(cld);
          await settle();
          expect(
            find.byKey(const ValueKey<String>('einvRowSheet')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey<String>('einvAlert-ack_before_invoice')),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          c.closeOv();
          await settle();
          // The invoice screen: its e-invoice section.
          final Voucher v = c.repo.vouchers().firstWhere(
            (Voucher x) => x.guid == 'V1',
          );
          c.go('entryDetail', <String, Object?>{'entry': v});
          await settle();
          final Finder sec = find.byKey(const ValueKey<String>('einvSection'));
          await t.scrollUntilVisible(
            sec,
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(sec, findsOneWidget);
          expect(find.text('122528944683651'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pump(const Duration(seconds: 6));
        },
      );
    }
  });
}
