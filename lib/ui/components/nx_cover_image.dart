/// The one cover-image widget, replacing three private ones that disagreed.
///
/// Before this there were `_PropertyCover` (16:9, `Image.file`, spinner while
/// loading, icon fallback), `_PropertyThumbnail` (fixed 44x44, `Image.network`,
/// error builder, *no* loading state) and `_MediaTile` (4:3, `Image.network`,
/// error builder, placeholder for a null URL) — three answers to the same
/// question, none of them exported.
///
/// **The empty state is the normal state, not the exception.** Property images
/// are optional, the demo fixture creates none, and most rows in a real
/// workspace will not have one for a long time. A card view that only looks
/// right with a photograph would look broken for almost every object, so the
/// placeholder here is composed rather than apologetic: it uses the same glass
/// treatment as the surrounding card and a domain icon, so a grid of
/// image-less properties reads as a deliberate layout instead of a row of
/// failures.
///
/// **An expired URL degrades to that same placeholder.** Signed URLs live five
/// minutes and nothing in the app renews them, so a grid left open on a second
/// screen *will* pass that boundary. The failure is silent by design: a broken
/// image glyph would tell the reader their data is damaged, which is untrue —
/// only the link aged out. The gap itself is real and named in the header of
/// `PropertyCoverController`; this widget makes it survivable, not fixed.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NxCoverImage extends StatelessWidget {
  const NxCoverImage({
    super.key,
    required this.url,
    this.aspectRatio = 16 / 9,
    this.icon = Icons.apartment_outlined,
    this.borderRadius,
    this.semanticLabel,
  });

  /// Null when the record has no image at all — which is the common case, not
  /// an error.
  final String? url;

  final double aspectRatio;
  final IconData icon;
  final BorderRadius? borderRadius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final radius =
        borderRadius ?? BorderRadius.circular(AppRadiusTokens.lg);
    return ClipRRect(
      borderRadius: radius,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final source = url;
    if (source == null || source.isEmpty) {
      return _Placeholder(icon: icon, semanticLabel: semanticLabel);
    }
    return Image.network(
      source,
      fit: BoxFit.cover,
      semanticLabel: semanticLabel,
      // A failed load is almost always an expired signature, not a damaged
      // file. It reads as "no image yet", which is both truer and calmer.
      errorBuilder: (context, error, stackTrace) =>
          _Placeholder(icon: icon, semanticLabel: semanticLabel),
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        // The same placeholder rather than a spinner: in a grid, a dozen
        // spinners is noise, and the placeholder is what the cell will look
        // like anyway if the load does not finish.
        return _Placeholder(
          icon: icon,
          semanticLabel: semanticLabel,
          dimmed: true,
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    this.semanticLabel,
    this.dimmed = false,
  });

  final IconData icon;
  final String? semanticLabel;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final theme = Theme.of(context);
    return Semantics(
      label: semanticLabel,
      image: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // The card's own depth treatment, so an image-less card is a card
          // with a quiet panel in it rather than a card with a hole.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color.alphaBlend(semantic.innerHighlight, semantic.glassFill),
              semantic.glassFill,
            ],
            stops: const <double>[0, 0.5],
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 28,
            color: theme.colorScheme.onSurfaceVariant.withValues(
              alpha: dimmed ? 0.25 : 0.45,
            ),
          ),
        ),
      ),
    );
  }
}
