import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';
import 'nx_card.dart';
import 'nx_empty_state.dart';

class NxDataTableShell extends StatefulWidget {
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
  State<NxDataTableShell> createState() => _NxDataTableShellState();
}

class _NxDataTableShellState extends State<NxDataTableShell> {
  // Own controllers so the always-visible scrollbar never depends on an
  // ambient PrimaryScrollController (absent inside scrollable page bodies).
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const NxCard(child: Center(child: CircularProgressIndicator()));
    }

    if (widget.errorMessage != null) {
      return NxEmptyState(
        title: context.strings.text('Unable to load this table'),
        description: widget.errorMessage!,
        icon: Icons.error_outline,
      );
    }

    if (widget.isEmpty) {
      return NxEmptyState(
        title: widget.emptyTitle,
        description: widget.emptyDescription,
        icon: widget.emptyIcon,
        primaryAction: widget.emptyAction,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final showMobileLayout = widget.mobileChild != null &&
            constraints.maxWidth < widget.mobileBreakpoint;
        return NxCard(
          padding: widget.padding ?? EdgeInsets.zero,
          child:
              showMobileLayout
                  ? widget.mobileChild!
                  : Scrollbar(
                    controller: _verticalController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _verticalController,
                      child: SingleChildScrollView(
                        controller: _horizontalController,
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minWidth: widget.minTableWidth),
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
        );
      },
    );
  }
}
