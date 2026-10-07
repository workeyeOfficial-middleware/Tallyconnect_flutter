// Launch splash: the Earth is on screen from the first frame and keeps a
// slow orbit (turn, settle, rise) while the transparent TallyConnect logo
// fades / scales / slides into place above it (~1 s), then the splash
// cross-fades into the app (Home or Login). Shown once per launch while the
// app starts up; it adds no wait of its own when start-up takes longer.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String kSplashImage = 'assets/images/splash_globe.jpg';
const String kSplashLogo = 'assets/images/splash_logo.png';

/// Light status-bar icons over the dark image.
const SystemUiOverlayStyle kSplashOverlay = SystemUiOverlayStyle(
  statusBarColor: Color(0x00000000),
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Color(0x00000000),
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);

/// The image's own edge colours (sampled from its top and bottom rows), so
/// the screen around the square image continues it seamlessly.
const Color _skyTop = Color(0xFF122135);
const Color _skyBottom = Color(0xFF040D14);

/// The Earth and logo decoded before the first frame, so the Earth is on
/// screen immediately (no empty frame while an asset decodes).
class SplashArt {
  const SplashArt(this.earth, this.logo);
  final ui.Image earth, logo;

  static Future<SplashArt?> load() async {
    try {
      Future<ui.Image> decode(String asset) async {
        final ByteData b = await rootBundle.load(asset);
        final ui.Codec codec = await ui.instantiateImageCodec(
          b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes),
        );
        return (await codec.getNextFrame()).image;
      }

      final List<ui.Image> r = await Future.wait(<Future<ui.Image>>[
        decode(kSplashImage),
        decode(kSplashLogo),
      ]);
      return SplashArt(r[0], r[1]);
    } catch (_) {
      return null; // the splash then loads the assets itself
    }
  }
}

/// Runs [boot] behind the splash and shows its app when both start-up and
/// the intro animation are done.
class SplashBoot extends StatefulWidget {
  const SplashBoot({
    super.key,
    required this.boot,
    required this.appOverlay,
    this.art,
  });

  /// Starts the app (storage, session, controller) and returns its root.
  final Future<Widget> Function() boot;

  /// The app's own system-bar style, restored when the splash leaves.
  final SystemUiOverlayStyle appOverlay;

  /// Pre-decoded images (see [SplashArt.load]); assets are used otherwise.
  final SplashArt? art;

  @override
  State<SplashBoot> createState() => _SplashBootState();
}

