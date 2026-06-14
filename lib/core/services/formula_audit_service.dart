import '../models/investment_modules.dart';

class FormulaAuditService {
  const FormulaAuditService();

  FormulaAuditEntry entry({
    required String formulaName,
    required String description,
    required Map<String, Object?> inputs,
    required double? result,
    required String unit,
    required String module,
    String? propertyId,
    String? scenarioId,
  }) {
    return FormulaAuditEntry(
      formulaName: formulaName,
      description: description,
      inputs: inputs,
      result: result,
      unit: unit,
      module: module,
      propertyId: propertyId,
      scenarioId: scenarioId,
      calculatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
