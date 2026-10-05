// Share / PDF / chart (new features) and the card-alignment fix.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/design/tc_kit.dart';
import 'package:tallyconnect_ui/core/share/doc_exporter.dart';
import 'package:tallyconnect_ui/core/share/pdf_builder.dart';
import 'package:tallyconnect_ui/core/share/report_data.dart';
import 'package:tallyconnect_ui/core/share/share_doc.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/mock/mock_data.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/tally_repository.dart';
import 'package:tallyconnect_ui/main.dart';
import 'package:tallyconnect_ui/presentation/widgets/report_chart.dart';

ByteData _font(String w) =>
    ByteData.sublistView(File('assets/fonts/Figtree-$w.ttf').readAsBytesSync());
DocFonts fonts() => DocFonts.fromBytes(
  regular: _font('Regular'),
  bold: _font('Bold'),
  extraBold: _font('ExtraBold'),
);

class FakeExporter implements DocExporter {
  final List<String> shared = <String>[];
  final List<String> saved = <String>[];
  @override
  Future<Uint8List> pdf(ShareDoc d, int accentArgb) async =>
      Uint8List.fromList('%PDF-fake ${d.title}'.codeUnits);
  @override
  Future<void> share(ShareDoc d, Uint8List bytes) async => shared.add(d.title);
  @override
  Future<String> download(String fileName, Uint8List bytes) async {
    saved.add(fileName);
    return 'Download/$fileName';
  }

  @override
  Future<List<ui.Image>> raster(Uint8List bytes) async => <ui.Image>[];
}

Future<void> loadFigtree() async {
  final FontLoader l = FontLoader('Figtree');
  for (final String w in <String>[
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
  ]) {
    l.addFont(Future<ByteData>.value(_font(w)));
  }
  await l.load();
}

Future<AppController> boot(
  WidgetTester t,
  FakeExporter fx, {
  String start = 'home',
}) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final AppController c = AppController(
    store: LocalStorage.memory(),
    startScreen: start,
    exporter: fx,
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
      child: const TallyConnectApp(),
    ),
  );
  await settle(t);
  return c;
}

