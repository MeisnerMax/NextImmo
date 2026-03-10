import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';
import 'nx_card.dart';
import 'nx_empty_state.dart';

class NxDataTableShell extends StatelessWidget {
  const NxDataTableShell({
    super.key,
    required this.child,
    this.mobileChild,
    this.minTableWidth = 920,
    this.mobileBreakpoint = 900,
    this.loading = false,
    this.errorMessage,
    this.isEmpty = false,
    this.emptyTitle = 'No records yet',
    this.emptyDescription =
        'Adjust filters or add a new record to populate this view.',
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyAction,
    this.padding,
  });

  final Widget child;
  final Widget? mobileChild;
  final double minTableWidth;
  final double mobileBreakpoint;
  final bool loading;
  final String? errorMessage;
  final bool isEmpty;
  final String emptyTitle;
  final String emptyDescription;
  final IconData emptyIcon;
  final Widget? emptyAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const NxCard(child: Center(child: CircularProgressIndicator()));
    }

    if (errorMessage != null) {
      return NxEmptyState(
        title: context.strings.text('Unable to load this table'),
        description: errorMessage!,
        icon: Icons.error_outline,
      );
    }

    if (isEmpty) {
      return NxEmptyState(
        title: emptyTitle,
        description: emptyDescription,
        icon: emptyIcon,
        primaryAction: emptyAction,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final showMobileLayout =
            mobileChild != null && constraints.maxWidth < mobileBreakpoint;
        return NxCard(
          padding: padding ?? EdgeInsets.zero,
          child:
              showMobileLayout
                  ? mobileChild!
                  : Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: minTableWidth),
                          child: child,
                        ),
                      ),
                    ),
                  ),
        );
      },
    );
  }
}
