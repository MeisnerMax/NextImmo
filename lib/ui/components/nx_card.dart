import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum NxCardVariant { standard, interactive, kpi }

/// Level 1 panel of the Liquid Enterprise system.
///
/// Depth comes from luminance, not shadow: a translucent fill, a hairline
/// stroke, and a top-edge inner highlight that fades out over the upper half
/// of the card. There is deliberately **no** [BackdropFilter] here — cards
/// appear dozens at a time in dense grids, and a real backdrop blur per card
/// is the single most expensive thing this design could do on web/CanvasKit.
/// Against the flat canvas the alpha-blended fill is visually equivalent.
/// Real blur is reserved for [NxGlassPanel] (shell chrome and overlays).
class NxCard extends StatefulWidget {
  const NxCard({
    super.key,
    required this.child,
    this.variant = NxCardVariant.standard,
    this.onTap,
    this.padding,
  });

  final Widget child;
  final NxCardVariant variant;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  State<NxCard> createState() => _NxCardState();
}

class _NxCardState extends State<NxCard> {
  bool _hovered = false;

  bool get _interactive =>
      widget.variant == NxCardVariant.interactive && widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final compact = context.compactLayout;
    final primary = Theme.of(context).colorScheme.primary;
    final resolvedPadding =
        widget.padding ??
        EdgeInsets.all(
          widget.variant == NxCardVariant.kpi
              ? (compact ? 12 : 16)
              : (compact ? 12 : AppSpacing.cardPadding),
        );
    final borderRadius = BorderRadius.circular(AppRadiusTokens.lg);
    final highlighted = _interactive && _hovered;

    final decoration = BoxDecoration(
      // Fill and top-edge highlight in one gradient: BoxDecoration takes
      // either a color or a gradient, not both.
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.alphaBlend(semantic.innerHighlight, semantic.glassFill),
          semantic.glassFill,
        ],
        stops: const [0, 0.5],
      ),
      borderRadius: borderRadius,
      border: Border.all(
        color:
            highlighted
                ? primary.withValues(alpha: 0.3)
                : semantic.glassStroke,
      ),
      // No shadow and no glow in either brightness. Hover is signalled by the
      // stroke shifting to the accent — that is the whole affordance.
    );

    if (!_interactive) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: decoration,
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: resolvedPadding, child: widget.child),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: borderRadius,
            hoverColor: Colors.transparent,
            child: Padding(padding: resolvedPadding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
