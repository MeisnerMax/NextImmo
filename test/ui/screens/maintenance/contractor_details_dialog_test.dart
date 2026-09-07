/// SUPPLIER-DETAILS-01 (P-3): the register editor.
///
/// The whole file is about one distinction the form has to keep:
///
///   * a field the reader **did not touch** must be absent from the patch, so
///     a save cannot overwrite a colleague's concurrent edit to something this
///     reader never looked at;
///   * a field the reader **emptied** must be present with a null, because
///     "no agreed rate any more" is a decision and has to reach the server.
///
/// A form that sent every field on every save would pass any test that only
/// checked the value it changed. So every assertion here checks the shape of
/// the whole patch, not just the field under test.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/domain/party_dto.dart';
import 'package:neximmo_app/ui/screens/maintenance/widgets/contractor_details_dialog.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

ContractorDetailsDto _details() {
  return ContractorDetailsDto(
    partyId: 'party-1',
    workspaceId: 'ws-1',
    tradeCategory: 'electrical',
    isActive: true,
    version: 3,
    hourlyRate: 85,
    serviceArea: 'Berlin Mitte',
    ratingPrice: 4,
    ratingQuality: 5,
    ratingSpeed: 3,
    ratingCommunication: 4,
    ratingPunctuality: 5,
    insuranceCertExpiry: DateTime(2027, 6, 30),
  );
}

Future<Map<String, Object?>?> _open(
  WidgetTester tester,
  Future<void> Function(WidgetTester tester) edit,
) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  Map<String, Object?>? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async {
              result = await showContractorDetailsDialog(
                context,
                details: _details(),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  await edit(tester);

  await tester.tap(find.byKey(const Key('contractor-details-save')));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('starts from the values the register holds', (tester) async {
    await _open(tester, (WidgetTester tester) async {
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('contractor-details-trade')))
            .controller
            ?.text,
        'electrical',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('contractor-details-rate')))
            .controller
            ?.text,
        '85',
        reason: 'not "85.0" -- a trailing zero would read as an edit the '
            'reader did not make, and would be sent as one',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('contractor-details-insurance')),
            )
            .controller
            ?.text,
        '2027-06-30',
      );
    });
  });

  testWidgets('an unchanged form sends nothing at all', (tester) async {
    final result = await _open(tester, (WidgetTester tester) async {});

    expect(
      result,
      isNull,
      reason: 'the server refuses an empty change set, and spending a round '
          'trip on a certain refusal is what the pre-checks around this screen '
          'already avoid',
    );
  });

  testWidgets('one changed field is the only thing in the patch', (
    tester,
  ) async {
    final result = await _open(tester, (WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const Key('contractor-details-rate')),
        '95',
      );
    });

    expect(result, <String, Object?>{'hourly_rate': 95.0});
    expect(
      result!.containsKey('trade_category'),
      isFalse,
      reason: 'a form that sent every field would overwrite a colleague who '
          'changed the trade while this dialog was open',
    );
  });

  testWidgets('an emptied field is a clear, not an omission', (tester) async {
    final result = await _open(tester, (WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const Key('contractor-details-rate')),
        '',
      );
    });

    expect(result, hasLength(1));
    expect(
      result!.containsKey('hourly_rate'),
      isTrue,
      reason: '"no agreed rate any more" is a decision and has to reach the '
          'server. Omitting it would leave the old rate standing',
    );
    expect(result['hourly_rate'], isNull);
  });

  testWidgets('an emptied insurance date clears rather than sending an empty '
      'string', (tester) async {
    final result = await _open(tester, (WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const Key('contractor-details-insurance')),
        '',
      );
    });

    expect(result, <String, Object?>{'insurance_cert_expiry': null});
  });

  testWidgets('a past insurance date is accepted', (tester) async {
    final result = await _open(tester, (WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const Key('contractor-details-insurance')),
        '2020-01-01',
      );
    });

    expect(
      result,
      <String, Object?>{'insurance_cert_expiry': '2020-01-01'},
      reason: 'an expired certificate is a fact worth recording. Refusing it '
          'would leave the register showing the old valid one, which is the '
          'reading that gets somebody sent to a site uninsured',
    );
  });

  testWidgets('the trade cannot be emptied', (tester) async {
    final result = await _open(tester, (WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const Key('contractor-details-trade')),
        '',
      );
    });

    // The save was pressed and the dialog is still open: the validator held.
    expect(find.byKey(const Key('contractor-details-dialog')), findsOneWidget);
    expect(result, isNull);
    expect(find.text('Pflichtfeld'), findsOneWidget);
  });

  testWidgets('a rating above five is refused before the round trip', (
    tester,
  ) async {
    final result = await _open(tester, (WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const Key('contractor-details-rating_quality')),
        '7',
      );
    });

    expect(find.byKey(const Key('contractor-details-dialog')), findsOneWidget);
    expect(result, isNull);
    expect(find.text('Höchstens 5.0'), findsOneWidget);
  });

  testWidgets('a comma decimal is accepted, as a German keyboard produces it', (
    tester,
  ) async {
    final result = await _open(tester, (WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const Key('contractor-details-rate')),
        '92,50',
      );
    });

    expect(result, <String, Object?>{'hourly_rate': 92.5});
  });

  testWidgets('the active switch is part of the same patch', (tester) async {
    final result = await _open(tester, (WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('contractor-details-active')));
      await tester.pumpAndSettle();
    });

    expect(result, <String, Object?>{'is_active': false});
  });

  testWidgets('several changes travel together', (tester) async {
    final result = await _open(tester, (WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const Key('contractor-details-rate')),
        '90',
      );
      await tester.enterText(
        find.byKey(const Key('contractor-details-area')),
        'Berlin gesamt',
      );
      await tester.enterText(
        find.byKey(const Key('contractor-details-rating_speed')),
        '4',
      );
    });

    expect(result, <String, Object?>{
      'hourly_rate': 90.0,
      'service_area': 'Berlin gesamt',
      'rating_speed': 4.0,
    });
  });

  testWidgets('renders without overflow at a phone width', (tester) async {
    tester.view.physicalSize = const Size(380, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showContractorDetailsDialog(
                context,
                details: _details(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
