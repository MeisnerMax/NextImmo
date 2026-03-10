import 'package:flutter/material.dart';

import '../components/nx_status_badge.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(label: label, kind: _toKind(color));
  }

  NxBadgeKind _toKind(Color value) {
    final rgb = value.toARGB32() & 0x00FFFFFF;
    switch (rgb) {
      case 0x001C8C5E:
        return NxBadgeKind.success;
      case 0x00C44949:
        return NxBadgeKind.error;
      case 0x00C28A1A:
        return NxBadgeKind.warning;
      case 0x002B78B8:
        return NxBadgeKind.info;
      default:
        return NxBadgeKind.neutral;
    }
  }
}
