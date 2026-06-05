import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/nx_card.dart';
import '../components/nx_empty_state.dart';
import '../components/nx_status_badge.dart';
import '../state/app_state.dart';
import '../templates/list_filter_template.dart';
import '../theme/app_theme.dart';

class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sections = _helpSections
        .where((section) {
          if (_query.isEmpty) {
            return true;
          }
          final haystack =
              '${section.title} ${section.description} ${section.keywords.join(' ')}'
                  .toLowerCase();
          return haystack.contains(_query);
        })
        .toList(growable: false);

    return ListFilterTemplate(
      title: 'Hilfe',
      breadcrumbs: const ['Workspace', 'Hilfe'],
      subtitle:
          'Schnelle Orientierung für die wichtigsten Workflows und Eingaben.',
      filters: ListFilterBar(
        children: [
          SizedBox(
            width: context.viewport == AppViewport.mobile ? 220 : 360,
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Hilfe durchsuchen',
                prefixIcon: Icon(Icons.search_outlined),
              ),
              onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          NxStatusBadge(label: '${sections.length} Treffer', kind: NxBadgeKind.info),
        ],
      ),
      content:
          sections.isEmpty
              ? const NxEmptyState(
                title: 'Kein Treffer',
                description: 'Suchbegriff ändern oder löschen.',
                icon: Icons.search_off_outlined,
              )
              : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _WorkflowStrip(onOpen: _openPage),
                    const SizedBox(height: AppSpacing.component),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cardWidth =
                            constraints.maxWidth >= 1200
                                ? (constraints.maxWidth - AppSpacing.component * 2) / 3
                                : constraints.maxWidth >= 760
                                    ? (constraints.maxWidth - AppSpacing.component) / 2
                                    : constraints.maxWidth;
                        return Wrap(
                          spacing: AppSpacing.component,
                          runSpacing: AppSpacing.component,
                          children: [
                            for (final section in sections)
                              SizedBox(
                                width: cardWidth,
                                child: _HelpSectionCard(
                                  section: section,
                                  onOpen: () => _openPage(section.target),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
    );
  }

  void _openPage(GlobalPage page) {
    ref.read(globalPageProvider.notifier).state = page;
    ref.read(selectedPropertyIdProvider.notifier).state = null;
    ref.read(selectedScenarioIdProvider.notifier).state = null;
  }
}

class _WorkflowStrip extends StatelessWidget {
  const _WorkflowStrip({required this.onOpen});

  final ValueChanged<GlobalPage> onOpen;

  @override
  Widget build(BuildContext context) {
    final steps = [
      _WorkflowStep('1', 'Objekt öffnen', GlobalPage.properties),
      _WorkflowStep('2', 'Vermietung & BK prüfen', GlobalPage.rentalOverview),
      _WorkflowStep('3', 'Aufgaben bearbeiten', GlobalPage.tasks),
      _WorkflowStep('4', 'Dokumente sichern', GlobalPage.documents),
      _WorkflowStep('5', 'Reports erstellen', GlobalPage.reportTemplates),
    ];
    return NxCard(
      child: Wrap(
        spacing: AppSpacing.component,
        runSpacing: AppSpacing.component,
        children: [
          for (final step in steps)
            SizedBox(
              width: context.viewport == AppViewport.mobile ? double.infinity : 210,
              child: OutlinedButton(
                onPressed: () => onOpen(step.target),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(radius: 12, child: Text(step.number)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        step.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HelpSectionCard extends StatelessWidget {
  const _HelpSectionCard({required this.section, required this.onOpen});

  final _HelpSection section;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      variant: NxCardVariant.interactive,
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 190),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(section.icon, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              section.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final keyword in section.keywords.take(3))
                  NxStatusBadge(label: keyword, kind: NxBadgeKind.neutral),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowStep {
  const _WorkflowStep(this.number, this.label, this.target);

  final String number;
  final String label;
  final GlobalPage target;
}

class _HelpSection {
  const _HelpSection({
    required this.title,
    required this.description,
    required this.icon,
    required this.target,
    required this.keywords,
  });

  final String title;
  final String description;
  final IconData icon;
  final GlobalPage target;
  final List<String> keywords;
}

const _helpSections = <_HelpSection>[
  _HelpSection(
    title: 'Dashboard lesen',
    description:
        'Portfolio-Wert, offene Aufgaben, Wartung, Dokumentlücken und kritische Hinweise als Startpunkt nutzen.',
    icon: Icons.dashboard_outlined,
    target: GlobalPage.dashboard,
    keywords: ['KPIs', 'Wertentwicklung', 'Hinweise'],
  ),
  _HelpSection(
    title: 'Objekte verwalten',
    description:
        'Objekt öffnen, Einheiten prüfen, Szenarien bearbeiten und bei Bedarf archivieren oder endgültig löschen.',
    icon: Icons.home_work_outlined,
    target: GlobalPage.properties,
    keywords: ['Objekte', 'Einheiten', 'Szenario'],
  ),
  _HelpSection(
    title: 'Vermietung & BK',
    description:
        'Mieten, Nebenkosten, Gebäude- und Einheitskosten sowie Umlageschlüssel in einem Workflow prüfen.',
    icon: Icons.request_quote_outlined,
    target: GlobalPage.rentalOverview,
    keywords: ['Mieten', 'BK', 'Kosten'],
  ),
  _HelpSection(
    title: 'Aufgaben',
    description:
        'Operative Aufgaben nach Status, Priorität und Objekt steuern. Wiederkehrende Standards über Vorlagen pflegen.',
    icon: Icons.checklist_outlined,
    target: GlobalPage.tasks,
    keywords: ['Tasks', 'Priorität', 'Vorlagen'],
  ),
  _HelpSection(
    title: 'Dokumente',
    description:
        'Dateien ablegen, Typen zuordnen, Pflichtunterlagen prüfen und objektbezogene Dokumente auffindbar halten.',
    icon: Icons.folder_open_outlined,
    target: GlobalPage.documents,
    keywords: ['Dokumente', 'Pflicht', 'Ablage'],
  ),
  _HelpSection(
    title: 'Importe',
    description:
        'CSV-Spalten vor dem Import eindeutig zuordnen und anschließend Importläufe sowie Datenqualität prüfen.',
    icon: Icons.upload_file_outlined,
    target: GlobalPage.imports,
    keywords: ['CSV', 'Mapping', 'Qualität'],
  ),
  _HelpSection(
    title: 'ESG',
    description:
        'EPC-Ratings, Ablaufdaten, Emissionen und Zielwerte je Objekt pflegen und exportieren.',
    icon: Icons.energy_savings_leaf_outlined,
    target: GlobalPage.esg,
    keywords: ['EPC', 'Emissionen', 'Export'],
  ),
  _HelpSection(
    title: 'Administration',
    description:
        'Nutzer, Einstellungen, Kriterien, Report-Vorlagen und Audit Log zentral verwalten.',
    icon: Icons.admin_panel_settings_outlined,
    target: GlobalPage.settings,
    keywords: ['Users', 'Settings', 'Audit'],
  ),
];
