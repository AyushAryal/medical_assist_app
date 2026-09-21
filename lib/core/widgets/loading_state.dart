import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// The quiet way a screen waits.
///
/// Two things make the stock `Scaffold(body: CircularProgressIndicator())`
/// read as jank. Its background is opaque theme colour, so a screen that is
/// otherwise painted on the ambient wash flashes a different colour for one
/// frame. And the spinner appears instantly, so a load that takes 80ms still
/// blinks a spinner at the user. This paints nothing behind itself and eases
/// the spinner in only once the wait is long enough to be real.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message});

  /// An optional line under the spinner for the waits worth naming
  /// ("Opening the encrypted record…").
  final String? message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: TweenAnimationBuilder<double>(
          // Holds invisible for ~200ms, then eases in over the remainder —
          // one implicit animation, no controller to dispose.
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: const Interval(0.3, 1, curve: Curves.easeOutCubic),
          builder: (context, t, child) => Opacity(opacity: t, child: child),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: palette.primary,
                ),
              ),
              if (message != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: context.texts.bodySmall?.copyWith(
                    color: palette.onSurfaceMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
