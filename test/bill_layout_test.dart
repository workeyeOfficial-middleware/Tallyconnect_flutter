// Bill PDF layout: saved shape, standard = the bill as before, and the PDF
// builds with every field off, with a logo and with own text.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/core/share/bill_layout.dart';
import 'package:tallyconnect_ui/core/share/pdf_builder.dart';
import 'package:tallyconnect_ui/core/share/share_doc.dart';
import 'package:tallyconnect_ui/data/models/models.dart';

ByteData _font(String w) =>
    ByteData.sublistView(File('assets/fonts/Figtree-$w.ttf').readAsBytesSync());

/// A real PNG (the bundled TallyConnect logo).
final Uint8List _png = File('assets/images/tc_logo.png').readAsBytesSync();

void main() {
  test('saved and read back; unknown values keep the standard', () {
    final BillLayout l = BillLayout.standard
        .toggled('hsn')
        .toggled('footer')
        .copyWith(const <String, bool>{}, 'GSTIN: 27AAA\nMumbai', 'Thanks');
    final BillLayout back = BillLayout.fromJson(l.toJson());
    expect(back, l);
    expect(back.showHsn, isFalse);
    expect(back.showFooter, isFalse);
    expect(back.sellerLines, <String>['GSTIN: 27AAA', 'Mumbai']);
    expect(back.terms, 'Thanks');
    expect(BillLayout.fromJson(null), BillLayout.standard);
    expect(BillLayout.fromJson(<String, Object?>{'hsn': 'no'}).showHsn, isTrue);
    expect(
      BillLayout.standard
          .copyWith(const <String, bool>{}, 'x' * 2000)
          .seller
          .length,
      BillLayout.kMaxText,
    );
    for (final (String, String) f in BillLayout.kFields) {
      expect(BillLayout.standard.on(f.$1), isTrue, reason: f.$1);
    }
  });

  test('a layout travels with the bill (e-invoice / demo copies)', () {
    final ShareDoc d = docInvoice(
      const PdfInfo(
        party: 'Mehta',
        no: 'S/1',
        date: '01 Oct 2026',
        due: '15 Oct 2026',
        total: 1180,
        kind: 'Sales',
        city: 'Pune',
        recv: true,
      ),
      'Rajlaxmi Traders',
    );
    expect(d.layout, isNull);
    final BillLayout l = BillLayout.standard.toggled('due');
    final ShareDoc s = d.withLayout(l, _png);
    expect(s.layout, l);
    expect(s.asDemo().layout, l);
    expect(s.withEinvoice(null).logo, _png);
    expect(s.fileName, d.fileName);
    expect(s.text, d.text);
  });

  test('the PDF builds with any layout', () async {
    final DocFonts fonts = DocFonts.fromBytes(
      regular: _font('Regular'),
      bold: _font('Bold'),
      extraBold: _font('ExtraBold'),
    );
    final ShareDoc d = docInvoice(
      const PdfInfo(
        party: 'Mehta',
        no: 'S/1',
        date: '01 Oct 2026',
        due: '15 Oct 2026',
        total: 1180,
        kind: 'Sales',
        city: 'Pune',
        recv: true,
        lines: <BillLine>[BillLine('Wire', '8544', '2', '₹500', 1000)],
        ledger: <LedgerLine>[LedgerLine('Mehta', 1180, true)],
      ),
      'Rajlaxmi Traders',
    );
    BillLayout none = BillLayout.standard;
    for (final (String, String) f in BillLayout.kFields) {
      none = none.toggled(f.$1);
    }
    for (final ShareDoc x in <ShareDoc>[
      d,
      d.withLayout(BillLayout.standard, _png),
      d.withLayout(none, _png),
      d.withLayout(
        BillLayout.standard
            .toggled('hsn')
            .copyWith(const <String, bool>{}, 'GSTIN: 27AAA', 'Bank: HDFC'),
        _png,
      ),
    ]) {
      final Uint8List b = await buildPdf(
        x,
        fonts: fonts,
        accentArgb: 0xFF8C1D3F,
      );
      expect(String.fromCharCodes(b.take(5)), '%PDF-');
    }
  });
}
