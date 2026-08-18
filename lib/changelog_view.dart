import 'package:flutter/material.dart';

Future<void> showPiControlChangelog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _ChangelogDialog(),
  );
}

class _ChangelogDialog extends StatelessWidget {
  const _ChangelogDialog();

  static const entries = [
    _ChangelogEntry(
      version: '1.5.1',
      date: '18. August 2026',
      title: 'Schöner Wartungsmodus',
      highlights: [
        'Während Updates erscheint eine moderne Wartungsansicht statt einer Fehlermeldung.',
        'Pi Control prüft automatisch, wann das Update fertig ist, und kehrt selbstständig zurück.',
      ],
    ),
    _ChangelogEntry(
      version: '1.5.0',
      date: '18. August 2026',
      title: 'Backups, Updates und schnelleres Arbeiten',
      highlights: [
        'Tägliche automatische Konfigurationsbackups mit 14 Tagen Aufbewahrung.',
        'Backup-Verwaltung für Administratoren mit manuellem Sofort-Backup.',
        'Aktive Freigabelinks können angezeigt und vorzeitig deaktiviert werden.',
        'Mehrfachauswahl für gemeinsames Verschieben und Löschen.',
        'Dateien lassen sich per Ziehen auf einen Ordner verschieben.',
        'Native Apps prüfen selbstständig, ob eine neuere Version verfügbar ist.',
      ],
    ),
    _ChangelogEntry(
      version: '1.4.0',
      date: '18. August 2026',
      title: 'Der große Dateimanager-Ausbau',
      highlights: [
        'Schnelle Suche nach Dateien und Ordnern im erlaubten Speicherbereich.',
        'Papierkorb mit Wiederherstellen und bewusstem endgültigem Löschen.',
        'Freigabelinks für Dateien, die automatisch nach 24 Stunden ablaufen.',
        'Bildvorschau direkt in Pi Control und Videovorschau im Browser.',
        'Update-Hinweis auf der Startseite mit direktem Link zum Changelog.',
      ],
    ),
    _ChangelogEntry(
      version: '1.3.0',
      date: '18. August 2026',
      title: 'Dateien bequem organisieren',
      highlights: [
        'Dateien und Ordner können jetzt in andere Ordner verschoben werden.',
        'Neuer übersichtlicher Zielordner-Dialog im Dateimanager.',
        'Der Dateimanager lädt bei großen NAS-Laufwerken deutlich schneller.',
        'Zusätzliche Sicherheitsprüfung verhindert das Verschieben eines Ordners in sich selbst.',
      ],
    ),
    _ChangelogEntry(
      version: '1.2.0',
      date: '18. August 2026',
      title: 'Benutzer, Speicher und mobile Apps',
      highlights: [
        'Eigene NAS-Ordner und Speicherlimits in GB pro Benutzer.',
        'Modernes Admin-Panel zum Erstellen und Bearbeiten von Benutzern und Rechten.',
        'Sicher angemeldet bleiben: Cookie im Web und geschützter Gerätespeicher in den Apps.',
        'Neues Pi-Control-App-Icon für Android, iOS und Web.',
        'Android-APK und iOS-Version über Codemagic vorbereitet.',
      ],
    ),
    _ChangelogEntry(
      version: '1.1.0',
      date: '18. August 2026',
      title: 'Pi Control wird zum Webportal',
      highlights: [
        'Neue Startseite mit geschütztem Login.',
        'Dateimanager und abgesichertes Web-Terminal ergänzt.',
        'Rollen und einzeln einstellbare Benutzerrechte eingeführt.',
        'Öffentlicher HTTPS-Zugriff über den festen ngrok-Tunnel.',
      ],
    ),
    _ChangelogEntry(
      version: '1.0.0',
      date: 'August 2026',
      title: 'Erste Version',
      highlights: [
        'Systemübersicht für Raspberry Pi, Speicher, Temperatur und Dienste.',
        'Benchmark-Verlauf und Verwaltungsaktionen.',
        'Responsive Oberfläche für Computer, Tablet und Smartphone.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 22, 12, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer,
                    colorScheme.tertiaryContainer,
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Was ist neu?',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text('Pi Control – Changelog'),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Schließen',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: entries.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 14),
                itemBuilder: (context, index) =>
                    _ChangelogCard(entry: entries[index], newest: index == 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangelogCard extends StatelessWidget {
  final _ChangelogEntry entry;
  final bool newest;

  const _ChangelogCard({required this.entry, required this.newest});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  avatar: const Icon(Icons.sell_outlined, size: 17),
                  label: Text('Version ${entry.version}'),
                ),
                if (newest)
                  Chip(
                    backgroundColor: colorScheme.primaryContainer,
                    label: const Text('Aktuell'),
                  ),
                Text(
                  entry.date,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              entry.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            for (final highlight in entry.highlights)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 9),
                    Expanded(child: Text(highlight)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChangelogEntry {
  final String version;
  final String date;
  final String title;
  final List<String> highlights;

  const _ChangelogEntry({
    required this.version,
    required this.date,
    required this.title,
    required this.highlights,
  });
}