class _SplashBootState extends State<SplashBoot> with TickerProviderStateMixin {
  /// The ~1 s intro: logo in, Earth orbit settling.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  /// Earth's orbit — a little longer than the intro, so it is still moving
  /// while the splash cross-fades out.
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// Very slow further turn, only while a long start-up is still running.
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  );

  /// Cross-fade into the app.
  late final AnimationController _out = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  final GlobalKey _appKey = GlobalKey();
  Widget? _app;
  Object? _error;
  bool _introDone = false, _gone = false, _started = false;
  Timer? _kick;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(kSplashOverlay);
    _intro.addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed) {
        _introDone = true;
        if (_app == null && _error == null) _idle.forward();
        _leaveIfReady();
      }
    });
    widget.boot().then(
      (Widget app) {
        if (!mounted) return;
        setState(() => _app = app);
        _leaveIfReady();
      },
      onError: (Object e, StackTrace st) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: e, stack: st, library: 'start-up'),
        );
        if (mounted) setState(() => _error = e);
      },
    );
    // Pre-decoded art: start with the very first frame.
    if (widget.art != null) _started = true;
    if (widget.art != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _go());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Assets: start once both are decoded, but never wait on a slow decode.
    Future.wait(<Future<void>>[
      precacheImage(const AssetImage(kSplashImage), context),
      precacheImage(const AssetImage(kSplashLogo), context),
    ]).whenComplete(_go);
    _kick = Timer(const Duration(milliseconds: 250), _go);
  }

  void _go() {
    _kick?.cancel();
    if (!mounted || _intro.isAnimating || _intro.isCompleted) return;
    final bool reduce = MediaQueryData.fromView(
      View.of(context),
    ).disableAnimations;
    if (reduce) {
      _orbit.value = 1;
      _intro.duration = const Duration(milliseconds: 300);
    } else {
      _orbit.forward();
    }
    _intro.forward();
  }

  void _leaveIfReady() {
    if (_app == null || !_introDone || _out.isAnimating || _gone) return;
    _out.forward().whenComplete(() {
      if (!mounted) return;
      SystemChrome.setSystemUIOverlayStyle(widget.appOverlay);
      setState(() => _gone = true);
    });
  }

  @override
  void dispose() {
    _kick?.cancel();
    _intro.dispose();
    _orbit.dispose();
    _idle.dispose();
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // The app stays at this position, so it is never rebuilt when the
          // splash above it is removed.
          KeyedSubtree(
            key: _appKey,
            child: _app ?? const ColoredBox(color: _skyBottom),
          ),
          if (!_gone)
            IgnorePointer(
              // Taps reach the app while the splash fades out.
              ignoring: _app != null,
              child: AnimatedBuilder(
                animation: _out,
                builder: (BuildContext context, Widget? child) {
                  final double t = Curves.easeInOut.transform(_out.value);
                  return Opacity(
                    opacity: 1 - t,
                    child: Transform.scale(scale: 1 + .04 * t, child: child),
                  );
                },
                child: _SplashView(
                  art: widget.art,
                  intro: _intro,
                  orbit: _orbit,
                  idle: _idle,
                  error: _error != null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView({
    required this.art,
    required this.intro,
    required this.orbit,
    required this.idle,
    required this.error,
  });
  final SplashArt? art;
  final Animation<double> intro, orbit, idle;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final Animation<double> ease = CurvedAnimation(
      parent: orbit,
      curve: Curves.easeOutCubic,
    );
    // Logo: 0.25–0.85 s of the intro.
    final Animation<double> logo = CurvedAnimation(
      parent: intro,
      curve: const Interval(.25, .85, curve: Curves.easeOutCubic),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double w = box.maxWidth, h = box.maxHeight;
        final EdgeInsets safe = MediaQueryData.fromView(
          View.of(context),
        ).padding;
        // The whole square Earth image fits the shorter side (never
        // stretched or cropped), a little below the middle.
        final double side = w < h ? w : h;
        final double cy = h * .56;
        final double top = (cy - side / 2).clamp(0.0, h - side);
        // Above / below the image the screen carries on with the image's own
        // edge colours.
        final double ft = h <= 0 ? 0 : (top / h).clamp(0.0, 1.0);
        final double fb = h <= 0 ? 1 : ((top + side) / h).clamp(0.0, 1.0);
        // Logo: up to 74 % of the width, resting just above the globe's rim
        // (the globe's top is ~7 % into the image).
        final double lw = (w * .74).clamp(0.0, 420.0);
        final double lh = lw * 152 / 470;
        final double logoTop = (top + side * .07 - lh * 1.05).clamp(
          safe.top + 12,
          h,
        );
        final Widget earth = art != null
            ? RawImage(
                image: art!.earth,
                width: side,
                height: side,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              )
            : Image.asset(
                kSplashImage,
                width: side,
                height: side,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              );
        final Widget mark = art != null
            ? RawImage(
                image: art!.logo,
                width: lw,
                height: lh,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              )
            : Image.asset(
                kSplashLogo,
                width: lw,
                height: lh,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              );
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const <Color>[_skyTop, _skyTop, _skyBottom, _skyBottom],
              stops: <double>[0, ft, fb, 1],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Earth: on screen at once (no fade from black); a slow orbit —
              // turns into place, settles from a slight zoom and rises.
              Positioned(
                left: (w - side) / 2,
                top: top,
                width: side,
                height: side,
                child: AnimatedBuilder(
                  animation: Listenable.merge(<Listenable>[ease, idle]),
                  builder: (BuildContext context, Widget? child) {
                    final double e = ease.value;
                    return Transform.translate(
                      offset: Offset(0, side * .03 * (1 - e)),
                      child: Transform.rotate(
                        angle: -.07 * (1 - e) + .2 * idle.value,
                        child: Transform.scale(
                          scale: 1.06 - .06 * e,
                          child: child,
                        ),
                      ),
                    );
                  },
                  // Only the square's outer corners (outside the globe) and
                  // its top / bottom edges fade into the background.
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (Rect r) => const RadialGradient(
                      radius: .72,
                      colors: <Color>[
                        Color(0xFFFFFFFF),
                        Color(0xFFFFFFFF),
                        Color(0x00FFFFFF),
                      ],
                      stops: <double>[0, .9, 1],
                    ).createShader(r),
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (Rect r) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Color(0x00FFFFFF),
                          Color(0xFFFFFFFF),
                          Color(0xFFFFFFFF),
                          Color(0x00FFFFFF),
                        ],
                        stops: <double>[0, .05, .95, 1],
                      ).createShader(r),
                      child: earth,
                    ),
                  ),
                ),
              ),
              // Logo: fades in, sharpens, scales up and slides into place.
              Positioned(
                left: (w - lw) / 2,
                top: logoTop,
                width: lw,
                height: lh,
                child: AnimatedBuilder(
                  animation: logo,
                  builder: (BuildContext context, Widget? child) {
                    final double t = logo.value;
                    final double blur = 6 * (1 - t);
                    Widget m = Transform.translate(
                      offset: Offset(0, lh * .35 * (1 - t)),
                      child: Transform.scale(
                        scale: .92 + .08 * t,
                        child: child,
                      ),
                    );
                    if (blur > .05) {
                      m = ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: blur,
                          sigmaY: blur,
                        ),
                        child: m,
                      );
                    }
                    return Opacity(opacity: t, child: m);
                  },
                  child: mark,
                ),
              ),
              if (error)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: safe.bottom + 48,
                  child: const Text(
                    'TallyConnect could not start. Please close and reopen the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 14,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
