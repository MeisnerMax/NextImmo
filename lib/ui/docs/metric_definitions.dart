import 'package:flutter/widgets.dart';

import '../i18n/app_strings.dart';

class MetricDefinition {
  const MetricDefinition({
    required this.key,
    required this.title,
    required this.description,
  });

  final String key;
  final String title;
  final String description;
}

class MetricDefinitions {
  static const Map<String, MetricDefinition>
  _definitions = <String, MetricDefinition>{
    'cap_rate': MetricDefinition(
      key: 'cap_rate',
      title: 'Cap Rate',
      description:
          'Net Operating Income divided by Purchase Price. Measures unlevered return in year 1.',
    ),
    'irr': MetricDefinition(
      key: 'irr',
      title: 'IRR',
      description:
          'Internal Rate of Return based on projected cashflows including exit.',
    ),
    'cash_on_cash': MetricDefinition(
      key: 'cash_on_cash',
      title: 'Cash on Cash',
      description:
          'Annual pre-tax cashflow divided by total cash invested in year 1.',
    ),
    'noi': MetricDefinition(
      key: 'noi',
      title: 'NOI',
      description:
          'Net Operating Income equals operating income minus operating expenses before debt service.',
    ),
    'dscr': MetricDefinition(
      key: 'dscr',
      title: 'DSCR',
      description: 'NOI divided by Annual Debt Service. Measures loan safety.',
    ),
    'vacancy': MetricDefinition(
      key: 'vacancy',
      title: 'Vacancy',
      description:
          'Expected percentage of gross scheduled income lost due to vacancy.',
    ),
    'mao': MetricDefinition(
      key: 'mao',
      title: 'MAO',
      description:
          'Maximum Allowable Offer calculated to meet selected investment target.',
    ),
    'monthly_cashflow': MetricDefinition(
      key: 'monthly_cashflow',
      title: 'Monthly Cashflow',
      description: 'Expected average monthly cashflow before taxes in year 1.',
    ),
    'annual_cashflow': MetricDefinition(
      key: 'annual_cashflow',
      title: 'Annual Cashflow',
      description: 'Total projected year 1 pre-tax cashflow.',
    ),
    'roi': MetricDefinition(
      key: 'roi',
      title: 'ROI',
      description:
          'Total projected profit divided by total cash invested over the hold period.',
    ),
    'purchase_price': MetricDefinition(
      key: 'purchase_price',
      title: 'Purchase Price',
      description:
          'Acquisition price used as entry basis for financing and return metrics.',
    ),
    'rehab_budget': MetricDefinition(
      key: 'rehab_budget',
      title: 'Rehab Budget',
      description:
          'Planned renovation spend included in total cash invested and MAO logic.',
    ),
    'total_cash_invested': MetricDefinition(
      key: 'total_cash_invested',
      title: 'Total Cash Invested',
      description:
          'Total up-front equity including down payment, rehab, and closing costs.',
    ),
    'arv_estimate': MetricDefinition(
      key: 'arv_estimate',
      title: 'ARV Estimate',
      description:
          'Weighted estimate of after-repair value based on selected sales comps.',
    ),
    'rent_estimate': MetricDefinition(
      key: 'rent_estimate',
      title: 'Rent Estimate',
      description:
          'Weighted estimate of monthly rent based on selected rental comps.',
    ),
    'gsi': MetricDefinition(
      key: 'gsi',
      title: 'GSI',
      description: 'Gross Scheduled Income before vacancy and credit losses.',
    ),
    'debt_service': MetricDefinition(
      key: 'debt_service',
      title: 'Debt Service',
      description: 'Total loan payment obligations in the selected period.',
    ),
    'criteria': MetricDefinition(
      key: 'criteria',
      title: 'Criteria',
      description:
          'Rule-based pass/fail checks against selected investment thresholds.',
    ),
    'sensitivity': MetricDefinition(
      key: 'sensitivity',
      title: 'Sensitivity',
      description:
          'Scenario matrix showing metric changes across purchase and rent deltas.',
    ),
    'epc_rating': MetricDefinition(
      key: 'epc_rating',
      title: 'EPC Rating',
      description:
          'Building energy performance class from local certification scale.',
    ),
    'emissions': MetricDefinition(
      key: 'emissions',
      title: 'Emissions',
      description:
          'Estimated annual CO2 emissions intensity in kgCO2 per square meter.',
    ),
    'portfolio_kpi': MetricDefinition(
      key: 'portfolio_kpi',
      title: 'Portfolio KPI',
      description:
          'Aggregated KPI across assigned portfolio properties and scenarios.',
    ),
    'data_quality': MetricDefinition(
      key: 'data_quality',
      title: 'Data Quality',
      description:
          'Validation flags indicating missing, inconsistent, or risky input data.',
    ),
  };

  static MetricDefinition? byKey(BuildContext context, String key) {
    final definition = _definitions[_normalize(key)];
    if (definition == null) {
      return null;
    }
    return _localize(context, definition);
  }

  static String normalizeKey(String labelOrKey) => _normalize(labelOrKey);

  static MetricDefinition fallback(BuildContext context, String labelOrKey) {
    return MetricDefinition(
      key: _normalize(labelOrKey),
      title:
          labelOrKey.trim().isEmpty
              ? context.strings.text('Metric')
              : labelOrKey.trim(),
      description: context.strings.text(
        'Calculated output based on scenario inputs, settings, and selected assumptions.',
      ),
    );
  }

  static MetricDefinition _localize(
    BuildContext context,
    MetricDefinition definition,
  ) {
    return MetricDefinition(
      key: definition.key,
      title: context.strings.text(definition.title),
      description: context.strings.text(definition.description),
    );
  }

  static String _normalize(String value) {
    final normalized = value.trim().toLowerCase().replaceAll('%', '');
    switch (normalized) {
      case 'cap rate':
        return 'cap_rate';
      case 'coc':
      case 'cash on cash':
        return 'cash_on_cash';
      case 'noi y1':
      case 'noi':
        return 'noi';
      case 'monthly cashflow':
      case 'monthly cf':
        return 'monthly_cashflow';
      case 'annual cashflow':
        return 'annual_cashflow';
      case 'dscr':
        return 'dscr';
      case 'mao':
        return 'mao';
      case 'vacancy':
        return 'vacancy';
      case 'irr':
        return 'irr';
      case 'gsi':
        return 'gsi';
      case 'debt':
      case 'debt service':
        return 'debt_service';
      case 'purchase price':
        return 'purchase_price';
      case 'rehab budget':
        return 'rehab_budget';
      case 'total cash invested':
        return 'total_cash_invested';
      case 'arv estimate':
        return 'arv_estimate';
      case 'rent estimate':
        return 'rent_estimate';
      default:
        return normalized.replaceAll(' ', '_');
    }
  }
}
