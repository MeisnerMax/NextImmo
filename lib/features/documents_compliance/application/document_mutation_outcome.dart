/// The result a document mutation hands back to the surface that triggered it
/// (DOCUMENTS-V2, Foundation §10).
///
/// Controllers still publish their action phase for the shared feedback
/// listener; this type exists so a *dialog* that owns the submit can react in
/// place — keep the input on a version conflict and show the server state as
/// a banner, explain a validation failure inline — instead of the discard
/// dialog the first Wave-2 cut opened from a `ref.listen`.
library;

import 'document_repository.dart';

sealed class DocumentMutationOutcome {
  const DocumentMutationOutcome();

  bool get succeeded => this is DocumentMutationSucceeded;
}

class DocumentMutationSucceeded extends DocumentMutationOutcome {
  const DocumentMutationSucceeded();
}

/// Optimistic-concurrency conflict with the current server document attached,
/// so a dialog can reseed ("Neu laden") or retry against the shown version
/// ("Erneut speichern") without losing what was typed.
class DocumentMutationConflicted extends DocumentMutationOutcome {
  const DocumentMutationConflicted(this.conflict);

  final DocumentVersionConflict conflict;
}

/// Every other failure. [kind] is null when the mutation never reached the
/// backend (missing scope, missing capability, read-only backend).
class DocumentMutationRejected extends DocumentMutationOutcome {
  const DocumentMutationRejected({required this.message, this.kind});

  final DocumentRepositoryFailureKind? kind;
  final String message;

  bool get isValidation =>
      kind == DocumentRepositoryFailureKind.validationFailed;
}
