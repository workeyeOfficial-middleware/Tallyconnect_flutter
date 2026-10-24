// Platform side of Share / Preview PDF / Download (NEW feature). Kept behind
// an interface so tests (and a future backend) can swap it.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'pdf_builder.dart';
import 'share_doc.dart';

abstract interface class DocExporter {
  /// Builds the PDF bytes for [d] in the current accent colour.
  Future<Uint8List> pdf(ShareDoc d, int accentArgb);

  /// Opens the Android / iOS system share sheet with the PDF and a text summary.
  Future<void> share(ShareDoc d, Uint8List bytes);

  /// One share sheet with several PDFs (e.g. selected invoices) and [text].
  Future<void> shareMany(
    List<(ShareDoc, Uint8List)> docs, {
    required String text,
    String? subject,
  });

  /// Saves the PDF where the user can find it; returns a display path.
  Future<String> download(String fileName, Uint8List bytes);

  /// Renders the PDF pages for the in-app preview.
  Future<List<ui.Image>> raster(Uint8List bytes);
}

class PlatformDocExporter implements DocExporter {
  PlatformDocExporter();

  static const MethodChannel _downloads = MethodChannel(
    'tallyconnect/downloads',
  );
  DocFonts? _fonts;
  Uint8List? _logo;

  Future<DocFonts> _loadFonts() async => _fonts ??= DocFonts.fromBytes(
    regular: await rootBundle.load('assets/fonts/Figtree-Regular.ttf'),
    bold: await rootBundle.load('assets/fonts/Figtree-Bold.ttf'),
    extraBold: await rootBundle.load('assets/fonts/Figtree-ExtraBold.ttf'),
  );

  /// The TallyConnect wordmark for the PDF header (null if missing).
  Future<Uint8List?> _loadLogo() async {
    try {
      return _logo ??= (await rootBundle.load(
        'assets/images/tc_logo.png',
      )).buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List> pdf(ShareDoc d, int accentArgb) async => buildPdf(
    d,
    fonts: await _loadFonts(),
    accentArgb: accentArgb,
    logo: await _loadLogo(),
  );

  @override
  Future<void> share(ShareDoc d, Uint8List bytes) async {
    final Directory tmp = await getTemporaryDirectory();
    final File f = File(p.join(tmp.path, d.fileName));
    await f.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(f.path, mimeType: 'application/pdf', name: d.fileName),
        ],
        text: d.text,
        subject: d.invoice != null
            ? '${d.invoice!.heading} ${d.invoice!.no}'
            : d.title,
      ),
    );
  }

  @override
  Future<void> shareMany(
    List<(ShareDoc, Uint8List)> docs, {
    required String text,
    String? subject,
  }) async {
    final Directory tmp = await getTemporaryDirectory();
    final List<XFile> files = <XFile>[];
    final Set<String> names = <String>{};
    for (final (ShareDoc d, Uint8List bytes) in docs) {
      // Two vouchers with the same number: keep both files.
      String name = d.fileName;
      for (int i = 2; !names.add(name); i++) {
        name = d.fileName.replaceFirst(RegExp(r'\.pdf$'), '_$i.pdf');
      }
      final File f = File(p.join(tmp.path, name));
      await f.writeAsBytes(bytes, flush: true);
      files.add(XFile(f.path, mimeType: 'application/pdf', name: name));
    }
    await SharePlus.instance.share(
      ShareParams(files: files, text: text, subject: subject),
    );
  }

  @override
  Future<String> download(String fileName, Uint8List bytes) async {
    if (Platform.isAndroid) {
      final String? path = await _downloads.invokeMethod<String>(
        'save',
        <String, Object>{
          'name': fileName,
          'mime': 'application/pdf',
          'bytes': bytes,
        },
      );
      return path ?? fileName;
    }
    // iOS: the app's Documents folder is visible in the Files app
    // (UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace).
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File(p.join(dir.path, fileName));
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  @override
  Future<List<ui.Image>> raster(Uint8List bytes) async {
    final List<ui.Image> out = <ui.Image>[];
    await for (final PdfRaster r in Printing.raster(bytes, dpi: 216)) {
      out.add(await r.toImage());
    }
    return out;
  }
}
