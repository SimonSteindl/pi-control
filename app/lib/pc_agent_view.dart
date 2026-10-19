import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

typedef PcAgentGet = Future<http.Response> Function(
  String path,
  Map<String, String>? headers,
  Duration? timeout,
);

typedef PcAgentPost = Future<http.Response> Function(
  String path,
  Map<String, String>? headers,
  Object? body,
  Duration? timeout,
);

class PcAgentView extends StatefulWidget {
  final Color accentColor;
  final bool english;
  final PcAgentGet apiGet;
  final PcAgentPost apiPost;

  const PcAgentView({
    super.key,
    required this.accentColor,
    required this.english,
    required this.apiGet,
    required this.apiPost,
  });

  @override
  State<PcAgentView> createState() => _PcAgentViewState();
}

class _PcAgentViewState extends State<PcAgentView> {
  bool loading = false;
  Map<String, dynamic>? status;
  String? error;
  String? result;
  final commandController = TextEditingController();
  String selectedApp = 'browser';

  bool get en => widget.english;

  @override
  void initState() {
    super.initState();
    loadStatus();
  }

  @override
  void dispose() {
    commandController.dispose();
    super.dispose();
  }

  Future<void> loadStatus() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final response = await widget.apiGet(
        'pc-agent/status',
        null,
        const Duration(seconds: 15),
      );
      final decoded = jsonDecode(response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          decoded is Map
              ? decoded['error']?.toString() ?? 'HTTP ${response.statusCode}'
              : 'HTTP ${response.statusCode}',
        );
      }

      if (decoded is! Map<String, dynamic>) {
        throw Exception(
          en ? 'Invalid server response' : 'Ungültige Serverantwort',
        );
      }

      if (mounted) setState(() => status = decoded);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> performAction(
    Map<String, dynamic> payload, {
    required String title,
    required String description,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(description)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(en ? 'Cancel' : 'Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(en ? 'Confirm' : 'Bestätigen'),
          ),
        ],
      ),
    );

    if (approved != true || !mounted) return;

    setState(() {
      loading = true;
      error = null;
      result = null;
    });

    try {
      final response = await widget.apiPost(
        'pc-agent/action',
        {'Content-Type': 'application/json'},
        jsonEncode({...payload, 'approved': true}),
        timeout,
      );

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          decoded is Map
              ? decoded['error']?.toString() ?? 'HTTP ${response.statusCode}'
              : 'HTTP ${response.statusCode}: $decoded',
        );
      }

      if (mounted) {
        setState(() {
          result = const JsonEncoder.withIndent('  ').convert(decoded);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: widget.accentColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget statusOverview() {
    final data = status;
    if (data == null) {
      return Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              en ? 'Waiting for PC-Agent status…' : 'Warte auf den PC-Agent-Status …',
            ),
          ),
        ],
      );
    }

    final online = data['ok'] == true;
    final actions = (data['allowed_actions'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        <String>[];
    final clients = (data['allowed_clients'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        <String>[];

    Widget infoTile(IconData icon, String label, String value) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: widget.accentColor, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 3),
                  SelectableText(
                    value.isEmpty ? '—' : value,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (online ? Colors.green : Colors.red).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (online ? Colors.green : Colors.red).withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Icon(
                online ? Icons.check_circle_rounded : Icons.error_rounded,
                color: online ? Colors.green : Colors.red,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      online
                          ? (en ? 'Agent connected' : 'Agent verbunden')
                          : (en ? 'Agent needs attention' : 'Agent benötigt Aufmerksamkeit'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      (data['agent'] ?? 'PC-Agent').toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (data['git_available'] == true)
                Tooltip(
                  message: en ? 'Git available' : 'Git verfügbar',
                  child: Icon(Icons.account_tree_rounded, color: widget.accentColor),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 520 ? 2 : 1;
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: columns == 2 ? 3.4 : 4.2,
              children: [
                infoTile(Icons.computer_rounded, en ? 'Operating system' : 'Betriebssystem',
                    (data['os'] ?? 'Unknown').toString()),
                infoTile(Icons.folder_open_rounded, en ? 'Workspace' : 'Arbeitsordner',
                    (data['workspace'] ?? '—').toString()),
                infoTile(Icons.home_work_outlined, en ? 'Access root' : 'Zugriffsbereich',
                    (data['access_root'] ?? '—').toString()),
                infoTile(Icons.lan_outlined, en ? 'Agent address' : 'Agent-Adresse',
                    (data['bind_host'] ?? '—').toString()),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: Icon(Icons.shield_outlined, color: widget.accentColor),
          title: Text(en ? 'Permissions & connection' : 'Berechtigungen & Verbindung'),
          subtitle: Text(
            en
                ? '${actions.length} allowed actions · ${clients.length} allowed clients'
                : '${actions.length} erlaubte Aktionen · ${clients.length} erlaubte Clients',
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                en ? 'Allowed actions' : 'Erlaubte Aktionen',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: actions
                  .map((action) => Chip(
                        avatar: const Icon(Icons.check, size: 16),
                        label: Text(action),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                en ? 'Allowed clients' : 'Erlaubte Clients',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 6),
            if (clients.isEmpty)
              Text(en ? 'No client listed' : 'Keine Clients eingetragen')
            else
              ...clients.map((client) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.devices_other),
                    title: SelectableText(client),
                  )),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(en ? 'Raw status data' : 'Rohe Statusdaten'),
                content: SingleChildScrollView(
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(data),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(en ? 'Close' : 'Schließen'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.data_object),
            label: Text(en ? 'View raw data' : 'Rohdaten anzeigen'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.computer_rounded, size: 30, color: widget.accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                en ? 'PC Control' : 'PC-Steuerung',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: en ? 'Refresh status' : 'Status aktualisieren',
              onPressed: loading ? null : loadStatus,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          en
              ? 'Control your PC through the authenticated Pi-Control server.'
              : 'Steuere deinen PC über den angemeldeten Pi-Control-Server.',
        ),
        const SizedBox(height: 16),
        if (loading) const LinearProgressIndicator(),
        if (error != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(child: SelectableText(error!)),
                ],
              ),
            ),
          ),
        ],
        sectionCard(
          title: en ? 'PC-Agent status' : 'PC-Agent-Status',
          icon: Icons.monitor_heart_outlined,
          child: statusOverview(),
        ),
        sectionCard(
          title: en ? 'Open an application' : 'Programm öffnen',
          icon: Icons.launch_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedApp,
                decoration: InputDecoration(
                  labelText: en ? 'Application' : 'Programm',
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'editor',
                    child: Text(en ? 'Editor' : 'Texteditor'),
                  ),
                  const DropdownMenuItem(
                    value: 'browser',
                    child: Text('Browser'),
                  ),
                  DropdownMenuItem(
                    value: 'file-manager',
                    child: Text(en ? 'File manager' : 'Dateimanager'),
                  ),
                ],
                onChanged: loading
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => selectedApp = value);
                        }
                      },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: loading
                    ? null
                    : () => performAction(
                        {'action': 'open', 'app': selectedApp},
                        title: en ? 'Open application?' : 'Programm öffnen?',
                        description: en
                            ? 'The PC-Agent will try to open: $selectedApp'
                            : 'Der PC-Agent versucht dieses Programm zu öffnen: $selectedApp',
                      ),
                icon: const Icon(Icons.open_in_new),
                label: Text(en ? 'Open application' : 'Programm öffnen'),
              ),
            ],
          ),
        ),
        sectionCard(
          title: en ? 'Run a command' : 'Befehl ausführen',
          icon: Icons.terminal_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                en
                    ? 'Commands run on your PC with the permissions of the PC-Agent. Only enter commands you understand.'
                    : 'Befehle werden auf deinem PC mit den Rechten des PC-Agents ausgeführt. Gib nur Befehle ein, die du verstehst.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commandController,
                enabled: !loading,
                decoration: InputDecoration(
                  labelText: en
                      ? 'Command and arguments'
                      : 'Befehl und Argumente',
                  hintText: 'whoami',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: loading
                    ? null
                    : () {
                        final command = commandController.text.trim();
                        if (command.isEmpty) {
                          setState(
                            () => error = en
                                ? 'Enter a command first.'
                                : 'Gib zuerst einen Befehl ein.',
                          );
                          return;
                        }

                        final parts = command.split(RegExp(r'\s+'));
                        performAction(
                          {
                            'action': 'run_command',
                            'command': parts,
                            'timeout': 30,
                          },
                          title: en ? 'Confirm command' : 'Befehl bestätigen',
                          description:
                              '${en ? 'This argument list will be sent to your PC:' : 'Diese Argumentliste wird an deinen PC gesendet:'}\n\n${const JsonEncoder.withIndent('  ').convert(parts)}\n\n${en ? 'Continue?' : 'Fortfahren?'}',
                          timeout: const Duration(seconds: 140),
                        );
                      },
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(en ? 'Review and run' : 'Prüfen und ausführen'),
              ),
            ],
          ),
        ),
        if (result != null)
          sectionCard(
            title: en ? 'Last result' : 'Letztes Ergebnis',
            icon: Icons.receipt_long_outlined,
            child: SelectableText(result!),
          ),
      ],
    );
  }
}
