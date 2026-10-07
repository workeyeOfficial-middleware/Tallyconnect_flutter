// Preview PDF: shows a generated document's real PDF pages (the same bytes
// Share and Download use) in the dark viewer chrome, with touch zoom — pinch
// in / out, pan while zoomed, double-tap to zoom — plus Share and Download.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/share/share_doc.dart';
import '../widgets/common.dart';

class DocViewer extends ConsumerStatefulWidget {
  const DocViewer({super.key});

  @override
  ConsumerState<DocViewer> createState() => _DocViewerState();
}

class _DocViewerState extends ConsumerState<DocViewer>
    with SingleTickerProviderStateMixin {
  Future<List<ui.Image>>? _pages;
  Future<Uint8List>? _src;

  /// Pinch / pan state of the pages.
  final TransformationController _tc = TransformationController();
  late final AnimationController _zoomAnim =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 260),
      )..addListener(
        () => _tc.value = _zoomTween?.evaluate(_zoomCurve) ?? _tc.value,
      );
  late final Animation<double> _zoomCurve = CurvedAnimation(
    parent: _zoomAnim,
    curve: Curves.easeOutCubic,
  );
  Matrix4Tween? _zoomTween;
  Offset _tapAt = Offset.zero;

  static const double _maxZoom = 4;
  static const double _tapZoom = 2.5;

  @override
  void dispose() {
    _zoomAnim.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 end) {
    _zoomTween = Matrix4Tween(begin: _tc.value, end: end);
    _zoomAnim.forward(from: 0);
  }

  /// Double-tap: zoom in at the tapped point, or back to fit.
  void _doubleTap() {
    if (_tc.value.getMaxScaleOnAxis() > 1.01) {
      _animateTo(Matrix4.identity());
      return;
    }
    final Offset f = _tapAt;
    _animateTo(
      Matrix4.identity()
        ..translateByDouble(
          -f.dx * (_tapZoom - 1),
          -f.dy * (_tapZoom - 1),
          0,
          1,
        )
        ..scaleByDouble(_tapZoom, _tapZoom, 1, 1),
    );
  }

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
      _tc.value = Matrix4.identity(); // a new document opens unzoomed
    }
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
                  const SizedBox(width: 10),
                  CBtn(
                    'download',
                    glass: false,
                    bg: whiteA(.12),
                    color: Colors.white,
                    onTap: () => c.downloadDoc(d),
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
                      return LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints box) {
                          final double pw = math.min(box.maxWidth - 32, 420);
                          // Pages centred; at 1x they scroll vertically, and
                          // pinch zooms in / out (pan while zoomed).
                          return GestureDetector(
                            onDoubleTapDown: (TapDownDetails t) =>
                                _tapAt = t.localPosition,
                            onDoubleTap: _doubleTap,
                            child: InteractiveViewer(
                              transformationController: _tc,
                              constrained: false,
                              minScale: 1,
                              maxScale: _maxZoom,
                              boundaryMargin: EdgeInsets.zero,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: box.maxWidth,
                                  maxWidth: box.maxWidth,
                                  minHeight: box.maxHeight,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    16,
                                    10,
                                    16,
                                    22 + mq.padding.bottom * .6,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: <Widget>[
                                      for (final ui.Image img in s.data!)
                                        Container(
                                          width: pw,
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            boxShadow: <BoxShadow>[
                                              css(
                                                0,
                                                20,
                                                40,
                                                0,
                                                Colors.black.withValues(
                                                  alpha: .4,
                                                ),
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            child: RawImage(
                                              image: img,
                                              width: pw,
                                              fit: BoxFit.fitWidth,
                                              filterQuality:
                                                  FilterQuality.medium,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
