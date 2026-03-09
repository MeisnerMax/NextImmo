import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ResponsiveConstraints {
  const ResponsiveConstraints._();

  static Widget wrapItem(
    BuildContext context, {
    required Widget child,
    required double idealWidth,
    double minWidth = 140,
    double maxWidth = 560,
  }) {
    final width = itemWidth(
      context,
      idealWidth: idealWidth,
      minWidth: minWidth,
      maxWidth: maxWidth,
    );
    return SizedBox(width: width, child: child);
  }

  static double itemWidth(
    BuildContext context, {
    required double idealWidth,
    double minWidth = 140,
    double maxWidth = 560,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final usable = screenWidth - (context.adaptivePagePadding * 2) - 24;
    final clamped = usable.clamp(minWidth, maxWidth).toDouble();
    return math.min(idealWidth, clamped);
  }

  static double dialogWidth(
    BuildContext context, {
    required double maxWidth,
    double horizontalMargin = 32,
    double minWidth = 260,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final available = screenWidth - horizontalMargin;
    return available.clamp(minWidth, maxWidth).toDouble();
  }

  static bool useVerticalSplit(
    BuildContext context, {
    double minTwoPaneWidth = 1024,
  }) {
    return MediaQuery.sizeOf(context).width >= minTwoPaneWidth;
  }
}
