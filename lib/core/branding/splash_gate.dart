import 'package:flutter/material.dart';
import 'package:opt_kit/opt_kit.dart' show OptBrandCredit;

/// The family launch screen: the app mark on the coral→violet→blue family
/// gradient, the "OptDAI" wordmark, and the shared "an OptERP product" credit.
///
/// This sits ABOVE the lock gate in the app's builder chain (see `app.dart`).
/// On cold start it paints itself over everything for a minimum beat — long
/// enough for the co-brand credit reveal to be seen — while the real startup
/// (session/theme restore, the lock gate, the encrypted database) proceeds
/// underneath. When the minimum elapses the splash fades out and the lock gate
/// (or the app, if unlocked) takes over. It never reappears after the first
/// paint, so re-locking mid-session goes straight to the lock screen.
///
/// The co-brand credit is the kit's `OptBrandCredit(compact: true)` — the
/// identical reveal every OptERP app shows. The rest of the splash (family
/// gradient, white glyph mark, wordmark) stays app-owned in the core layer
/// (chrome, outside `lib/features/`, where an explicit family gradient is
/// allowed).
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  /// How long the splash is held, measured from the FIRST Flutter frame (see
  /// `initState`) so the native splash overlay can't eat into it. The credit
  /// starts at 300ms and its full reveal takes 2400ms, so it completes at
  /// ~2700ms — a 3600ms hold lets "an OptERP product" land and sit for
  /// ~900ms before the 420ms fade-out.
  static const Duration _minimum = Duration(milliseconds: 3600);

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // Start the clock on the first rendered frame, not now: on a cold start
    // the native splash still covers the app while the engine warms up, so a
    // timer started in initState would burn 0.5–1.5s of the hold before the
    // Flutter splash (and the credit reveal) is even visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(SplashGate._minimum, () {
        if (mounted) setState(() => _done = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // The child is always built underneath so its own startup work (unlock,
    // database open) begins immediately, hidden behind the splash.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchOutCurve: Curves.easeOutCubic,
          child: _done
              ? const SizedBox.shrink(key: ValueKey<String>('gone'))
              : const _SplashSurface(key: ValueKey<String>('splash')),
        ),
      ],
    );
  }
}

class _SplashSurface extends StatelessWidget {
  const _SplashSurface({super.key});

  // The OptERP family sweep: coral → violet → blue, warm to cool, top-left to
  // bottom-right. Hard-coded here on purpose — a splash is chrome, it lives in
  // core/ (not lib/features/), and the app has no BrandTheme, so the family
  // gradient is stated explicitly.
  static const LinearGradient _family = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFFEE6352), Color(0xFF7B5FD6), Color(0xFF2F6FE4)],
    stops: <double>[0.0, 0.52, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: _family),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const Center(child: _SplashMark()),
            Align(
              alignment: const Alignment(0, 0.55),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeIn,
                builder: (context, value, child) =>
                    Opacity(opacity: value.clamp(0.0, 1.0), child: child),
                child: const Text(
                  'OptDAI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            // The shared family credit reveal. The kit default delay lets the
            // rest of a screen settle first; here the splash owns the screen,
            // so start early (300ms) — with the 2400ms reveal it completes at
            // ~2700ms, inside the gate's 3600ms hold with ~900ms to spare.
            const Align(
              alignment: Alignment(0, 0.88),
              child: OptBrandCredit(
                compact: true,
                delay: Duration(milliseconds: 300),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The centered app mark: the white glyph painted straight on the gradient —
/// no card, no border — so it matches the native splash's white glyph exactly
/// (the launch reads as one screen) and mirrors the family style (OptHealth's
/// white heart, OptIVF's white embryo mark on their gradients). Fades and
/// scales in gently for a breath of motion.
class _SplashMark extends StatelessWidget {
  const _SplashMark();

  @override
  Widget build(BuildContext context) {
    // Match the native launch glyph's visual scale: the storyboard centers the
    // LaunchImage at ~a fifth of the screen width, so size the Dart mark the
    // same way (21% of width, clamped) — no size jump at the native→Dart
    // handoff.
    final double size =
        (MediaQuery.sizeOf(context).width * 0.21).clamp(96.0, 160.0);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
      ),
      child: Image.asset(
        'assets/branding/icon_foreground.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
