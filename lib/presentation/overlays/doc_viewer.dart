// Preview PDF (NEW feature): shows a generated document's real PDF pages in
// the same dark viewer chrome as the prototype's bill PDF (1563–1582), with
// zoom, Share and Download.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/share/share_doc.dart';
import '../widgets/common.dart';

class DocViewer extends ConsumerStatefulWidget {
  const DocViewer({super.key});

  @override
  ConsumerState<DocViewer> createState() => _DocViewerState();
}

class _DocViewerState extends ConsumerState<DocViewer> {
  Future<List<ui.Image>>? _pages;
  Future<Uint8List>? _src;

  Future<List<ui.Image>> _render(
    AppController c,
    Future<Uint8List> bytes,
  ) async => c.exporter.raster(await bytes);

  @override
  Widget build(BuildContext context) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final MediaQueryData mq = MediaQuery.of(context);
    final ShareDoc? d = c.docShown;
    final Future<Uint8List>? bytes = c.docBytes;
    if (d == null || bytes == null) return const SizedBox.shrink();
    if (!identical(bytes, _src)) {
      _src = bytes;
      _pages = _render(c, bytes);
    }
    Widget ctl(String ic, VoidCallback f) => Tap(
      onTap: f,
      radius: 23,
      subtleHighlight: true,
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: whiteA(.14), shape: BoxShape.circle),
        child: Ic(ic, color: Colors.white),
      ),
    );
    return fadeIn(
      ColoredBox(
        color: const Color(0xFF1D2231),
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                math.max(28, mq.padding.top + 8),
                16,
                12,
              ),
              child: Row(
                children: <Widget>[
                  CBtn(
                    'close',
                    glass: false,
                    bg: whiteA(.12),
                    color: Colors.white,
                    onTap: c.closeOv,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          d.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(16, w: w700, c: Colors.white),
                        ),
                        FutureBuilder<List<ui.Image>>(
                          future: _pages,
                          builder:
                              (
                                BuildContext context,
                                AsyncSnapshot<List<ui.Image>> s,
                              ) {
                                final int n = s.data?.length ?? 0;
                                return Opacity(
                                  opacity: .7,
                                  child: Text(
                                    n == 0
                                        ? 'A4 · PDF'
                                        : '$n page${n == 1 ? '' : 's'} · A4 · PDF',
                                    style: ts(13, c: Colors.white),
                                  ),
                                );
                              },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  CBtn(
                    'share',
                    glass: false,
                    bg: whiteA(.12),
                    color: Colors.white,
                    onTap: () => c.shareDoc(d),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<ui.Image>>(
                future: _pages,
                builder:
                    (BuildContext context, AsyncSnapshot<List<ui.Image>> s) {
                      if (s.hasError) {
                        return Center(
                          child: Text(
                            'Could not show this PDF',
                            style: ts(15, w: w700, c: whiteA(.8)),
                          ),
                        );
                      }
                      if (!s.hasData) {
                        return Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: p.acc2,
                            ),
                          ),
                        );
                      }
                      return SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 10, bottom: 10),
                        child: Center(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: c.zoom / 100),
                            duration: const Duration(milliseconds: 350),
                            curve: const Cubic(.3, 1.4, .5, 1),
                            builder:
                                (BuildContext context, double z, Widget? ch) =>
                                    Transform.scale(
                                      scale: z,
                                      alignment: Alignment.topCenter,
                                      child: ch,
                                    ),
                            child: Column(
                              children: <Widget>[
                                for (final ui.Image img in s.data!)
                                  Container(
                                    width: math.min(mq.size.width - 32, 360),
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      boxShadow: <BoxShadow>[
                                        css(
                                          0,
                                          20,
                                          40,
                                          0,
                                          Colors.black.withValues(alpha: .4),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: RawImage(
                                        image: img,
                                        fit: BoxFit.fitWidth,
                                        filterQuality: FilterQuality.medium,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
              ),
            ),
            Container(
              margin: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                22 + mq.padding.bottom * .6,
              ),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: whiteA(.12),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: <Widget>[
                  ctl('minus', () => c.zoomBy(-20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${c.zoom}%',
                      textAlign: TextAlign.center,
                      style: ts(16, w: w800, c: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ctl('plus', () => c.zoomBy(20)),
                  const SizedBox(width: 10),
                  ctl('download', () => c.downloadDoc(d)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
