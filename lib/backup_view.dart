import 'dart:convert';

import 'package:flutter/material.dart';

import 'auth.dart';

Future<void> showBackupManager(BuildContext context, PiApiClient client) {
  return showDialog<void>(
    context: context,
    builder: (context) => _BackupDialog(client: client),
  );
}

class _BackupDialog extends StatefulWidget {
  final PiApiClient client;

  const _BackupDialog({required this.client});

  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  List<_BackupItem> _items = [];
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.client.get(
        'backups',
        timeout: const Duration(seconds: 20),
      );
      if (response.statusCode != 200) {
        throw widget.client.responseException(response);
      }
      final decoded = jsonDecode(response.body);
      final items = <_BackupItem>[];
      if (decoded is Map && decoded['backups'] is List) {
        for (final item in decoded['backups'] as List) {
          if (item is Map) items.add(_BackupItem.fromJson(item));
        }
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final response = await widget.client.post(
        'backups/create',
        timeout: const Duration(minutes: 2),
      );
      if (response.statusCode != 200) {
        throw widget.client.responseException(response);
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _restore(_BackupItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restore_rounded),
        title: const Text('Backup wiederherstellen?'),
        content: Text(
          '${item.name} wird eingespielt. Pi Control startet danach neu und ist kurz nicht erreichbar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Wiederherstellen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final response = await widget.client.post(
      'backups/restore',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'name': item.name}),
      timeout: const Duration(seconds: 30),
    );
    if (response.statusCode != 200) {
      throw widget.client.responseException(response);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Wiederherstellung gestartet. Pi Control startet neu …'),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year}, '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 700),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.backup_rounded),
              title: const Text(
                'Automatische Backups',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Täglich um 03:15 Uhr · 14 Tage Aufbewahrung',
              ),
              trailing: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _creating ? null : _create,
                    icon: _creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded),
                    label: Text(_creating ? 'Wird erstellt …' : 'Backup jetzt'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _loading ? null : _load,
                    tooltip: 'Aktualisieren',
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    )
                  : _items.isEmpty
                  ? const Center(child: Text('Noch keine Backups vorhanden.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(item.name),
                          subtitle: Text(
                            '${_formatDate(item.createdAt)} · ${_formatSize(item.size)}',
                          ),
                          trailing: IconButton(
                            onPressed: () => _restore(item),
                            tooltip: 'Wiederherstellen',
                            icon: const Icon(Icons.restore_rounded),
                          ),
                        );
                      },
                    ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Text(
                'Gesichert werden Benutzer, Rechte, Einstellungen und Verlauf. '
                'Persönliche NAS-Dateien bleiben unverändert.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupItem {
  final String name;
  final int size;
  final DateTime createdAt;

  const _BackupItem({
    required this.name,
    required this.size,
    required this.createdAt,
  });

  factory _BackupItem.fromJson(Map<dynamic, dynamic> json) => _BackupItem(
    name: json['name']?.toString() ?? 'Backup',
    size: (json['size'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      ((json['created_at'] as num?)?.toInt() ?? 0) * 1000,
    ),
  );
}