Future<void> settle(WidgetTester t) async {
  for (int i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final TallyRepository repo = MockTallyRepository();
  setUpAll(loadFigtree);

  group('report data (unchanged values) and chart series', () {
    test('totals match the prototype', () {
      expect(reportData(repo, 'top').total, '₹3,35,710');
      expect(reportData(repo, 'exp').total, '₹1,86,450');
      expect(reportData(repo, 'day').total, '₹9,18,490');
      expect(reportData(repo, 'sreg').total, '₹3,48,690');
      expect(reportData(repo, 'stock').total, '₹2,45,760');
    });
    test('charts use the same rows; no chart without numbers', () {
      final ReportData top = reportData(repo, 'top');
      expect(
        top.points.map((ChartPoint p) => p.value),
        top.rows.map((ReportRow r) => r.value),
      );
      expect(reportData(repo, 'inC').hasChart, isFalse);
      expect(reportData(repo, 'inI').hasChart, isFalse);
      final ReportData day = reportData(repo, 'day');
      expect(day.lineFirst, isTrue);
      expect(
        day.points.fold<num>(0, (num s, ChartPoint p) => s + p.value),
        918490,
      );
      expect(day.points.first.label, '2 Sep');
    });
    test('compact axis labels', () {
      expect(compactInr(112100), '₹1.1L');
      expect(compactInr(48000), '₹48K');
      expect(compactInr(950), '₹950');
    });
  });

  group('share documents', () {
    test('invoice carries the bill lines and GST', () {
      const PdfInfo s9 = PdfInfo(
        party: 'Shree Balaji Traders',
        no: 'Sales 9',
        date: '21 Sep 2026',
        due: '06 Oct 2026',
        total: 112100,
        kind: 'Sales bill',
        city: 'Mumbai',
        recv: true,
        lines: kSales9,
      );
      final ShareDoc d = docInvoice(s9, 'GI Apr 25-26');
      expect(d.fileName, 'Sales_9.pdf');
      expect(d.text, contains('Polycab FR Wire 1.0 sq mm (90 m)'));
      expect(d.text, contains('CGST @ 9%: ₹8,550'));
      expect(d.text, contains('Total: ₹1,12,100'));
      // No item lines from the server → no invented subtotal / GST split.
      final InvoiceSpec p = invoiceOf(
        const PdfInfo(
          party: 'Kiran',
          no: 'PI-0005',
          date: '',
          due: '',
          total: 48380,
          kind: 'Purchase bill',
          city: 'Ludhiana',
          recv: false,
        ),
      );
      expect(p.heading, 'PURCHASE BILL');
      expect(p.sub, isNull);
      expect(p.taxes, isEmpty);
      expect(p.lines, isEmpty);
      expect(p.total, 48380);
      // Real lines whose sum differs from the total show the difference as is.
      final InvoiceSpec q = invoiceOf(
        const PdfInfo(
          party: 'A',
          no: 'S-1',
          date: '',
          due: '',
          total: 1180,
          kind: 'Sales',
          city: '',
          lines: <BillLine>[BillLine('Wire', '', '1', '', 1000)],
        ),
      );
      expect(q.sub, 1000);
      expect(q.taxes.single.$2, 180);
    });
    test('report / list docs contain the actual data', () {
      final ShareDoc r = docReport(reportData(repo, 'top'), 'GI Apr 25-26');
      expect(r.text, contains('Shree Balaji Traders'));
      expect(r.text, contains('Top 5 owe you: ₹3,35,710'));
      expect(r.fileName, 'TallyConnect_Report_Top_customers.pdf');
      final ShareDoc v = docVouchers(
        'All Vouchers',
        kVouchers,
        'GI',
        'This month',
      );
      expect(v.table!.rows.length, 21);
      expect(v.text, contains('Total value: ₹9,18,490'));
    });
    test('real PDF bytes are produced for every layout', () async {
      for (final ShareDoc d in <ShareDoc>[
        docInvoice(
          const PdfInfo(
            party: 'A',
            no: 'Sales 9',
            date: 'd',
            due: 'd',
            total: 112100,
            kind: 'Sales bill',
            city: 'Mumbai',
            recv: true,
            lines: kSales9,
          ),
          'GI',
        ),
        docReport(reportData(repo, 'day'), 'GI'),
        docItems(kItems, 'GI'),
        docEntry(kVouchers.last, 'GI'),
      ]) {
        final Uint8List b = await buildPdf(
          d,
          fonts: fonts(),
          accentArgb: 0xFF8C1D3F,
        );
        expect(String.fromCharCodes(b.take(5)), '%PDF-');
        expect(b.length, greaterThan(2000));
      }
    });
  });

  group('controller share actions', () {
    test('every long-press card has a share document', () {
      final AppController c = AppController(
        store: LocalStorage.memory(),
        startScreen: 'home',
        exporter: FakeExporter(),
      );
      for (final String id in <String>[
        'newEntry',
        'money',
        ...kShortcuts.keys,
      ]) {
        expect(c.docForCard('home', id), isNotNull, reason: id);
      }
      expect(c.docForCard('notifs', 'n1')!.title, 'Payment received');
      expect(c.docForCard('vouchers', 'Sales 9')!.title, contains('Sales 9'));
      expect(c.docForCard('bills', 'Sales 9'), isNotNull);
      expect(c.docForCard('items', kItems.first.name), isNotNull);
      expect(c.docForCard('party', kParties.first.name), isNotNull);
      expect(c.docForCard('reports', 'exp')!.title, 'Expenses');
      expect(c.docForCard('acts', 'a1'), isNotNull);
      expect(
        c.docForCard('team', 'priya.shah@example.com')!.title,
        'Priya Shah',
      );
      c.dispose();
    });
    test('share, download and preview', () async {
      final FakeExporter fx = FakeExporter();
      final AppController c = AppController(
        store: LocalStorage.memory(),
        startScreen: 'home',
        exporter: fx,
      );
      final ShareDoc d = docReport(reportData(repo, 'top'), 'GI');
      await c.shareDoc(d);
      expect(fx.shared, <String>['Top customers']);
      await c.downloadDoc(d);
      expect(fx.saved, <String>['TallyConnect_Report_Top_customers.pdf']);
      expect(c.toast, 'Saved to Downloads');
      c.previewDoc(d);
      expect(c.overlay, 'doc');
      expect(await c.docBytes, isNotNull);
      c.openCardMenu('reports', 'exp', const Rect.fromLTWH(10, 300, 160, 150));
      c.cmShare();
      await Future<void>.delayed(Duration.zero);
      expect(fx.shared.last, 'Expenses');
      expect(c.cmenu, isNull);
      c.dispose();
    });
  });

  group('widgets', () {
    testWidgets('card menu offers Share after Pin/Open/Drag/Hide', (
      WidgetTester t,
    ) async {
      final FakeExporter fx = FakeExporter();
      final AppController c = await boot(t, fx);
      c.openCardMenu('home', 'items', const Rect.fromLTWH(20, 300, 110, 136));
      await settle(t);
      final List<double> ys = <String>[
        'Pin',
        'Open',
        'Drag',
        'Hide',
        'Share',
      ].map((String s) => t.getCenter(find.text(s)).dy).toList();
      for (int i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]));
      }
      await t.tap(find.text('Share'));
      await settle(t);
      expect(fx.shared.single, 'Items · Stock summary');
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('report detail: chart first, list below, type switch', (
      WidgetTester t,
    ) async {
      final AppController c = await boot(t, FakeExporter());
      c.go('report', <String, Object?>{'report': 'top'});
      await settle(t);
      expect(find.byType(ReportChart), findsOneWidget);
      final double chartY = t.getTopLeft(find.byType(ReportChart)).dy;
      final double listY = t.getTopLeft(find.text('Top 5 owe you')).dy;
      expect(chartY, lessThan(listY));
      await t.tap(find.text('Pie'));
      await settle(t);
      expect(c.chartType['top'], 'pie');
      await t.tap(find.text('Line'));
      await settle(t);
      expect(c.chartType['top'], 'line');
      c.go('report', <String, Object?>{'report': 'inC'});
      await settle(t);
      expect(find.byType(ReportChart), findsNothing);
      expect(find.text('Quiet customers'), findsWidgets);
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('cards that share a row have equal size and fill their cell', (
      WidgetTester t,
    ) async {
      final AppController c = await boot(t, FakeExporter());
      Rect tile(String label) => t.getRect(
        find.ancestor(of: find.text(label), matching: find.byType(Glass)).first,
      );
      // Home shortcut tiles: three equal columns, equal heights per row.
      final Rect a = tile('Items'), b = tile('Party'), v = tile('Vouchers');
      expect(a.width, closeTo(b.width, .5));
      expect(b.width, closeTo(v.width, .5));
      expect(a.height, closeTo(v.height, .5));
      expect(a.width, closeTo((390 - 32 - 24) / 3, .6));
      // Quick buttons in the New Entry card: four equal columns.
      Rect quick(String l) => t.getRect(
        find.ancestor(of: find.text(l), matching: find.byType(Tap)).first,
      );
      final double q = quick('Sale').width;
      for (final String l in <String>['Purchase', 'Receipt', 'Payment']) {
        expect(quick(l).width, closeTo(q, .5), reason: l);
      }
      // Payment modes in the sale flow: five equal buttons.
      c.startFlow('sales');
      c.flowNext();
      c.flowNext();
      await settle(t);
      final double m = quick('Cash').width;
      for (final String l in <String>['Bank', 'UPI', 'Cheque', 'Other']) {
        expect(quick(l).width, closeTo(m, .5), reason: l);
      }
      // Reports: two cards per row with equal heights.
      c.jump('reports');
      await settle(t);
      final Rect r1 = tile('Top customers'), r2 = tile('Expenses');
      expect(r1.height, closeTo(r2.height, .5));
      expect(r1.width, closeTo(r2.width, .5));
      await t.pump(const Duration(seconds: 3));
    });
  });
}
