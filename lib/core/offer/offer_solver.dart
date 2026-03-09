import '../engine/analysis_engine.dart';
import '../models/analysis_result.dart';
import '../models/inputs.dart';
import '../models/settings.dart';

class OfferSolveRequest {
  const OfferSolveRequest({
    required this.baseInputs,
    required this.settings,
    required this.incomeLines,
    required this.expenseLines,
    required this.targetMetricKey,
    required this.targetValue,
    this.lowBound = 0,
    required this.highBound,
    this.iterations = 60,
  });

  final ScenarioInputs baseInputs;
  final AppSettingsRecord settings;
  final List<IncomeLine> incomeLines;
  final List<ExpenseLine> expenseLines;
  final String targetMetricKey;
  final double targetValue;
  final double lowBound;
  final double highBound;
  final int iterations;
}

class OfferSolveResult {
  const OfferSolveResult({
    required this.mao,
    required this.analysisAtMao,
    required this.iterationsUsed,
    required this.warnings,
    required this.isFeasible,
    required this.finalGap,
    required this.lowBoundGap,
    required this.highBoundGap,
  });

  final double mao;
  final AnalysisResult analysisAtMao;
  final int iterationsUsed;
  final List<String> warnings;
  final bool isFeasible;
  final double? finalGap;
  final double? lowBoundGap;
  final double? highBoundGap;
}

class OfferSolver {
  const OfferSolver({AnalysisEngine engine = const AnalysisEngine()})
    : _engine = engine;

  final AnalysisEngine _engine;

  OfferSolveResult solve(OfferSolveRequest request) {
    var low = request.lowBound;
    var high =
        request.highBound <= request.lowBound
            ? request.lowBound + 1
            : request.highBound;

    var bestPrice = low;
    var bestAnalysis = _runAtPrice(request, bestPrice);
    final warnings = <String>[];
    var iterationsUsed = 0;

    final lowAnalysis = _runAtPrice(request, low);
    final highAnalysis = _runAtPrice(request, high);
    final lowGap = _metricGap(
      analysis: lowAnalysis,
      metricKey: request.targetMetricKey,
      targetValue: request.targetValue,
    );
    final highGap = _metricGap(
      analysis: highAnalysis,
      metricKey: request.targetMetricKey,
      targetValue: request.targetValue,
    );

    if (lowGap == null || highGap == null) {
      warnings.add(
        'Selected metric is not available for one or both solver bounds.',
      );
      return OfferSolveResult(
        mao: bestPrice,
        analysisAtMao: bestAnalysis,
        iterationsUsed: iterationsUsed,
        warnings: warnings,
        isFeasible: false,
        finalGap: null,
        lowBoundGap: lowGap,
        highBoundGap: highGap,
      );
    }

    if (lowGap < 0 && highGap < 0) {
      warnings.add('Target is infeasible inside provided price bounds.');
      return OfferSolveResult(
        mao: bestPrice,
        analysisAtMao: bestAnalysis,
        iterationsUsed: iterationsUsed,
        warnings: warnings,
        isFeasible: false,
        finalGap: lowGap,
        lowBoundGap: lowGap,
        highBoundGap: highGap,
      );
    }

    if (lowGap > 0 && highGap > 0) {
      warnings.add(
        'Target is satisfied at both bounds; MAO is capped by provided high bound.',
      );
    }

    if (lowGap < highGap) {
      warnings.add(
        'Metric appears non-monotonic across bounds; result is best-effort.',
      );
    }

    for (var i = 0; i < request.iterations; i++) {
      iterationsUsed = i + 1;
      final mid = (low + high) / 2;
      final analysis = _runAtPrice(request, mid);
      final gap = _metricGap(
        analysis: analysis,
        metricKey: request.targetMetricKey,
        targetValue: request.targetValue,
      );

      if (gap == null) {
        warnings.add('Selected metric is not available for solver iteration.');
        break;
      }

      if (gap >= 0) {
        low = mid;
        bestPrice = mid;
        bestAnalysis = analysis;
      } else {
        high = mid;
      }
    }

    return OfferSolveResult(
      mao: bestPrice,
      analysisAtMao: bestAnalysis,
      iterationsUsed: iterationsUsed,
      warnings: warnings,
      isFeasible:
          _metricGap(
                analysis: bestAnalysis,
                metricKey: request.targetMetricKey,
                targetValue: request.targetValue,
              ) !=
              null &&
          _metricGap(
                analysis: bestAnalysis,
                metricKey: request.targetMetricKey,
                targetValue: request.targetValue,
              )! >=
              0,
      finalGap: _metricGap(
        analysis: bestAnalysis,
        metricKey: request.targetMetricKey,
        targetValue: request.targetValue,
      ),
      lowBoundGap: lowGap,
      highBoundGap: highGap,
    );
  }

  AnalysisResult _runAtPrice(OfferSolveRequest request, double price) {
    final updated = request.baseInputs.copyWith(
      purchasePrice: price,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    return _engine.run(
      inputs: updated,
      settings: request.settings,
      incomeLines: request.incomeLines,
      expenseLines: request.expenseLines,
    );
  }

  double? _metricGap({
    required AnalysisResult analysis,
    required String metricKey,
    required double targetValue,
  }) {
    final metric = switch (metricKey) {
      'cash_on_cash' => analysis.metrics.cashOnCash,
      'irr' => analysis.metrics.irr,
      'monthly_cashflow' => analysis.metrics.monthlyCashflowYear1,
      'roi' => analysis.metrics.roi,
      _ => null,
    };
    return metric == null ? null : metric - targetValue;
  }
}
