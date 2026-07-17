import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/contractor.dart';
import '../../../core/models/maintenance.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../templates/list_filter_template.dart';
import '../../components/nx_status_badge.dart';

class ContractorsScreen extends ConsumerStatefulWidget {
  const ContractorsScreen({super.key});

  @override
  ConsumerState<ContractorsScreen> createState() => _ContractorsScreenState();
}

class _ContractorsScreenState extends ConsumerState<ContractorsScreen> {
  String _searchQuery = '';
  String? _selectedTrade;
  ContractorRecord? _selectedContractor;
  bool _isLoading = false;
  List<ContractorRecord> _contractors = [];
  List<MaintenanceTicketRecord> _allTickets = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final contractorRepo = ref.read(contractorRepositoryProvider);
      final list = await contractorRepo.listContractors();
      if (!mounted) return;
      
      final maintRepo = ref.read(maintenanceRepositoryProvider);
      final tickets = await maintRepo.listTickets();
      if (!mounted) return;
      
      setState(() {
        _contractors = list;
        _allTickets = tickets;
        
        // Keep selection updated if it exists
        if (_selectedContractor != null) {
          final updated = list.firstWhere(
            (c) => c.id == _selectedContractor!.id,
            orElse: () => _selectedContractor!,
          );
          _selectedContractor = updated;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Laden der Handwerker: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<ContractorRecord> get _filteredContractors {
    return _contractors.where((c) {
      final matchesSearch = c.companyName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.contactName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.tradeCategory.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesTrade = _selectedTrade == null || c.tradeCategory == _selectedTrade;
      return matchesSearch && matchesTrade;
    }).toList();
  }

  List<MaintenanceTicketRecord> _getTicketsForContractor(ContractorRecord contractor) {
    return _allTickets.where((t) => t.vendorName?.toLowerCase() == contractor.companyName.toLowerCase()).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredContractors;
    final content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Side: List View
              Expanded(
                flex: 4,
                child: Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // List Header / Count
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.cardPadding),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${filtered.length} Handwerker gefunden',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // List of contractors
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text('Keine Handwerker gefunden.'),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final contractor = filtered[index];
                                  final isSelected = _selectedContractor?.id == contractor.id;
                                  final overallRating = contractor.overallRating;

                                  return ListTile(
                                    selected: isSelected,
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            contractor.companyName,
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        if (overallRating != null) ...[
                                          const Icon(Icons.star, color: Colors.amber, size: 14),
                                          const SizedBox(width: 4),
                                          Text(
                                            overallRating.toStringAsFixed(1),
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ],
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primaryContainer,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              contractor.tradeCategory,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              contractor.contactName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 11),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedContractor = contractor;
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.component),
              // Right Side: Detail View
              Expanded(
                flex: 6,
                child: _selectedContractor == null
                    ? Card(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.engineering_outlined,
                                size: 64,
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Wählen Sie einen Handwerker aus der Liste aus,\num Details und Leistungsstatistiken anzuzeigen.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _buildDetailView(_selectedContractor!),
              ),
            ],
          );

    return ListFilterTemplate(
      title: 'Handwerker-Stammdaten',
      breadcrumbs: const ['Instandhaltung', 'Handwerker'],
      subtitle: 'Verwalten Sie Profile, Kontaktdaten, Bewertungen und Kostenhistorien Ihrer Handwerkspartner.',
      primaryAction: ElevatedButton.icon(
        onPressed: _showAddContractorDialog,
        icon: const Icon(Icons.add),
        label: const Text('Handwerker hinzufügen'),
      ),
      filters: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Suche nach Name, Kontakt oder Gewerk...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              const VerticalDivider(width: 32),
              DropdownButton<String?>(
                value: _selectedTrade,
                hint: const Text('Alle Gewerke'),
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Alle Gewerke')),
                  ...kTradeCategories.map(
                    (trade) => DropdownMenuItem(value: trade, child: Text(trade)),
                  ),
                ],
                onChanged: (val) => setState(() => _selectedTrade = val),
              ),
            ],
          ),
        ),
      ),
      content: content,
    );
  }

  Widget _buildDetailView(ContractorRecord contractor) {
    final tickets = _getTicketsForContractor(contractor);
    final completedTickets = tickets.where((t) => t.status == 'resolved' || t.status == 'closed').toList();
    final activeTickets = tickets.where((t) => t.status != 'resolved' && t.status != 'closed').toList();
    
    double actualCostsSum = completedTickets.fold<double>(0.0, (sum, t) => sum + (t.costActual ?? 0.0));
    double estimateCostsSum = tickets.fold<double>(0.0, (sum, t) => sum + (t.costEstimate ?? 0.0));

    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card
          Card(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary.withValues(alpha: 0.08),
                    colorScheme.primary.withValues(alpha: 0.01),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              contractor.companyName,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Gewerk: ${contractor.tradeCategory}',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _showEditContractorDialog(contractor),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _showDeleteConfirmDialog(contractor),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Rating Display
                  Row(
                    children: [
                      const Text(
                        'Bewertung: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (contractor.overallRating != null) ...[
                        _buildStarRating(contractor.overallRating!),
                        const SizedBox(width: 8),
                        Text(
                          '${contractor.overallRating!.toStringAsFixed(1)} / 5.0',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ] else
                        const Text('Keine Bewertungen vorliegend'),
                      const Spacer(),
                      if (contractor.insuranceCertExpiry != null) ...[
                        _buildInsuranceExpiryBadge(contractor.insuranceCertExpiry!),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.component),

          // Statistics Row
          Row(
            children: [
              Expanded(
                child: _statCard(
                  title: 'Umsatz (Ist)',
                  value: '€ ${actualCostsSum.toStringAsFixed(2)}',
                  color: Colors.teal,
                  icon: Icons.payments_outlined,
                  subtitle: 'Aus erledigten Aufträgen',
                ),
              ),
              const SizedBox(width: AppSpacing.component),
              Expanded(
                child: _statCard(
                  title: 'Ausstehend (Plan)',
                  value: '€ ${estimateCostsSum.toStringAsFixed(2)}',
                  color: Colors.blue,
                  icon: Icons.hourglass_empty_outlined,
                  subtitle: 'Erwartetes Volumen gesamt',
                ),
              ),
              const SizedBox(width: AppSpacing.component),
              Expanded(
                child: _statCard(
                  title: 'Aufträge',
                  value: '${tickets.length} gesamt',
                  color: Colors.indigo,
                  icon: Icons.assignment_outlined,
                  subtitle: '${activeTickets.length} aktiv, ${completedTickets.length} erledigt',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),

          // Details Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kontakt- und Stammdaten', style: Theme.of(context).textTheme.titleMedium),
                  const Divider(height: 24),
                  _infoRow(Icons.person_outline, 'Ansprechpartner', contractor.contactName),
                  _infoRow(Icons.phone_outlined, 'Telefon', contractor.phone),
                  _infoRow(Icons.email_outlined, 'E-Mail', contractor.email),
                  _infoRow(Icons.map_outlined, 'Anschrift', contractor.address),
                  _infoRow(
                    Icons.euro_outlined,
                    'Stundensatz (Soll/Kalkulation)',
                    contractor.hourlyRate != null ? '€ ${contractor.hourlyRate!.toStringAsFixed(2)} / Std.' : 'Nicht erfasst',
                  ),
                  _infoRow(
                    Icons.explore_outlined,
                    'Einsatzgebiete',
                    contractor.serviceAreas.isEmpty ? 'Nicht erfasst' : contractor.serviceAreas.join(', '),
                  ),
                  _infoRow(Icons.notes_outlined, 'Notizen', contractor.notes ?? 'Keine Notizen vorhanden'),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.component),

          // Ratings Breakdown Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Leistungsbewertung', style: Theme.of(context).textTheme.titleMedium),
                      TextButton.icon(
                        onPressed: () => _showRatingFormDialog(contractor),
                        icon: const Icon(Icons.rate_review_outlined, size: 16),
                        label: const Text('Bewertung anpassen'),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _ratingBarRow('Preis-Leistung', contractor.ratingPrice),
                  _ratingBarRow('Qualität', contractor.ratingQuality),
                  _ratingBarRow('Zuverlässigkeit & Termintreue', contractor.ratingPunctuality),
                  _ratingBarRow('Schnelligkeit', contractor.ratingSpeed),
                  _ratingBarRow('Kommunikation', contractor.ratingCommunication),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.component),

          // Cost History and Linked Tickets
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Auftragshistorie', style: Theme.of(context).textTheme.titleMedium),
                  const Divider(height: 24),
                  tickets.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: Text('Bisher keine Tickets für diesen Handwerker hinterlegt.'),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: tickets.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final ticket = tickets[index];
                            final date = DateTime.fromMillisecondsSinceEpoch(ticket.reportedAt).toIso8601String().substring(0, 10);
                            
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(ticket.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text('Erstellt am: $date | Typ: ${ticket.category}'),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    ticket.costActual != null
                                        ? '€ ${ticket.costActual!.toStringAsFixed(2)} (Ist)'
                                        : (ticket.costEstimate != null ? '€ ${ticket.costEstimate!.toStringAsFixed(2)} (Soll)' : 'Keine Kosten'),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  _ticketStatusBadge(ticket.status),
                                ],
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsuranceExpiryBadge(int expiryTimestamp) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final remainingDays = (expiryTimestamp - now) / (1000 * 60 * 60 * 24);
    final expiryDate = DateTime.fromMillisecondsSinceEpoch(expiryTimestamp).toIso8601String().substring(0, 10);

    final Color color;
    final String label;

    if (remainingDays < 0) {
      color = Colors.red;
      label = 'Versicherungsnachweis abgelaufen ($expiryDate)';
    } else if (remainingDays < 30) {
      color = Colors.orange;
      label = 'Versicherung läuft bald ab ($expiryDate)';
    } else {
      color = Colors.green;
      label = 'Versicherung gültig bis $expiryDate';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _ticketStatusBadge(String status) {
    final NxBadgeKind kind;
    switch (status) {
      case 'open':
        kind = NxBadgeKind.info;
        break;
      case 'in_progress':
        kind = NxBadgeKind.warning;
        break;
      case 'resolved':
      case 'closed':
        kind = NxBadgeKind.success;
        break;
      default:
        kind = NxBadgeKind.neutral;
    }
    return NxStatusBadge(label: status.toUpperCase(), kind: kind);
  }

  Widget _statCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    required String subtitle,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold).merge(context.tabularNumericStyle),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 7,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingBarRow(String criterion, double? rating) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              criterion,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 6,
            child: Row(
              children: [
                if (rating != null) ...[
                  _buildStarRating(rating),
                  const SizedBox(width: 8),
                  Text(
                    rating.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ] else
                  const Text('Keine Bewertung', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStarRating(double rating, {double size = 18}) {
    final fullStars = rating.floor();
    final hasHalf = (rating - fullStars) >= 0.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 5; i++)
          Icon(
            i < fullStars
                ? Icons.star
                : (i == fullStars && hasHalf ? Icons.star_half : Icons.star_border),
            color: Colors.amber,
            size: size,
          ),
      ],
    );
  }

  void _showAddContractorDialog() {
    _showContractorFormDialog(null);
  }

  void _showEditContractorDialog(ContractorRecord contractor) {
    _showContractorFormDialog(contractor);
  }

  Future<void> _showContractorFormDialog(ContractorRecord? existing) async {
    final companyNameCtrl = TextEditingController(text: existing?.companyName ?? '');
    final tradeCategoryCtrl = TextEditingController(text: existing?.tradeCategory ?? kTradeCategories.first);
    final contactNameCtrl = TextEditingController(text: existing?.contactName ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    final hourlyRateCtrl = TextEditingController(text: existing?.hourlyRate?.toString() ?? '');
    final serviceAreasCtrl = TextEditingController(text: existing?.serviceAreas.join(', ') ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    
    DateTime? insuranceCertExpiry = existing?.insuranceCertExpiry != null
        ? DateTime.fromMillisecondsSinceEpoch(existing!.insuranceCertExpiry!)
        : null;

    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Handwerker erfassen' : 'Handwerker bearbeiten'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(context, maxWidth: 500),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: companyNameCtrl,
                      decoration: const InputDecoration(labelText: 'Firma / Name *'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: tradeCategoryCtrl.text,
                      items: kTradeCategories.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => tradeCategoryCtrl.text = val);
                      },
                      decoration: const InputDecoration(labelText: 'Gewerk *'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: contactNameCtrl,
                      decoration: const InputDecoration(labelText: 'Ansprechpartner *'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(labelText: 'Telefon *'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(labelText: 'E-Mail *'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: addressCtrl,
                      decoration: const InputDecoration(labelText: 'Anschrift *'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: hourlyRateCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Stundensatz (€/Std.)'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: serviceAreasCtrl,
                      decoration: const InputDecoration(labelText: 'Einsatzgebiete (Komma-getrennt)'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Notizen'),
                    ),
                    const SizedBox(height: 12),
                    // Date picker for insurance
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          insuranceCertExpiry == null
                              ? 'Kein Versicherungsnachweis'
                              : 'Gültig bis: ${insuranceCertExpiry!.toIso8601String().substring(0, 10)}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: insuranceCertExpiry ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 3650)),
                            );
                            if (picked != null) {
                              setDialogState(() => insuranceCertExpiry = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: const Text('Nachweis wählen'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final areas = serviceAreasCtrl.text
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList();
                  final rate = double.tryParse(hourlyRateCtrl.text.trim());

                  final contractorRepo = ref.read(contractorRepositoryProvider);
                  
                  if (existing == null) {
                    await contractorRepo.createContractor(
                      companyName: companyNameCtrl.text.trim(),
                      tradeCategory: tradeCategoryCtrl.text,
                      contactName: contactNameCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      address: addressCtrl.text.trim(),
                      hourlyRate: rate,
                      serviceAreas: areas,
                      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                      insuranceCertExpiry: insuranceCertExpiry?.millisecondsSinceEpoch,
                    );
                  } else {
                    final updated = ContractorRecord(
                      id: existing.id,
                      companyName: companyNameCtrl.text.trim(),
                      tradeCategory: tradeCategoryCtrl.text,
                      contactName: contactNameCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      address: addressCtrl.text.trim(),
                      hourlyRate: rate,
                      serviceAreas: areas,
                      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                      createdAt: existing.createdAt,
                      updatedAt: DateTime.now().millisecondsSinceEpoch,
                      ratingPrice: existing.ratingPrice,
                      ratingQuality: existing.ratingQuality,
                      ratingSpeed: existing.ratingSpeed,
                      ratingCommunication: existing.ratingCommunication,
                      ratingPunctuality: existing.ratingPunctuality,
                      insuranceCertExpiry: insuranceCertExpiry?.millisecondsSinceEpoch,
                      isActive: existing.isActive,
                    );
                    await contractorRepo.updateContractor(updated);
                  }

                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                  await _loadData();
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );

    companyNameCtrl.dispose();
    contactNameCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    addressCtrl.dispose();
    hourlyRateCtrl.dispose();
    serviceAreasCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _showDeleteConfirmDialog(ContractorRecord contractor) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Handwerker löschen?'),
        content: Text('Möchten Sie den Handwerker ${contractor.companyName} wirklich unwiderruflich aus den Stammdaten löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final contractorRepo = ref.read(contractorRepositoryProvider);
      await contractorRepo.deleteContractor(contractor.id);
      setState(() {
        _selectedContractor = null;
      });
      await _loadData();
    }
  }

  Future<void> _showRatingFormDialog(ContractorRecord contractor) async {
    double price = contractor.ratingPrice ?? 3.0;
    double quality = contractor.ratingQuality ?? 3.0;
    double speed = contractor.ratingSpeed ?? 3.0;
    double communication = contractor.ratingCommunication ?? 3.0;
    double reliability = contractor.ratingPunctuality ?? 3.0;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Bewertung abgeben: ${contractor.companyName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vergeben Sie Punkte von 1 (schlecht) bis 5 (hervorragend):', style: TextStyle(fontSize: 12)),
              const Divider(height: 24),
              _buildDialogRatingSelector('Preis-Leistung', price, (val) => setDialogState(() => price = val)),
              _buildDialogRatingSelector('Qualität', quality, (val) => setDialogState(() => quality = val)),
              _buildDialogRatingSelector('Zuverlässigkeit', reliability, (val) => setDialogState(() => reliability = val)),
              _buildDialogRatingSelector('Schnelligkeit', speed, (val) => setDialogState(() => speed = val)),
              _buildDialogRatingSelector('Kommunikation', communication, (val) => setDialogState(() => communication = val)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                final updated = ContractorRecord(
                  id: contractor.id,
                  companyName: contractor.companyName,
                  tradeCategory: contractor.tradeCategory,
                  contactName: contractor.contactName,
                  phone: contractor.phone,
                  email: contractor.email,
                  address: contractor.address,
                  hourlyRate: contractor.hourlyRate,
                  serviceAreas: contractor.serviceAreas,
                  notes: contractor.notes,
                  createdAt: contractor.createdAt,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                  ratingPrice: price,
                  ratingQuality: quality,
                  ratingSpeed: speed,
                  ratingCommunication: communication,
                  ratingPunctuality: reliability,
                  insuranceCertExpiry: contractor.insuranceCertExpiry,
                  isActive: contractor.isActive,
                );
                await ref.read(contractorRepositoryProvider).updateContractor(updated);
                
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                await _loadData();
              },
              child: const Text('Bewertung speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogRatingSelector(String title, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            children: List.generate(5, (index) {
              final starValue = index + 1.0;
              return IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  value >= starValue ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 26,
                ),
                onPressed: () => onChanged(starValue),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class ResponsiveConstraints {
  static double dialogWidth(BuildContext context, {required double maxWidth}) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < maxWidth) return width * 0.9;
    return maxWidth;
  }
}
