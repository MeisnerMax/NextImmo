import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/components/nx_form_section_card.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Coverage for the `body` capability added to [NxFormSectionCard] for the
/// SCR-008 wizard redesign: a full-width custom section body rendered instead
/// of the width-bounded `children` wrap, without forking the component.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the title and a full-width custom body', (tester) async {
    await pump(
      tester,
      const NxFormSectionCard(
        title: 'Section title',
        body: Text('custom body content'),
      ),
    );

    expect(find.text('Section title'), findsOneWidget);
    expect(find.text('custom body content'), findsOneWidget);
  });

  testWidgets('still lays out the children wrap when no body is given', (
    tester,
  ) async {
    await pump(
      tester,
      const NxFormSectionCard(
        title: 'Fields',
        children: [
          SizedBox(width: 120, child: Text('field a')),
          SizedBox(width: 120, child: Text('field b')),
        ],
      ),
    );

    expect(find.text('field a'), findsOneWidget);
    expect(find.text('field b'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
