import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/ledger.dart';
import '../../components/responsive_constraints.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  List<LedgerAccountRecord> _accounts = const [];
  List<LedgerEntryRecord> _entries = const [];
  String? _status;
  String _filterEntityType = 'none';
  String _filterPeriodFrom = '';
  String _filterPeriodTo = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Entries'),
                Tab(text: 'Accounts'),
                Tab(text: 'Import'),
              ],
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_status!),
                ),
              ),
            const SizedBox(height: AppSpacing.component),
            Expanded(
              child: TabBarView(
                children: [_entriesTab(), _accountsTab(), _importTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entriesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _openAddEntryDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Entry'),
            ),
            OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
            SizedBox(
              width: ResponsiveConstraints.itemWidth(context, idealWidth: 220),
              child: DropdownButtonFormField<String>(
                value: _filterEntityType,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('Entity: none')),
                  DropdownMenuItem(
                    value: 'property',
                    child: Text('Entity: property'),
                  ),
                  DropdownMenuItem(
                    value: 'portfolio',
                    child: Text('Entity: portfolio'),
                  ),
                  DropdownMenuItem(
                    value: 'asset_property',
                    child: Text('Entity: asset property'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => _filterEntityType = value);
                  _reload();
                },
                decoration: const InputDecoration(labelText: 'Entity Type'),
              ),
            ),
            SizedBox(
              width: ResponsiveConstraints.itemWidth(context, idealWidth: 140),
              child: TextFormField(
                initialValue: _filterPeriodFrom,
                decoration: const InputDecoration(labelText: 'From (YYYY-MM)'),
                onChanged: (value) => _filterPeriodFrom = value.trim(),
                onFieldSubmitted: (_) => _reload(),
              ),
            ),
            SizedBox(
              width: ResponsiveConstraints.itemWidth(context, idealWidth: 140),
              child: TextFormField(
                initialValue: _filterPeriodTo,
                decoration: const InputDecoration(labelText: 'To (YYYY-MM)'),
                onChanged: (value) => _filterPeriodTo = value.trim(),
                onFieldSubmitted: (_) => _reload(),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(
          child:
              _entries.isEmpty
                  ? const Center(child: Text('No ledger entries yet.'))
                  : Card(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Posted')),
                          DataColumn(label: Text('Period')),
                          DataColumn(label: Text('Entity Type')),
                          DataColumn(label: Text('Direction')),
                          DataColumn(label: Text('Amount')),
                          DataColumn(label: Text('Currency')),
                          DataColumn(label: Text('Account')),
                          DataColumn(label: Text('Memo')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows:
                            _entries.map((entry) {
                              String? account;
                              for (final acc in _accounts) {
                                if (acc.id == entry.accountId) {
                                  account = acc.name;
                                  break;
                                }
                              }
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        entry.postedAt,
                                      ).toIso8601String().substring(0, 10),
                                    ),
                                  ),
                                  DataCell(Text(entry.periodKey)),
                                  DataCell(_entityTypeCell(entry.entityType)),
                                  DataCell(Text(entry.direction)),
                                  DataCell(
                                    Text(entry.amount.toStringAsFixed(2)),
                                  ),
                                  DataCell(Text(entry.currencyCode)),
                                  DataCell(Text(account ?? entry.accountId)),
                                  DataCell(
                                    SizedBox(
                                      width: ResponsiveConstraints.itemWidth(
                                        context,
                                        idealWidth: 220,
                                      ),
                                      child: Text(
                                        entry.memo ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        TextButton(
                                          onPressed:
                                              () => _openEditEntryDialog(entry),
                                          child: const Text('Edit'),
                                        ),
                                        TextButton(
                                          onPressed:
                                              () => _deleteEntry(entry.id),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                      ),
                    ),
                  ),
        ),
      ],
    );
  }

  Widget _accountsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _openAddAccountDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Account'),
            ),
            OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(
          child:
              _accounts.isEmpty
                  ? const Center(child: Text('No accounts yet.'))
                  : ListView.builder(
                    itemCount: _accounts.length,
                    itemBuilder: (context, index) {
                      final account = _accounts[index];
                      return Card(
                        child: ListTile(
                          title: Text(account.name),
                          subtitle: Text('Kind: ${account.kind}'),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => _renameAccount(account),
                                child: const Text('Rename'),
                              ),
                              TextButton(
                                onPressed: () => _deleteAccount(account.id),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _importTab() {
    return Align(
      alignment: Alignment.topLeft,
      child: ElevatedButton.icon(
        onPressed: _runLedgerImportWizard,
        icon: const Icon(Icons.upload_file),
        label: const Text('Run Ledger CSV Import'),
      ),
    );
  }

  Future<void> _reload() async {
    final repo = ref.read(ledgerRepositoryProvider);
    final accounts = await repo.listAccounts();
    final entries = await repo.listEntries(
      entityType: _filterEntityType.trim().isEmpty ? null : _filterEntityType,
      periodFrom: _filterPeriodFrom.trim().isEmpty ? null : _filterPeriodFrom,
      periodTo: _filterPeriodTo.trim().isEmpty ? null : _filterPeriodTo,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _accounts = accounts;
      _entries = entries;
    });
  }

  Future<void> _openAddAccountDialog() async {
    final nameController = TextEditingController();
    String kind = 'other';
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Ledger Account'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: kind,
                    items: const [
                      DropdownMenuItem(value: 'income', child: Text('income')),
                      DropdownMenuItem(
                        value: 'expense',
                        child: Text('expense'),
                      ),
                      DropdownMenuItem(value: 'capex', child: Text('capex')),
                      DropdownMenuItem(value: 'debt', child: Text('debt')),
                      DropdownMenuItem(value: 'other', child: Text('other')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => kind = value);
                    },
                    decoration: const InputDecoration(labelText: 'Kind'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    await ref
                        .read(ledgerRepositoryProvider)
                        .createAccount(name: name, kind: kind);
                    if (context.mounted) Navigator.of(context).pop();
                    await _reload();
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
    nameController.dispose();
  }

  Future<void> _renameAccount(LedgerAccountRecord account) async {
    final controller = TextEditingController(text: account.name);
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Rename Account'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  await ref
                      .read(ledgerRepositoryProvider)
                      .renameAccount(accountId: account.id, name: name);
                  if (context.mounted) Navigator.of(context).pop();
                  await _reload();
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
    controller.dispose();
  }

  Future<void> _deleteAccount(String id) async {
    try {
      await ref.read(ledgerRepositoryProvider).deleteAccount(id);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '$error');
    }
  }

  Future<void> _openAddEntryDialog() async {
    await _entryDialog();
  }

  Future<void> _openEditEntryDialog(LedgerEntryRecord entry) async {
    await _entryDialog(existing: entry);
  }

  Future<void> _entryDialog({LedgerEntryRecord? existing}) async {
    final isEdit = existing != null;
    final postedAtController = TextEditingController(
      text:
          (existing?.postedAt ?? DateTime.now().millisecondsSinceEpoch)
              .toString(),
    );
    final amountController = TextEditingController(
      text: (existing?.amount ?? 0).toStringAsFixed(2),
    );
    final counterpartyController = TextEditingController(
      text: existing?.counterparty ?? '',
    );
    final memoController = TextEditingController(text: existing?.memo ?? '');
    var direction = existing?.direction ?? 'out';
    var entityType = existing?.entityType ?? 'none';
    final currencyCode = existing?.currencyCode ?? 'EUR';
    final entityIdController = TextEditingController(
      text: existing?.entityId ?? '',
    );
    final currencyCodeController = TextEditingController(text: currencyCode);
    var selectedAccountId =
        existing?.accountId ??
        (_accounts.isNotEmpty ? _accounts.first.id : null);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'Edit Entry' : 'Add Entry'),
              content: SizedBox(
                width: ResponsiveConstraints.dialogWidth(
                  context,
                  maxWidth: 520,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: selectedAccountId,
                        items:
                            _accounts
                                .map(
                                  (account) => DropdownMenuItem(
                                    value: account.id,
                                    child: Text(account.name),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            (value) =>
                                setDialogState(() => selectedAccountId = value),
                        decoration: const InputDecoration(labelText: 'Account'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: postedAtController,
                        decoration: const InputDecoration(
                          labelText: 'Posted At (epoch ms)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: direction,
                        items: const [
                          DropdownMenuItem(value: 'in', child: Text('in')),
                          DropdownMenuItem(value: 'out', child: Text('out')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => direction = value);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Direction',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: amountController,
                        decoration: const InputDecoration(labelText: 'Amount'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: counterpartyController,
                        decoration: const InputDecoration(
                          labelText: 'Counterparty',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: memoController,
                        decoration: const InputDecoration(labelText: 'Memo'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: entityType,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('none')),
                          DropdownMenuItem(
                            value: 'property',
                            child: Text('property'),
                          ),
                          DropdownMenuItem(
                            value: 'portfolio',
                            child: Text('portfolio'),
                          ),
                          DropdownMenuItem(
                            value: 'asset_property',
                            child: Text('asset property'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => entityType = value);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Entity type',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: entityIdController,
                        decoration: const InputDecoration(
                          labelText: 'Entity id',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: currencyCodeController,
                        decoration: const InputDecoration(
                          labelText: 'Currency code',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final accountId =
                        selectedAccountId ??
                        (_accounts.isNotEmpty ? _accounts.first.id : null);
                    final postedAt = int.tryParse(
                      postedAtController.text.trim(),
                    );
                    final amount = double.tryParse(
                      amountController.text.trim(),
                    );
                    if (accountId == null ||
                        postedAt == null ||
                        amount == null) {
                      return;
                    }
                    final repo = ref.read(ledgerRepositoryProvider);
                    if (isEdit) {
                      await repo.updateEntry(
                        LedgerEntryRecord(
                          id: existing.id,
                          entityType: entityType,
                          entityId:
                              entityIdController.text.trim().isEmpty
                                  ? null
                                  : entityIdController.text.trim(),
                          accountId: accountId,
                          postedAt: postedAt,
                          periodKey: ref
                              .read(ledgerServiceProvider)
                              .derivePeriodKey(postedAt),
                          direction: direction,
                          amount: amount.abs(),
                          currencyCode:
                              currencyCodeController.text.trim().isEmpty
                                  ? 'EUR'
                                  : currencyCodeController.text.trim(),
                          counterparty:
                              counterpartyController.text.trim().isEmpty
                                  ? null
                                  : counterpartyController.text.trim(),
                          memo:
                              memoController.text.trim().isEmpty
                                  ? null
                                  : memoController.text.trim(),
                          documentId: existing.documentId,
                          createdAt: existing.createdAt,
                        ),
                      );
                    } else {
                      await repo.createEntry(
                        entityType: entityType,
                        entityId:
                            entityIdController.text.trim().isEmpty
                                ? null
                                : entityIdController.text.trim(),
                        accountId: accountId,
                        postedAt: postedAt,
                        direction: direction,
                        amount: amount.abs(),
                        currencyCode:
                            currencyCodeController.text.trim().isEmpty
                                ? 'EUR'
                                : currencyCodeController.text.trim(),
                        counterparty:
                            counterpartyController.text.trim().isEmpty
                                ? null
                                : counterpartyController.text.trim(),
                        memo:
                            memoController.text.trim().isEmpty
                                ? null
                                : memoController.text.trim(),
                      );
                    }
                    if (mounted) {
                      Navigator.of(this.context, rootNavigator: true).pop();
                    }
                    await _reload();
                  },
                  child: Text(isEdit ? 'Save' : 'Create'),
                ),
              ],
            );
          },
        );
      },
    );

    postedAtController.dispose();
    amountController.dispose();
    counterpartyController.dispose();
    memoController.dispose();
    entityIdController.dispose();
    currencyCodeController.dispose();
  }

  Future<void> _deleteEntry(String id) async {
    await ref.read(ledgerRepositoryProvider).deleteEntry(id);
    await _reload();
  }

  Widget _entityTypeCell(String value) {
    final normalized = value.trim().isEmpty ? 'none' : value.trim();
    return Tooltip(
      message: normalized,
      child: SizedBox(
        width: ResponsiveConstraints.itemWidth(context, idealWidth: 130),
        child: Text(normalized, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Future<void> _runLedgerImportWizard() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (file == null) {
      return;
    }
    try {
      final repo = ref.read(importsRepositoryProvider);
      final job = await repo.createJob(kind: 'csv', targetScope: 'global');
      await repo.saveMapping(
        importJobId: job.id,
        targetTable: 'ledger_entries',
        mapping: const {
          'posted_at': 'posted_at',
          'account_name': 'account_name',
          'account_kind': 'account_kind',
          'direction': 'direction',
          'amount': 'amount',
          'entity_type': 'entity_type',
          'entity_id': 'entity_id',
          'counterparty': 'counterparty',
          'memo': 'memo',
          'currency_code': 'currency_code',
          '__auto_create_accounts': '1',
        },
      );
      final imported = await repo.runCsvImport(
        jobId: job.id,
        csvPath: file.path,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Imported $imported ledger entries.';
      });
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Ledger import failed: $error';
      });
    }
  }
}
