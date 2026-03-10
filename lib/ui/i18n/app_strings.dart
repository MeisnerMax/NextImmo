import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('de'),
  ];

  static const Iterable<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ];

  static AppStrings of(BuildContext context) {
    final result = Localizations.of<AppStrings>(context, AppStrings);
    return result ?? const AppStrings(Locale('en'));
  }

  static Locale localeFromLanguageCode(String? languageCode) {
    switch ((languageCode ?? '').trim().toLowerCase()) {
      case 'de':
      case 'de_de':
        return const Locale('de');
      case 'en':
      case 'en_us':
      default:
        return const Locale('en');
    }
  }

  static String normalizeLanguageCode(String? languageCode) {
    final normalized = (languageCode ?? '').trim().toLowerCase();
    if (normalized.startsWith('de')) {
      return 'de';
    }
    return 'en';
  }

  bool get isGerman => locale.languageCode == 'de';

  String get appTitle => 'NexImmo';
  String get notSet => isGerman ? 'Nicht gesetzt' : 'Not set';
  String get never => isGerman ? 'nie' : 'never';

  String onOff(bool value) {
    if (isGerman) {
      return value ? 'An' : 'Aus';
    }
    return value ? 'On' : 'Off';
  }

  String languageName(String code) {
    switch (normalizeLanguageCode(code)) {
      case 'de':
        return isGerman ? 'Deutsch' : 'German';
      case 'en':
      default:
        return isGerman ? 'Englisch' : 'English';
    }
  }

  String userRoleLabel(String role) {
    switch (role) {
      case 'admin':
        return text('admin');
      case 'manager':
        return text('manager');
      case 'analyst':
        return text('analyst');
      case 'viewer':
        return text('viewer');
      default:
        return role;
    }
  }

  String entityTypeLabel(String entityType) {
    switch (entityType) {
      case 'property':
        return text('property');
      case 'scenario':
        return text('scenario');
      case 'portfolio':
        return text('portfolio');
      case 'document':
        return text('document');
      case 'task':
        return text('task');
      case 'notification':
        return text('notification');
      case 'ledger_entry':
        return text('ledger entry');
      default:
        return entityType;
    }
  }

  String unsavedChangesLabel(int count) {
    if (isGerman) {
      return '$count nicht gespeicherte Anderung${count == 1 ? '' : 'en'}';
    }
    return '$count unsaved change${count == 1 ? '' : 's'}';
  }

  String pendingSecurityChangesLabel(int count) {
    if (isGerman) {
      return '$count Sicherheitsanderung${count == 1 ? '' : 'en'} bereit';
    }
    return '$count security change${count == 1 ? '' : 's'} ready';
  }

  String applyingPendingChangesDetail(int count) {
    if (isGerman) {
      return '$count ausstehende Anderung${count == 1 ? '' : 'en'} werden angewendet.';
    }
    return 'Applying $count pending change${count == 1 ? '' : 's'}.';
  }

  String changedSectionsDetail(String sections) {
    if (sections.trim().isEmpty) {
      return text('Use Save Settings to commit the current draft.');
    }
    if (isGerman) {
      return 'Geanderte Bereiche: $sections';
    }
    return 'Changed sections: $sections';
  }

  String lastSavedLabel(String timestamp) {
    if (isGerman) {
      return 'Zuletzt gespeichert $timestamp';
    }
    return 'Last saved $timestamp';
  }

  String invalidSectionDetail(String section) {
    if (isGerman) {
      return 'Prufe $section auf leere oder unzulassige Werte.';
    }
    return 'Check $section for empty or out-of-range fields.';
  }

  String lastBackupLabel(String timestamp, String path) {
    if (isGerman) {
      return 'Letztes Backup: $timestamp$path';
    }
    return 'Last Backup: $timestamp$path';
  }

  String errorWithPrefix(String prefix, Object error) {
    if (isGerman) {
      return '$prefix: $error';
    }
    return '$prefix: $error';
  }

  String text(String value, [Map<String, Object?> args = const {}]) {
    var template = isGerman ? (_de[value] ?? value) : value;
    args.forEach((key, arg) {
      template = template.replaceAll('{$key}', '${arg ?? ''}');
    });
    return template;
  }

  static const Map<String, String> _de = <String, String>{
    'Portfolio': 'Portfolio',
    'Operations': 'Betrieb',
    'Governance': 'Governance',
    'System': 'System',
    'Dashboard': 'Dashboard',
    'Properties': 'Objekte',
    'Portfolios': 'Portfolios',
    'Scenario Compare': 'Szenariovergleich',
    'Tasks': 'Aufgaben',
    'Task Templates': 'Aufgabenvorlagen',
    'Maintenance': 'Instandhaltung',
    'Ledger': 'Buchungen',
    'Budgets': 'Budgets',
    'Data Imports': 'Datenimporte',
    'Notifications': 'Benachrichtigungen',
    'Documents': 'Dokumente',
    'Audit Log': 'Audit-Log',
    'Criteria': 'Kriterien',
    'Templates': 'Vorlagen',
    'Users': 'Benutzer',
    'Settings': 'Einstellungen',
    'Use clear defaults, isolate risky actions, and keep every change visible.':
        'Klare Standards verwenden, riskante Aktionen isolieren und jede Anderung sichtbar halten.',
    'Save Settings': 'Einstellungen speichern',
    'Saving...': 'Speichern...',
    'Reload': 'Neu laden',
    'Help': 'Hilfe',
    'Summary': 'Zusammenfassung',
    'Overview': 'Ubersicht',
    'Inputs': 'Eingaben',
    'Analysis': 'Analyse',
    'Market Comps': 'Marktvergleich',
    'Offer': 'Angebot',
    'Commercial': 'Vermietung',
    'Units': 'Einheiten',
    'Tenants': 'Mieter',
    'Leases': 'Mietvertrage',
    'Rent Roll': 'Mieterliste',
    'Operations Center': 'Betriebszentrale',
    'Budget vs Actual': 'Budget vs Ist',
    'Alerts': 'Warnungen',
    'Covenants': 'Covenants',
    'Audit': 'Audit',
    'Reports': 'Berichte',
    'Versions': 'Versionen',
    'Scenario': 'Szenario',
    'Scenarios': 'Szenarien',
    'Property Detail': 'Objektdetail',
    'Command Palette': 'Befehlspalette',
    'Search pages, assets, documents, tasks or run an action':
        'Seiten, Assets, Dokumente und Aufgaben suchen oder eine Aktion ausfuhren',
    'Arrow keys': 'Pfeiltasten',
    'Enter to run': 'Enter zum Ausfuhren',
    'No matching commands. Try a page, property, document or task.':
        'Keine passenden Befehle. Versuchen Sie eine Seite, ein Objekt, ein Dokument oder eine Aufgabe.',
    'New Property': 'Neues Objekt',
    'Jump to the property workspace and start a new asset flow':
        'Zum Objektbereich springen und einen neuen Asset-Workflow starten',
    'Open Overdue Tasks': 'Uberfallige Aufgaben offnen',
    'Go straight to the task queue filtered for overdue work':
        'Direkt zur Aufgabenliste mit uberfalligen Aufgaben wechseln',
    'Jump to Missing Documents': 'Zu fehlenden Dokumenten springen',
    'Open document compliance and review missing requirements':
        'Dokumenten-Compliance offnen und fehlende Anforderungen prufen',
    'Create Report Pack': 'Berichtspaket erstellen',
    'Open portfolio workflows to generate reporting packs':
        'Portfolio-Workflows offnen und Berichtspakete erzeugen',
    'Create Property': 'Objekt anlegen',
    'Start with the basics. You can add strategy, financial assumptions, rent data and documents after the property is created.':
        'Starten Sie mit den Grundlagen. Strategie, finanzielle Annahmen, Mietdaten und Dokumente konnen nach dem Anlegen im Objektbereich erganzt werden.',
    'Basic Information': 'Basisinformationen',
    'Property Details': 'Objektdetails',
    'Single Family': 'Einfamilienhaus',
    'Multi Family': 'Mehrfamilienhaus',
    'Apartment': 'Wohnung',
    'Commercial Asset': 'Gewerbe',
    'Required': 'Pflichtfeld',
    'Enter a valid unit count.':
        'Bitte eine gultige Anzahl an Einheiten eingeben.',
    'Next Steps': 'Nachste Schritte',
    'This property was created with the basics only. Add the next inputs to unlock a reliable analysis.':
        'Dieses Objekt wurde nur mit den Basisdaten angelegt. Ergaenzen Sie als Naechstes die wichtigsten Angaben fuer eine belastbare Analyse.',
    'Add financial assumptions': 'Finanzielle Annahmen erganzen',
    'Purchase price, financing and capex assumptions':
        'Kaufpreis, Finanzierung und CapEx-Annahmen pflegen',
    'Set strategy': 'Strategie festlegen',
    'Choose the base scenario and investment approach':
        'Basisszenario und Investitionsansatz festlegen',
    'Add rent data': 'Mietdaten erganzen',
    'Enter rent, vacancy and operating income data':
        'Mieten, Leerstand und laufende Ertrage erfassen',
    'Add documents': 'Dokumente hinzufugen',
    'Upload leases, diligence files and supporting material':
        'Mietvertraege, Due-Diligence-Dateien und Unterlagen hochladen',
    'Action': 'Aktion',
    'Page': 'Seite',
    'Result': 'Treffer',
    'Expand navigation': 'Navigation ausklappen',
    'Collapse navigation': 'Navigation einklappen',
    'Search': 'Suche',
    'Lock app': 'App sperren',
    'Back to list': 'Zuruck zur Liste',
    'Switch Workspace': 'Workspace wechseln',
    'Workspace': 'Workspace',
    'Cancel': 'Abbrechen',
    'Switch': 'Wechseln',
    'Switch User': 'Benutzer wechseln',
    'User': 'Benutzer',
    'Close': 'Schliessen',
    'Unable to load this table': 'Diese Tabelle konnte nicht geladen werden',
    'No records yet': 'Noch keine Eintrage',
    'Adjust filters or add a new record to populate this view.':
        'Filter anpassen oder einen neuen Eintrag anlegen, um diese Ansicht zu fullen.',
    'No data available.': 'Keine Daten verfugbar.',
    'Chart could not be loaded.': 'Diagramm konnte nicht geladen werden.',
    'Property Navigation': 'Objektnavigation',
    'Section': 'Bereich',
    'Create or select a scenario': 'Szenario erstellen oder auswahlen',
    'Create or select a scenario to open this section.':
        'Erstellen oder wahlen Sie ein Szenario aus, um diesen Bereich zu offnen.',
    'Error': 'Fehler',
    'Security initialization failed':
        'Sicherheitsinitialisierung fehlgeschlagen',
    'App is locked': 'App ist gesperrt',
    'Enter password to unlock this workspace.':
        'Passwort eingeben, um diesen Workspace zu entsperren.',
    'Password': 'Passwort',
    'Unlock': 'Entsperren',
    'Invalid password.': 'Ungultiges Passwort.',
    'General': 'Allgemein',
    'Analysis Defaults': 'Analyse-Standards',
    'Operations Defaults': 'Betriebs-Standards',
    'Appearance': 'Darstellung',
    'Security': 'Sicherheit',
    'Backup & Restore': 'Backup & Wiederherstellung',
    'Admin': 'Admin',
    'Risk': 'Risiko',
    'Locale, currency, and core scenario defaults.':
        'Sprache, Wahrung und zentrale Szenario-Standards.',
    'Underwriting, growth, exit, and financing defaults.':
        'Standards fur Underwriting, Wachstum, Exit und Finanzierung.',
    'Task, maintenance, covenant, and automation defaults.':
        'Standards fur Aufgaben, Instandhaltung, Covenants und Automatisierung.',
    'Thresholds and quality warning behavior.':
        'Schwellwerte und Verhalten von Qualitatswarnungen.',
    'Theme, density, and interface motion.':
        'Theme, Dichte und Bewegungen der Oberflache.',
    'App lock and restricted actions.':
        'App-Sperre und eingeschrankte Aktionen.',
    'Workspace path plus backup and restore actions.':
        'Workspace-Pfad sowie Backup- und Wiederherstellungsaktionen.',
    'Demo data and administrative helper settings.':
        'Demodaten und administrative Hilfseinstellungen.',
    'Saving settings...': 'Einstellungen werden gespeichert...',
    'Use Save Settings to commit the current draft.':
        'Mit Einstellungen speichern den aktuellen Entwurf ubernehmen.',
    'Use Apply Security in this section to commit them.':
        'Mit Sicherheit anwenden in diesem Bereich ubernehmen.',
    'All changes saved': 'Alle Anderungen gespeichert',
    'No local draft is pending.': 'Kein lokaler Entwurf ausstehend.',
    'Save Overview': 'Speicherubersicht',
    'General settings save through the header action. Security changes are applied separately inside the Security section.':
        'Allgemeine Einstellungen werden uber die Aktion im Header gespeichert. Sicherheitsanderungen werden separat im Sicherheitsbereich angewendet.',
    'This role can review settings, but cannot save configuration changes.':
        'Diese Rolle kann Einstellungen prufen, aber keine Konfigurationsanderungen speichern.',
    'Pending fields': 'Ausstehende Felder',
    'Changed sections': 'Geanderte Bereiche',
    'Selected section': 'Ausgewahlter Bereich',
    'No pending draft changes in this section.':
        'In diesem Bereich gibt es keine ausstehenden Entwurfsanderungen.',
    'Pending changes in this section':
        'Ausstehende Anderungen in diesem Bereich',
    'Enable App Lock': 'App-Sperre aktivieren',
    'App Lock Password': 'Passwort fur App-Sperre',
    'Keep current password': 'Aktuelles Passwort beibehalten',
    'Replace password': 'Passwort ersetzen',
    'Currency Code': 'Wahrungscode',
    'Locale': 'Format-Locale',
    'Default Horizon Years': 'Standard-Haltedauer Jahre',
    'Vacancy Rate': 'Leerstandsquote',
    'Management Fee Rate': 'Verwaltungsquote',
    'Maintenance Reserve Rate': 'Instandhaltungsrucklage',
    'CapEx Reserve Rate': 'CapEx-Rucklage',
    'Appreciation Rate': 'Wertsteigerungsrate',
    'Rent Growth Rate': 'Mietwachstumsrate',
    'Expense Growth Rate': 'Kostenwachstumsrate',
    'Sale Cost Rate': 'Verkaufsnebenkostenquote',
    'Acquisition Cost Rate': 'Ankaufsnebenkostenquote',
    'Disposition Closing Cost Rate': 'Verkaufsabschlusskostenquote',
    'Down Payment Rate': 'Eigenkapitalquote',
    'Interest Rate': 'Zinssatz',
    'Loan Term Years': 'Darlehenslaufzeit Jahre',
    'Market Rent Mode': 'Marktmiete-Modus',
    'Task Due Soon Days': 'Aufgaben in Kurze fallig',
    'Budget Year Start Month': 'Budgetjahr Startmonat',
    'Scenario Auto Daily Versions': 'Szenario Auto-Tagesversionen',
    'Auto Version User Id': 'Benutzer-ID fur Auto-Versionen',
    'Vacancy Alert Threshold': 'Schwellwert Leerstandswarnung',
    'NOI Drop Alert Threshold': 'Schwellwert NOI-Ruckgang',
    'EPC Expiry Warning Days': 'Tage bis EPC-Ablaufwarnung',
    'Rent Roll Stale Months': 'Monate bis veraltete Mieterliste',
    'Ledger Stale Days': 'Tage bis veraltete Buchungen',
    'Task Notifications': 'Aufgabenbenachrichtigungen',
    'Workspace Root Path': 'Workspace-Stammpfad',
    'Theme Mode': 'Theme-Modus',
    'Density Mode': 'Dichte-Modus',
    'Chart Animations': 'Diagramm-Animationen',
    'Enable Demo Seed Button': 'Demo-Seed-Schaltflache aktivieren',
    'These defaults shape new scenarios before property-specific inputs take over.':
        'Diese Standards formen neue Szenarien, bevor objektspezifische Eingaben ubernehmen.',
    'General Defaults': 'Allgemeine Standards',
    'Used in new scenarios and reports.':
        'Wird in neuen Szenarien und Berichten verwendet.',
    'Formatting profile such as de_DE or en_US.':
        'Formatierungsprofil wie de_DE oder en_US.',
    'Default Hold Period': 'Standard-Haltedauer',
    'Years used for new scenarios.': 'Jahre fur neue Szenarien.',
    'Language': 'Sprache',
    'Choose the language for all texts, tooltips and labels.':
        'Sprache fur alle Texte, Tooltips und Labels auswahlen.',
    'Keep underwriting assumptions consistent so new scenarios start from the same baseline.':
        'Underwriting-Annahmen konsistent halten, damit neue Szenarien mit derselben Basis starten.',
    'Operating Defaults': 'Betriebs-Standards',
    'Decimal value, for example 0.05 = 5.0%':
        'Dezimalwert, zum Beispiel 0.05 = 5.0%',
    'Growth and Exit': 'Wachstum und Exit',
    'Decimal value, for example 0.02 = 2.0%':
        'Dezimalwert, zum Beispiel 0.02 = 2.0%',
    'Decimal value, for example 0.06 = 6.0%':
        'Dezimalwert, zum Beispiel 0.06 = 6.0%',
    'Decimal value, for example 0.03 = 3.0%':
        'Dezimalwert, zum Beispiel 0.03 = 3.0%',
    'Financing': 'Finanzierung',
    'Decimal value, for example 0.25 = 25.0%':
        'Dezimalwert, zum Beispiel 0.25 = 25.0%',
    'Used for new financing assumptions.':
        'Wird fur neue Finanzierungsannahmen verwendet.',
    'Default Market Rent Mode': 'Standard-Marktmiete-Modus',
    'Optional market rent default.': 'Optionaler Standard fur Marktmiete.',
    'Use one operational baseline for generated work, budgets, and recurring checks.':
        'Eine gemeinsame operative Basis fur generierte Aufgaben, Budgets und wiederkehrende Prufungen verwenden.',
    'Workflow Defaults': 'Workflow-Standards',
    'Budget Year Start Month (1-12)': 'Budgetjahr Startmonat (1-12)',
    'Maintenance Due Soon Days': 'Instandhaltung bald fallig Tage',
    'Covenant Due Soon Days': 'Covenant bald fallig Tage',
    'Set thresholds that surface issues early without flooding daily work.':
        'Schwellwerte festlegen, die Probleme fruh sichtbar machen, ohne die Tagesarbeit zu uberfluten.',
    'Alert Thresholds': 'Warnschwellen',
    'Vacancy Alert Threshold (0-1)': 'Schwellwert Leerstandswarnung (0-1)',
    'NOI Drop Alert Threshold (0-1)': 'Schwellwert NOI-Ruckgang (0-1)',
    'Quality EPC Expiry Warning Days': 'Qualitat EPC-Ablaufwarnung Tage',
    'Quality Rent Roll Stale Months': 'Qualitat veraltete Mieterliste Monate',
    'Quality Ledger Stale Days': 'Qualitat veraltete Buchungen Tage',
    'Enable Task Notifications': 'Aufgabenbenachrichtigungen aktivieren',
    'Low-frequency administrative switches stay visible, but clearly separated from daily settings.':
        'Selten genutzte administrative Schalter bleiben sichtbar, sind aber klar von taglichen Einstellungen getrennt.',
    'Administrative helper settings should stay restricted to setup and test workflows.':
        'Administrative Hilfseinstellungen sollten auf Setup- und Test-Workflows beschrankt bleiben.',
    'Administrative Controls': 'Administrative Steuerung',
    'User id used for automated scenario versions.':
        'Benutzer-ID fur automatisierte Szenario-Versionen.',
    'Control density and motion so the interface stays predictable across desktop setups.':
        'Dichte und Bewegung steuern, damit die Oberflache auf Desktop-Setups vorhersehbar bleibt.',
    'UI and Accessibility': 'UI und Barrierefreiheit',
    'Light': 'Hell',
    'Dark': 'Dunkel',
    'Comfort': 'Komfort',
    'Compact': 'Kompakt',
    'Adaptive': 'Adaptiv',
    'Enable Chart Animations': 'Diagramm-Animationen aktivieren',
    'Protect local access without burying the controls in a generic form.':
        'Lokalen Zugriff schutzen, ohne die Steuerung in einem generischen Formular zu verstecken.',
    'App lock changes affect local access immediately after applying them.':
        'Anderungen an der App-Sperre wirken sofort nach dem Anwenden auf den lokalen Zugriff.',
    'Access Controls': 'Zugriffskontrollen',
    'New App Lock Password': 'Neues Passwort fur App-Sperre',
    'Leave empty to keep the current password.':
        'Leer lassen, um das aktuelle Passwort beizubehalten.',
    'Apply Security': 'Sicherheit anwenden',
    'Keep workspace paths visible and separate backup actions from general defaults.':
        'Workspace-Pfade sichtbar halten und Backup-Aktionen von allgemeinen Standards trennen.',
    'Restore replaces the current database and docs after creating a pre-restore backup.':
        'Die Wiederherstellung ersetzt die aktuelle Datenbank und Dokumente nach einem Vorab-Backup.',
    'Workspace and Backup': 'Workspace und Backup',
    'Workspace Root Path (optional)': 'Workspace-Stammpfad (optional)',
    'Optional root folder for the workspace.':
        'Optionaler Stammordner fur den Workspace.',
    'Create Backup ZIP': 'Backup-ZIP erstellen',
    'Restore from ZIP': 'Aus ZIP wiederherstellen',
    'Discard Draft Changes': 'Entwurfsanderungen verwerfen',
    'This reloads the saved settings and removes your unsaved local draft changes.':
        'Dadurch werden die gespeicherten Einstellungen neu geladen und lokale, ungespeicherte Entwurfsanderungen entfernt.',
    'Discard Draft': 'Entwurf verwerfen',
    'Insufficient permission to edit settings.':
        'Keine ausreichende Berechtigung zum Bearbeiten der Einstellungen.',
    'This role can review settings, but cannot save them.':
        'Diese Rolle kann Einstellungen prufen, aber nicht speichern.',
    'Review invalid values before saving.':
        'Ungultige Werte vor dem Speichern prufen.',
    'Settings saved.': 'Einstellungen gespeichert.',
    'Settings save failed.': 'Speichern der Einstellungen fehlgeschlagen.',
    'Security update blocked.': 'Sicherheitsaktualisierung blockiert.',
    'Provide a password before enabling app lock for the first time.':
        'Geben Sie ein Passwort an, bevor Sie die App-Sperre erstmals aktivieren.',
    'Applying security changes...':
        'Sicherheitsanderungen werden angewendet...',
    'Security settings updated.': 'Sicherheitseinstellungen aktualisiert.',
    'Local access controls were updated successfully.':
        'Lokale Zugriffskontrollen wurden erfolgreich aktualisiert.',
    'Security update failed.': 'Aktualisierung der Sicherheit fehlgeschlagen.',
    'Insufficient permission to export backups.':
        'Keine ausreichende Berechtigung zum Exportieren von Backups.',
    'Creating backup...': 'Backup wird erstellt...',
    'Backup created.': 'Backup erstellt.',
    'Backup failed.': 'Backup fehlgeschlagen.',
    'Insufficient permission to restore backups.':
        'Keine ausreichende Berechtigung zum Wiederherstellen von Backups.',
    'Restore Backup': 'Backup wiederherstellen',
    'Before restore, an automatic pre-restore backup will be created.\nThe current DB data and docs folder will be replaced.':
        'Vor der Wiederherstellung wird automatisch ein Vorab-Backup erstellt.\nDie aktuellen DB-Daten und der Dokumentenordner werden ersetzt.',
    'Restore': 'Wiederherstellen',
    'Restoring backup...': 'Backup wird wiederhergestellt...',
    'Backup schema ({schema}) is newer than current app schema ({current}).':
        'Das Backup-Schema ({schema}) ist neuer als das aktuelle App-Schema ({current}).',
    'Restore completed.': 'Wiederherstellung abgeschlossen.',
    'Restore failed.': 'Wiederherstellung fehlgeschlagen.',
    'Metric': 'Metrik',
    'Calculated output based on scenario inputs, settings, and selected assumptions.':
        'Berechnetes Ergebnis auf Basis von Szenarioeingaben, Einstellungen und ausgewahlten Annahmen.',
    'Cap Rate': 'Cap Rate',
    'Net Operating Income divided by Purchase Price. Measures unlevered return in year 1.':
        'Net Operating Income geteilt durch Kaufpreis. Misst die unverschuldete Rendite im ersten Jahr.',
    'IRR': 'IRR',
    'Internal Rate of Return based on projected cashflows including exit.':
        'Interner Zinsfuss auf Basis der prognostizierten Cashflows inklusive Exit.',
    'Cash on Cash': 'Cash on Cash',
    'Annual pre-tax cashflow divided by total cash invested in year 1.':
        'Jahrlicher Cashflow vor Steuern geteilt durch das im ersten Jahr investierte Gesamtkapital.',
    'NOI': 'NOI',
    'Net Operating Income equals operating income minus operating expenses before debt service.':
        'Net Operating Income entspricht den operativen Ertragen minus Betriebskosten vor Schuldendienst.',
    'NOI divided by Annual Debt Service. Measures loan safety.':
        'NOI geteilt durch den jahrlichen Schuldendienst. Misst die Darlehenssicherheit.',
    'Vacancy': 'Leerstand',
    'Expected percentage of gross scheduled income lost due to vacancy.':
        'Erwarteter Anteil des Bruttomietertrags, der durch Leerstand verloren geht.',
    'MAO': 'MAO',
    'Maximum Allowable Offer calculated to meet selected investment target.':
        'Maximal zulassiges Angebot, berechnet zur Erreichung des gewahlten Investitionsziels.',
    'Monthly Cashflow': 'Monatlicher Cashflow',
    'Expected average monthly cashflow before taxes in year 1.':
        'Erwarteter durchschnittlicher monatlicher Cashflow vor Steuern im ersten Jahr.',
    'Annual Cashflow': 'Jahrlicher Cashflow',
    'Total projected year 1 pre-tax cashflow.':
        'Gesamter erwarteter Cashflow vor Steuern im ersten Jahr.',
    'ROI': 'ROI',
    'Total projected profit divided by total cash invested over the hold period.':
        'Gesamtgewinn geteilt durch das uber die Haltedauer investierte Gesamtkapital.',
    'Purchase Price': 'Kaufpreis',
    'Acquisition price used as entry basis for financing and return metrics.':
        'Ankaufspreis als Einstiegsbasis fur Finanzierungs- und Renditekennzahlen.',
    'Rehab Budget': 'Sanierungsbudget',
    'Planned renovation spend included in total cash invested and MAO logic.':
        'Geplante Sanierungsausgaben, die in Gesamtkapitaleinsatz und MAO-Logik einfliessen.',
    'Total Cash Invested': 'Gesamt investiertes Kapital',
    'Total up-front equity including down payment, rehab, and closing costs.':
        'Gesamtes eingesetztes Eigenkapital inklusive Anzahlung, Sanierung und Nebenkosten.',
    'ARV Estimate': 'ARV-Schatzung',
    'Weighted estimate of after-repair value based on selected sales comps.':
        'Gewichtete Schatzung des Werts nach Sanierung auf Basis ausgewahlter Verkaufsvergleiche.',
    'Rent Estimate': 'Mietschatzung',
    'Weighted estimate of monthly rent based on selected rental comps.':
        'Gewichtete Schatzung der Monatsmiete auf Basis ausgewahlter Mietvergleiche.',
    'GSI': 'GSI',
    'Gross Scheduled Income before vacancy and credit losses.':
        'Bruttosollmietertrag vor Leerstand und Ausfallverlusten.',
    'Debt Service': 'Schuldendienst',
    'Total loan payment obligations in the selected period.':
        'Gesamte Darlehenszahlungsverpflichtungen im ausgewahlten Zeitraum.',
    'Rule-based pass/fail checks against selected investment thresholds.':
        'Regelbasierte Bestanden/Nicht-bestanden-Prufungen gegen ausgewahlte Investitionsschwellen.',
    'Sensitivity': 'Sensitivitat',
    'Scenario matrix showing metric changes across purchase and rent deltas.':
        'Szenariomatrix, die Kennzahlenanderungen uber Kauf- und Mietdeltas zeigt.',
    'EPC Rating': 'EPC-Bewertung',
    'Building energy performance class from local certification scale.':
        'Energieeffizienzklasse des Gebaudes gemass lokaler Zertifizierungsskala.',
    'Emissions': 'Emissionen',
    'Estimated annual CO2 emissions intensity in kgCO2 per square meter.':
        'Geschatzte jahrliche CO2-Emissionsintensitat in kgCO2 pro Quadratmeter.',
    'Portfolio KPI': 'Portfolio-KPI',
    'Aggregated KPI across assigned portfolio properties and scenarios.':
        'Aggregierte KPI uber zugewiesene Portfolio-Objekte und Szenarien.',
    'Data Quality': 'Datenqualitat',
    'Validation flags indicating missing, inconsistent, or risky input data.':
        'Validierungskennzeichen fur fehlende, inkonsistente oder riskante Eingabedaten.',
    'property': 'Objekt',
    'scenario': 'Szenario',
    'portfolio': 'Portfolio',
    'document': 'Dokument',
    'task': 'Aufgabe',
    'notification': 'Benachrichtigung',
    'ledger entry': 'Buchung',
    'admin': 'Admin',
    'manager': 'Manager',
    'analyst': 'Analyst',
    'viewer': 'Betrachter',
  };
}

class AppStringsX {
  const AppStringsX(this.context);

  final BuildContext context;

  AppStrings get l10n => AppStrings.of(context);
}

extension AppStringsBuildContextX on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => AppStrings.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<AppStrings> load(Locale locale) async {
    return AppStrings(locale);
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
