// Renders a [ShareDoc] to a real PDF (A4). Bills use the prototype's invoice
// "paper" layout; everything else uses a TallyConnect-styled table/report.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/format.dart';
import 'share_doc.dart';

/// Figtree faces used in the PDF (loaded from the bundled TTFs).
class DocFonts {
  const DocFonts({
    required this.regular,
    required this.bold,
    required this.extraBold,
  });
  final pw.Font regular, bold, extraBold;

  factory DocFonts.fromBytes({
    required ByteData regular,
    required ByteData bold,
    required ByteData extraBold,
  }) => DocFonts(
    regular: pw.Font.ttf(regular),
    bold: pw.Font.ttf(bold),
    extraBold: pw.Font.ttf(extraBold),
  );
}

const PdfColor _ink = PdfColor.fromInt(0xFF16203A);
const PdfColor _mute = PdfColor.fromInt(0xFF6B7690);
const PdfColor _band = PdfColor.fromInt(0xFFEEF1F8);
const PdfColor _rule = PdfColor.fromInt(0xFFE6E9F1);

/// Figtree has no "↔" glyph.
String _safe(String s) => s.replaceAll('↔', '<->');

Future<Uint8List> buildPdf(
  ShareDoc d, {
  required DocFonts fonts,
  required int accentArgb,
  String? generated,
}) async {
  final String made = generated ?? dmy(DateTime.now());
  final PdfColor acc = PdfColor.fromInt(accentArgb);
  final pw.Document doc = pw.Document(
    title: d.title,
    author: 'TallyConnect',
    creator: 'TallyConnect',
  );
  final pw.ThemeData theme = pw.ThemeData.withFont(
    base: fonts.regular,
    bold: fonts.bold,
  );
  pw.TextStyle st(double size, {pw.Font? f, PdfColor c = _ink}) => pw.TextStyle(
    font: f ?? fonts.regular,
    fontSize: size,
    color: c,
    lineSpacing: 1.5,
  );

  final InvoiceSpec? iv = d.invoice;
  if (iv != null) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.fromLTRB(48, 54, 48, 48),
        build: (pw.Context c) {
          pw.Widget lt(pw.Widget a, pw.Widget b) => pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Flexible(child: a),
              pw.SizedBox(width: 12),
              b,
            ],
          );
          pw.Widget cell(String s, {bool r = false, bool head = false}) =>
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 7,
                ),
                child: pw.Text(
                  _safe(s),
                  textAlign: r ? pw.TextAlign.right : pw.TextAlign.left,
                  style: head ? st(10, f: fonts.bold) : st(11),
                ),
              );
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: <pw.Widget>[
              lt(
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(
                      d.company,
                      style: st(16, f: fonts.extraBold, c: acc),
                    ),
                    for (final String l in iv.seller)
                      pw.Text(_safe(l), style: st(11)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: <pw.Widget>[
                    pw.Text(iv.heading, style: st(15, f: fonts.extraBold)),
                    pw.RichText(
                      text: pw.TextSpan(
                        text: 'No: ',
                        style: st(11),
                        children: <pw.InlineSpan>[
                          pw.TextSpan(
                            text: iv.no,
                            style: st(11, f: fonts.bold),
                          ),
                        ],
                      ),
                    ),
                    pw.RichText(
                      text: pw.TextSpan(
                        text: 'Date: ',
                        style: st(11),
                        children: <pw.InlineSpan>[
                          pw.TextSpan(
                            text: iv.date,
                            style: st(11, f: fonts.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.Container(
                height: 1.4,
                color: acc,
                margin: const pw.EdgeInsets.symmetric(vertical: 12),
              ),
              lt(
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(iv.toLabel, style: st(9, c: _mute)),
                    pw.Text(iv.party, style: st(12, f: fonts.extraBold)),
                    if (iv.city.isNotEmpty) pw.Text(iv.city, style: st(11)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: <pw.Widget>[
                    pw.Text('DUE DATE', style: st(9, c: _mute)),
                    pw.Text(iv.due, style: st(12, f: fonts.extraBold)),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
              pw.Table(
                columnWidths: const <int, pw.TableColumnWidth>{
                  0: pw.FixedColumnWidth(24),
                  1: pw.FlexColumnWidth(5),
                  2: pw.FlexColumnWidth(1.6),
                  3: pw.FlexColumnWidth(1.6),
                  4: pw.FlexColumnWidth(1.8),
                  5: pw.FlexColumnWidth(2.2),
                },
                children: <pw.TableRow>[
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: _band),
                    children: <pw.Widget>[
                      cell('#', head: true),
                      cell('Item', head: true),
                      cell('HSN', head: true),
                      cell('Qty', head: true, r: true),
                      cell('Rate', head: true, r: true),
                      cell('Amount', head: true, r: true),
                    ],
                  ),
                  for (final (String, String, String, String, String, String) l
                      in iv.lines)
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: _rule)),
                      ),
                      children: <pw.Widget>[
                        cell(l.$1),
                        cell(l.$2),
                        cell(l.$3),
                        cell(l.$4, r: true),
                        cell(l.$5, r: true),
                        cell(l.$6, r: true),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                children: <pw.Widget>[
                  pw.Spacer(flex: 45),
                  pw.Expanded(
                    flex: 55,
                    child: pw.Column(
                      children: <pw.Widget>[
                        if (iv.sub != null)
                          lt(
                            pw.Text('Subtotal', style: st(11)),
                            pw.Text(inr(iv.sub), style: st(11)),
                          ),
                        for (final (String, num) x in iv.taxes)
                          lt(
                            pw.Text(_safe(x.$1), style: st(11)),
                            pw.Text(inr(x.$2), style: st(11)),
                          ),
                        pw.Container(
                          margin: const pw.EdgeInsets.only(top: 4),
                          padding: const pw.EdgeInsets.only(top: 4),
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(top: pw.BorderSide(color: _ink)),
                          ),
                          child: lt(
                            pw.Text('Total', style: st(12, f: fonts.extraBold)),
                            pw.Text(
                              inr(iv.total),
                              style: st(12, f: fonts.extraBold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 14),
                padding: const pw.EdgeInsets.all(8),
                color: _band,
                child: pw.RichText(
                  text: pw.TextSpan(
                    text: 'Amount: ',
                    style: st(11),
                    children: <pw.InlineSpan>[
                      pw.TextSpan(
                        text: inr(iv.total),
                        style: st(11, f: fonts.bold),
                      ),
                    ],
                  ),
                ),
              ),
              if (iv.note.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text(_safe(iv.note), style: st(9, c: _mute)),
                ),
              pw.SizedBox(height: 36),
              lt(
                pw.Text('Made with TallyConnect', style: st(9, c: _mute)),
                pw.Container(
                  padding: const pw.EdgeInsets.only(top: 3),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(color: _ink)),
                  ),
                  child: pw.Text('Authorised signatory', style: st(9)),
                ),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  // ---- report / detail / list layout
  final DocTable? t = d.table;
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.fromLTRB(44, 48, 44, 44),
      header: (pw.Context c) => c.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Text(
                _safe('${d.title} · ${d.company}'),
                style: st(9, c: _mute),
              ),
            ),
      footer: (pw.Context c) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text('Made with TallyConnect · $made', style: st(8.5, c: _mute)),
          pw.Text(
            'Page ${c.pageNumber} of ${c.pagesCount}',
            style: st(8.5, c: _mute),
          ),
        ],
      ),
      build: (pw.Context c) => <pw.Widget>[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Container(
              width: 34,
              height: 34,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                color: acc,
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Text(
                '₹',
                style: st(18, f: fonts.extraBold, c: PdfColors.white),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.RichText(
                    text: pw.TextSpan(
                      children: <pw.InlineSpan>[
                        pw.TextSpan(
                          text: 'Tally',
                          style: st(12, f: fonts.extraBold),
                        ),
                        pw.TextSpan(
                          text: 'Connect',
                          style: st(12, f: fonts.extraBold, c: acc),
                        ),
                      ],
                    ),
                  ),
                  pw.Text(d.company, style: st(10, c: _mute)),
                ],
              ),
            ),
          ],
        ),
        pw.Container(
          height: 1.4,
          color: acc,
          margin: const pw.EdgeInsets.symmetric(vertical: 14),
        ),
        pw.Text(_safe(d.title), style: st(20, f: fonts.extraBold)),
        if (d.subtitle.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(_safe(d.subtitle), style: st(11, c: _mute)),
          ),
        pw.SizedBox(height: 14),
        if (d.facts.isNotEmpty)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _rule),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              children: <pw.Widget>[
                for (int i = 0; i < d.facts.length; i++)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: i > 0
                        ? const pw.BoxDecoration(
                            border: pw.Border(top: pw.BorderSide(color: _rule)),
                          )
                        : null,
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: <pw.Widget>[
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            _safe(d.facts[i].$1),
                            style: st(11, c: _mute),
                          ),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(
                            _safe(d.facts[i].$2),
                            textAlign: pw.TextAlign.right,
                            style: st(11, f: fonts.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (t != null && t.rows.isNotEmpty)
          pw.TableHelper.fromTextArray(
            headers: t.columns,
            data: <List<String>>[
              for (final List<String> r in t.rows) r.map(_safe).toList(),
            ],
            headerStyle: st(10, f: fonts.bold),
            cellStyle: st(10.5),
            headerDecoration: const pw.BoxDecoration(color: _band),
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _rule, width: .6)),
            ),
            border: null,
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 6,
            ),
            cellAlignments: <int, pw.Alignment>{
              for (final int i in t.right) i: pw.Alignment.centerRight,
            },
            headerAlignments: <int, pw.Alignment>{
              for (final int i in t.right) i: pw.Alignment.centerRight,
            },
          ),
        if (d.totals.isNotEmpty)
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: pw.BoxDecoration(
              color: _band,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              children: <pw.Widget>[
                for (final (String, String) x in d.totals)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: <pw.Widget>[
                      pw.Text(_safe(x.$1), style: st(12, f: fonts.bold)),
                      pw.Text(_safe(x.$2), style: st(12, f: fonts.extraBold)),
                    ],
                  ),
              ],
            ),
          ),
      ],
    ),
  );
  return doc.save();
}
