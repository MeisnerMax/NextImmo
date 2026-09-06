/// A grid that chooses its column count from the width it is actually given.
///
/// The system had no such primitive, and it shows: the `LayoutBuilder` + `Wrap`
/// pattern is hand-copied in three places (`nx_kpi_tile.dart`,
/// `property_media_panel.dart`, `imports_screen.dart`) and two more screens
/// inline a `GridView` with their own breakpoints. Each copy picked its own
/// thresholds, so two grids on the same screen can break at different widths.
///
/// Two rules it holds that the copies did not:
///
///   * **It measures the space it gets, not the window.** A grid inside a
///     workspace shell with a navigation rail has a few hundred pixels less
///     than `MediaQuery` reports, and a breakpoint read from the window puts
///     three columns into a space that fits two. The existing property list
///     already learned this — it switches on shell width, not window width.
///   * **The last row is not stretched.** A `Wrap` leaves a short final row
///     alone; a `GridView` with a fixed column count would too, but several of
///     the hand-copies used `Expanded` children inside a `Row`, which makes a
///     single trailing card span the full width and look like a different kind
///     of thing. Cards keep their width; the row simply ends.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Column count per available width. The thresholds are the system's own
/// breakpoints rather than new numbers, so a grid breaks where everything else
/// on the screen breaks.
int nxGridColumnsFor(double width, {int maxColumns = 4}) {
  final columns = switch (width) {
    < 640 => 1,
    < 1024 => 2,
    < 1440 => 3,
    _ => 4,
  };
  return columns > maxColumns ? maxColumns : columns;
}

class NxResponsiveGrid extends StatelessWidget {
  const NxResponsiveGrid({
    super.key,
    required this.children,
    this.maxColumns = 4,
    this.spacing,
    this.runSpacing,
  });

  final List<Widget> children;

  /// Upper bound on columns. A grid of three-line cards reads badly at four
  /// across even on a wide screen; the caller knows its content, this widget
  /// only knows the width.
  final int maxColumns;

  final double? spacing;
  final double? runSpacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final gap = spacing ?? AppSpacing.md;
    final runGap = runSpacing ?? AppSpacing.md;

    return LayoutBuilder(
      builder: (context, constraints) {
        // An unbounded width has no column count to derive — that happens
        // inside an unconstrained Row or a horizontal scroll view, where a
        // grid does not belong. One column is the honest answer rather than a
        // crash or an arbitrary guess.
        if (!constraints.hasBoundedWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0) SizedBox(height: runGap),
                children[i],
              ],
            ],
          );
        }

        final columns = nxGridColumnsFor(
          constraints.maxWidth,
          maxColumns: maxColumns,
        );
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0) SizedBox(height: runGap),
                children[i],
              ],
            ],
          );
        }

        // Width per cell, with the gaps taken out first. `floorToDouble` keeps
        // a sub-pixel remainder from pushing the last cell onto its own line.
        final totalGap = gap * (columns - 1);
        final cellWidth = ((constraints.maxWidth - totalGap) / columns)
            .floorToDouble();

        return Wrap(
          spacing: gap,
          runSpacing: runGap,
          children: <Widget>[
            for (final child in children)
              SizedBox(width: cellWidth, child: child),
          ],
        );
      },
    );
  }
}
