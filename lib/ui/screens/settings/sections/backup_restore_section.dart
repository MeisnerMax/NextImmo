part of '../../settings_screen.dart';

/// Backup & Restore section (workspace path plus backup/restore actions). Split
/// out of the screen body for BIG-009. `_createBackup`/`_restoreBackup` and
/// their confirmations stay on the state class.
extension _BackupRestoreSection on _SettingsScreenState {
  Widget buildBackupRestoreSection(
    BuildContext context, {
    required AppSettingsRecord settings,
    required bool canBackupRestore,
    required bool canExport,
  }) {
    final s = _strings;
    return Column(
      children: [
        _introCard(
          title: s.text('Backup & Restore'),
          description: s.text(
            'Keep workspace paths visible and separate backup actions from general defaults.',
          ),
          warning: s.text(
            'Restore replaces the current database and docs after creating a pre-restore backup.',
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        _section(
          context,
          title: s.text('Workspace and Backup'),
          children: [
            SizedBox(
              width: ResponsiveConstraints.itemWidth(
                context,
                idealWidth: 540,
                maxWidth: 720,
              ),
              child: TextField(
                controller: _workspaceRootController,
                enabled: canExport || canBackupRestore,
                decoration: _settingInputDecoration(
                  s.text('Workspace Root Path (optional)'),
                  helperText: s.text('Optional root folder for the workspace.'),
                ),
              ),
            ),
            SizedBox(
              width: ResponsiveConstraints.itemWidth(
                context,
                idealWidth: 540,
                maxWidth: 720,
              ),
              child: Text(
                s.lastBackupLabel(
                  settings.lastBackupAt == null
                      ? s.never
                      : DateTime.fromMillisecondsSinceEpoch(
                        settings.lastBackupAt!,
                      ).toIso8601String(),
                  settings.lastBackupPath == null
                      ? ''
                      : ' | ${settings.lastBackupPath}',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: canExport ? _createBackup : null,
                  icon: const Icon(Icons.save_alt),
                  label: Text(s.text('Create Backup ZIP')),
                ),
                OutlinedButton.icon(
                  onPressed: canBackupRestore ? _restoreBackup : null,
                  icon: const Icon(Icons.restore),
                  label: Text(s.text('Restore from ZIP')),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
