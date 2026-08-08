import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/application/valuation_repository.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';

void main() {
  group('ValuationCaseStatus transitions', () {
    test('follows draft → inReview → approved → archived', () {
      expect(
        ValuationCaseStatus.draft.canTransitionTo(ValuationCaseStatus.inReview),
        isTrue,
      );
      expect(
        ValuationCaseStatus.inReview.canTransitionTo(
          ValuationCaseStatus.approved,
        ),
        isTrue,
      );
      expect(
        ValuationCaseStatus.approved.canTransitionTo(
          ValuationCaseStatus.archived,
        ),
        isTrue,
      );
    });

    test('never reopens an approved or archived case', () {
      expect(
        ValuationCaseStatus.approved.canTransitionTo(ValuationCaseStatus.draft),
        isFalse,
      );
      expect(
        ValuationCaseStatus.approved.canTransitionTo(
          ValuationCaseStatus.inReview,
        ),
        isFalse,
      );
      for (final target in ValuationCaseStatus.values) {
        expect(
          ValuationCaseStatus.archived.canTransitionTo(target),
          isFalse,
          reason: 'archiviert ist terminal',
        );
      }
      expect(ValuationCaseStatus.archived.isTerminal, isTrue);
    });

    test('allows sending a review back to draft', () {
      expect(
        ValuationCaseStatus.inReview.canTransitionTo(ValuationCaseStatus.draft),
        isTrue,
      );
    });
  });

  group('ValuationKeysetCursor', () {
    test('round-trips timestamp and id', () {
      final cursor = ValuationKeysetCursor(
        timestamp: DateTime.utc(2026, 7, 28, 12, 15, 30),
        id: 'case-1',
      );

      final decoded = ValuationKeysetCursor.decode(cursor.encode())!;

      expect(decoded.id, 'case-1');
      expect(decoded.timestamp, DateTime.utc(2026, 7, 28, 12, 15, 30));
    });

    test('rejects malformed cursors instead of guessing', () {
      expect(ValuationKeysetCursor.decode(null), isNull);
      expect(ValuationKeysetCursor.decode('nonsense'), isNull);
      expect(ValuationKeysetCursor.decode('2026-07-28T12:00:00Z|'), isNull);
      expect(ValuationKeysetCursor.decode('|case-1'), isNull);
    });
  });

  group('ValuationPageRequest', () {
    test('rejects an out-of-range page size', () {
      expect(() => ValuationPageRequest(limit: 0), throwsA(isA<AssertionError>()));
      expect(
        () => ValuationPageRequest(limit: 101),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ValuationRepositoryFailure', () {
    test('a version conflict must carry the conflict detail', () {
      expect(
        () => ValuationRepositoryFailure<void>(
          kind: ValuationRepositoryFailureKind.versionConflict,
          message: 'stale',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a non-conflict failure must not carry one', () {
      expect(
        () => ValuationRepositoryFailure<void>(
          kind: ValuationRepositoryFailureKind.forbidden,
          message: 'nope',
          versionConflict: const ValuationVersionConflict(
            expectedVersion: 1,
            actualVersion: 2,
          ),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('approvedImmutable is distinct from forbidden', () {
      const failure = ValuationRepositoryFailure<void>(
        kind: ValuationRepositoryFailureKind.approvedImmutable,
        message: 'Bewertung ist freigegeben.',
      );

      expect(failure.kind, isNot(ValuationRepositoryFailureKind.forbidden));
      expect(failure.versionConflict, isNull);
    });
  });
}
