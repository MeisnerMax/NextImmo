/// Supabase adapter for the service-charge preview (`SERVICE-CHARGE-PREVIEW-01`).
///
/// One RPC, one shape, no command beside it. The preview is computed on demand
/// and stored nowhere, so there is nothing here to version, retry or reconcile
/// — which is why this adapter is the shortest one in the feature and should
/// stay that way until a settlement becomes a document.
///
/// Three refusals happen before the round trip, and every one of them is
/// refused server-side as well — this layer is not the server's only caller,
/// so a check here is a courtesy to the form and never the guarantee:
///
///   * **A period that is not whole months.** The booking periods of this
///     schema are calendar months; a range from the 15th has no period to fall
///     inside. Caught here so the form can say so without a round trip, and
///     caught again on the server because this layer is not the only caller.
///   * **A period that ends before it starts.** Same reason.
///   * **A period longer than 36 months.** An operating-cost period is at
///     most a year (§ 556 Abs. 3 BGB); the cap is wider so a multi-year
///     comparison stays possible, and low enough that a mistyped year is
///     refused instead of asking the server to walk decades of days.
///
/// The German mapping is deliberately small. Everything the server can refuse
/// here is either one of those three — already caught above — or a permission,
/// and a sentence this build has not seen before is passed through verbatim
/// rather than replaced with a guess.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/finance_ledger_port.dart';
import '../domain/service_charge_preview_dto.dart';
import 'supabase_finance_ledger_adapter.dart' show FinanceSupabaseGateway;

class SupabaseServiceChargePreviewAdapter implements ServiceChargePreviewPort {
  SupabaseServiceChargePreviewAdapter({required SupabaseClient client})
    : _gateway = _DirectGateway(client);

  SupabaseServiceChargePreviewAdapter.withGateway(this._gateway);

  final FinanceSupabaseGateway _gateway;

  @override
  Future<FinanceRepositoryResult<ServiceChargePreviewDto>> readPreview({
    required String workspaceId,
    required String propertyId,
    required DateTime from,
    required DateTime to,
  }) async {
    final DateTime start = DateTime(from.year, from.month, from.day);
    final DateTime end = DateTime(to.year, to.month, to.day);

    if (end.isBefore(start)) {
      return const FinanceRepositoryFailure<ServiceChargePreviewDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message: 'Der Abrechnungszeitraum endet vor seinem Beginn.',
        field: 'to',
      );
    }
    // The same cap the server applies, so a mistyped year is answered by the
    // form rather than by a round trip. The server keeps its own copy: this
    // layer is not its only caller.
    final int months =
        (end.year - start.year) * 12 + (end.month - start.month) + 1;
    if (months > 36) {
      return FinanceRepositoryFailure<ServiceChargePreviewDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Ein Abrechnungszeitraum umfasst höchstens 36 Monate; dieser '
            'umfasst $months. Nach § 556 Abs. 3 BGB ist ein '
            'Abrechnungszeitraum höchstens ein Jahr lang.',
        field: 'to',
      );
    }
    if (start.day != 1 || end != _lastDayOfMonth(end)) {
      return const FinanceRepositoryFailure<ServiceChargePreviewDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message:
            'Ein Abrechnungszeitraum läuft über ganze Monate: vom Ersten '
            'eines Monats bis zum Letzten eines Monats.',
        field: 'from',
      );
    }

    try {
      final response = await _gateway.callRpc(
        'property_service_charge_preview',
        <String, Object?>{
          'p_workspace_id': workspaceId,
          'p_property_id': propertyId,
          'p_from': _formatDate(start),
          'p_to': _formatDate(end),
        },
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return FinanceRepositorySuccess<ServiceChargePreviewDto>(
          ServiceChargePreviewDto.fromJson(_asMap(payload['entity'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapFailure(_asMap(payload['error']));
    } catch (_) {
      return const FinanceRepositoryFailure<ServiceChargePreviewDto>(
        kind: FinanceRepositoryFailureKind.infrastructureFailure,
        message: 'Die Abrechnung konnte nicht berechnet werden.',
      );
    }
  }
}

/// The last day of [value]'s month, computed by stepping to the first of the
/// next month and back a day — so February and leap years need no table.
DateTime _lastDayOfMonth(DateTime value) =>
    DateTime(value.year, value.month + 1, 1).subtract(const Duration(days: 1));

String _formatDate(DateTime value) {
  final String month = value.month.toString().padLeft(2, '0');
  final String day = value.day.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-$month-$day';
}

String? _germanFor(String message) => switch (message) {
  'Property not found' => 'Dieses Objekt gibt es nicht (mehr).',
  'This property is not permitted' =>
    'Für dieses Objekt fehlt die Berechtigung.',
  'Finance reads are not permitted' =>
    'Zum Lesen der Finanzdaten fehlt die Berechtigung (finance.read).',
  'AAL2 is required for finance reads' =>
    'Finanzdaten brauchen die Zwei-Faktor-Anmeldung.',
  _ => null,
};

FinanceRepositoryFailure<ServiceChargePreviewDto> _mapFailure(
  Map<String, dynamic> error,
) {
  final code = error['code'] is String ? error['code'] as String : '';
  final raw = error['message'] is String
      ? error['message'] as String
      : 'Die Anfrage wurde abgelehnt.';
  // The currency and whole-month refusals are composed by the server and
  // cannot be matched exactly. They come through verbatim, which is right:
  // both name the thing that is wrong.
  final message = _germanFor(raw) ?? raw;
  final field = error['field'] is String ? error['field'] as String : null;
  return switch (code) {
    'forbidden' => FinanceRepositoryFailure<ServiceChargePreviewDto>(
      kind: FinanceRepositoryFailureKind.forbidden,
      message: message,
      field: field,
    ),
    'not_found' => FinanceRepositoryFailure<ServiceChargePreviewDto>(
      kind: FinanceRepositoryFailureKind.notFound,
      message: message,
      field: field,
    ),
    'validation_failed' => FinanceRepositoryFailure<ServiceChargePreviewDto>(
      kind: FinanceRepositoryFailureKind.validationFailed,
      message: message,
      field: field,
    ),
    _ => FinanceRepositoryFailure<ServiceChargePreviewDto>(
      kind: FinanceRepositoryFailureKind.infrastructureFailure,
      message: message,
      field: field,
    ),
  };
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, dynamic entry) => MapEntry(key.toString(), entry));
  }
  throw const FormatException('Expected an object.');
}

class _DirectGateway implements FinanceSupabaseGateway {
  const _DirectGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> callRpc(String name, Map<String, Object?> params) =>
      _client.rpc<Object?>(name, params: params);
}
