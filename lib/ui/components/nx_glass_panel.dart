import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Level 2 surface of the Liquid Enterprise system — the only place a real
/// [BackdropFilter] is allowed.
///
/// **Use for:** shell chrome (sidebar, top bar), modals, popovers, and docked
/// detail panels — surfaces that exist once or twice on screen and genuinely
/// overlap scrolling content behind them.
///
/// **Do not use for:** cards, list rows, table cells, or anything that repeats.
/// Every [BackdropFilter] forces a saveLayer and re-reads the framebuffer;
/// dozens of them in a dense grid is the difference between a smooth and a
/// stuttering web build. [NxCard] gives the same visual result without blur.
///
/// In light the theme resolves the fill to a near-opaque white, so this
/// degrades to a plain panel rather than needing a brightness branch at the
/// call site. There is no glow variant — the system has no emission.
class NxGlassPanel extends StatelessWidget {
  const NxGlassPanel({
    super.key,
    required this.child,
    this.blurSigma = 20,
    this.borderRadius,
    this.padding,
  });

  final Widget child;

  /// Backdrop blur strength. The design specifies 24px for panels and 40px
  /// for modals; sigma is roughly half the CSS blur radius.
  final double blurSigma;

  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final radius = borderRadius ?? BorderRadius.circular(AppRadiusTokens.lg);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(semantic.innerHighlight, semantic.glassFill),
                semantic.glassFill,
              ],
              stops: const [0, 0.5],
            ),
            borderRadius: radius,
            border: Border.all(color: semantic.glassStroke),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
