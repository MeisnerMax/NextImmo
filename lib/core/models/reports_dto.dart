import 'analysis_result.dart';
import 'comps.dart';
import 'criteria.dart';
import 'esg.dart';
import 'inputs.dart';
import 'property.dart';
import 'scenario.dart';

class ReportExportDto {
  const ReportExportDto({
    required this.property,
    required this.scenario,
    required this.inputs,
    required this.analysis,
    required this.criteria,
    required this.salesComps,
    required this.rentalComps,
    required this.esgProfile,
  });

  final PropertyRecord property;
  final ScenarioRecord scenario;
  final ScenarioInputs inputs;
  final AnalysisResult analysis;
  final CriteriaEvaluationResult? criteria;
  final List<CompSale> salesComps;
  final List<CompRental> rentalComps;
  final EsgProfileRecord? esgProfile;
}
