import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/platform_error_presentation.dart';

PlatformRepositoryFailure<TaskDto> _failure(
  PlatformRepositoryFailureKind kind, {
  String message = 'Server said so',
  List<String> validationFields = const <String>[],
}) {
  return PlatformRepositoryFailure<TaskDto>(
    kind: kind,
    message: message,
    validationFields: validationFields,
    versionConflict: kind == PlatformRepositoryFailureKind.versionConflict
        ? PlatformVersionConflict(
            expectedVersion: 1,
            actualVersion: 2,
            currentTask: TaskDto(
              id: 'task-a',
              workspaceId: 'workspace-a',
              title: 'Heizung prüfen',
              priority: TaskPriority.normal,
              status: TaskStatus.open,
              createdAt: DateTime.utc(2026, 3, 31),
              updatedAt: DateTime.utc(2026, 3, 31),
              createdBy: 'user-1',
              updatedBy: 'user-1',
              version: 2,
            ),
          )
        : null,
  );
}

void main() {
  group('platformErrorDispositionOf', () {
    test('maps every failure kind onto its §12 behavior', () {
      const expected =
          <PlatformRepositoryFailureKind, PlatformErrorDisposition>{
            PlatformRepositoryFailureKind.notFound:
                PlatformErrorDisposition.notFound,
            PlatformRepositoryFailureKind.forbidden:
                PlatformErrorDisposition.forbidden,
            PlatformRepositoryFailureKind.validationFailed:
                PlatformErrorDisposition.fieldValidation,
            PlatformRepositoryFailureKind.versionConflict:
                PlatformErrorDisposition.versionConflict,
            PlatformRepositoryFailureKind.mutationConflict:
                PlatformErrorDisposition.mutationConflict,
            PlatformRepositoryFailureKind.mutationInProgress:
                PlatformErrorDisposition.retryInProgress,
            PlatformRepositoryFailureKind.dependencyConflict:
                PlatformErrorDisposition.infrastructure,
            PlatformRepositoryFailureKind.infrastructureFailure:
                PlatformErrorDisposition.infrastructure,
          };

      // Exhaustive by construction: a new failure kind without a row fails.
      expect(expected.keys, PlatformRepositoryFailureKind.values);
      expected.forEach((kind, disposition) {
        expect(
          platformErrorDispositionOf(_failure(kind)),
          disposition,
          reason: kind.name,
        );
      });
    });

    test('separates the AAL2 gate from an ordinary forbidden', () {
      // §11/§12: the DEC-025 gate message must render as the step-up state,
      // never as "Kein Zugriff" — a correctly secured session is not a
      // permission problem.
      expect(
        platformErrorDispositionOf(
          _failure(
            PlatformRepositoryFailureKind.forbidden,
            message: 'AAL2 is required for platform mutations',
          ),
        ),
        PlatformErrorDisposition.aalStepUpRequired,
      );
      expect(
        platformErrorDispositionOf(
          _failure(
            PlatformRepositoryFailureKind.forbidden,
            message: 'permission denied for table tasks',
          ),
        ),
        PlatformErrorDisposition.forbidden,
      );
    });
  });

  group('platformErrorMessageOf', () {
    test('uses the fixed §12 German copy where the contract fixes it', () {
      expect(
        platformErrorMessageOf(
          _failure(PlatformRepositoryFailureKind.mutationConflict),
        ),
        'Diese Aktion wurde bereits mit anderen Daten ausgeführt.',
      );
      expect(
        platformErrorMessageOf(
          _failure(PlatformRepositoryFailureKind.infrastructureFailure),
        ),
        'Aktion konnte nicht ausgeführt werden.',
      );
    });

    test('passes the controlled server message through otherwise', () {
      expect(
        platformErrorMessageOf(
          _failure(
            PlatformRepositoryFailureKind.validationFailed,
            message: 'Title is required',
            validationFields: const <String>['title'],
          ),
        ),
        'Title is required',
      );
      expect(
        platformErrorMessageOf(
          _failure(
            PlatformRepositoryFailureKind.forbidden,
            message: 'task.manage is required',
          ),
        ),
        'task.manage is required',
      );
    });
  });
}
