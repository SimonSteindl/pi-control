import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

typedef TerminalApiPost = Future<http.Response> Function(
  String path,
  Map<String, String>? headers,
  Object? body,
  Duration? timeout,
);

class TerminalView extends StatefulWidget {
  final TerminalApiPost apiPost;
  final Color accentColor;

  const TerminalView({
    super.key,
    required this.apiPost,
    required this.accentColor,
  });

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  final _commandController = TextEditingController();
  final _commandFocus = FocusNode();
  final _scrollController = ScrollController();
  final List<_TerminalEntry> _entries = [];
  final List<String> _history = [];

  String _cwd = '/home/pi-terminal';
  bool _running = false;
  int _historyIndex = 0;

  @override
  void dispose() {
    _commandController.dispose();
    _commandFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _responseError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      // Bei ungültigem JSON wird der HTTP-Status angezeigt.
    }
    return 'HTTP ${response.statusCode}';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _run([String? suggestedCommand]) async {
    final command = (suggestedCommand ?? _commandController.text).trim();
    if (command.isEmpty || _running) return;

    if (command == 'clear') {
      setState(_entries.clear);
      _commandController.clear();
      _commandFocus.requestFocus();
      return;
    }

    setState(() {
      _running = true;
      _entries.add(_TerminalEntry(command: command, cwd: _cwd));
      _history.add(command);
      _historyIndex = _history.length;
      _commandController.clear();
    });
    _scrollToBottom();

    try {
      final response = await widget.apiPost(
        'terminal/execute',
        const {'Content-Type': 'application/json'},
        jsonEncode({'command': command, 'cwd': _cwd}),
        const Duration(seconds: 20),
      );

      if (response.statusCode != 200) {
        throw Exception(_responseError(response));
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException('Ungültige Antwort');

      final entry = _entries.last;
      entry
        ..output = decoded['output']?.toString() ?? ''
        ..exitCode = (decoded['exit_code'] as num?)?.toInt()
        ..timedOut = decoded['timed_out'] == true
        ..truncated = decoded['truncated'] == true
        ..finished = true;

      final returnedCwd = decoded['cwd']?.toString();
      if (returnedCwd != null && returnedCwd.startsWith('/')) {
        _cwd = returnedCwd;
      }
    } catch (error) {
      final entry = _entries.last;
      entry
        ..output = error.toString().replaceFirst('Exception: ', '')
        ..failed = true
        ..finished = true;
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
        });
        _scrollToBottom();
        _commandFocus.requestFocus();
      }
    }
  }

  void _showPreviousCommand() {
    if (_history.isEmpty) return;
    _historyIndex = (_historyIndex - 1).clamp(0, _history.length - 1).toInt();
    _commandController.text = _history[_historyIndex];
    _commandController.selection = TextSelection.collapsed(
      offset: _commandController.text.length,
    );
  }

  void _showNextCommand() {
    if (_history.isEmpty) return;
    if (_historyIndex >= _history.length - 1) {
      _historyIndex = _history.length;
      _commandController.clear();
      return;
    }
    _historyIndex += 1;
    _commandController.text = _history[_historyIndex];
    _commandController.selection = TextSelection.collapsed(
      offset: _commandController.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const quickCommands = <(String, String)>[
      ('Uptime', 'uptime'),
      ('Speicher', 'df -h'),
      ('Arbeitsspeicher', 'free -h'),
      ('Netzwerk', 'ip -brief address'),
      ('Dateien', 'ls -la'),
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CircleAvatar(
                    backgroundColor: widget.accentColor.withValues(alpha: 0.18),
                    child: Icon(
                      Icons.terminal_rounded,
                      color: widget.accentColor,
                    ),
                  ),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Abgesichertes Pi-Terminal',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'Admin-only · eigener Benutzer · kein Root oder sudo',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  OutlinedButton.icon(
                    onPressed: _entries.isEmpty
                        ? null
                        : () => setState(_entries.clear),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Leeren'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF050912),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: SelectionArea(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Pi Control Web Terminal\n'
                      'Befehle laufen maximal 15 Sekunden. Interaktive Programme '
                      'wie nano oder htop werden noch nicht unterstützt.\n',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: colors.primary,
                        height: 1.45,
                      ),
                    ),
                    for (final entry in _entries)
                      _TerminalEntryView(entry: entry),
                    if (_running)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in quickCommands) ...[
                  ActionChip(
                    label: Text(item.$1),
                    onPressed: _running ? null : () => _run(item.$2),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commandController,
                  focusNode: _commandFocus,
                  enabled: !_running,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.chevron_right_rounded),
                    labelText: _cwd,
                    hintText: 'Befehl eingeben, z. B. ls -la',
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _run(),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  IconButton.filledTonal(
                    onPressed: _running ? null : _showPreviousCommand,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    tooltip: 'Vorheriger Befehl',
                  ),
                  IconButton.filledTonal(
                    onPressed: _running ? null : _showNextCommand,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    tooltip: 'Nächster Befehl',
                  ),
                ],
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('Ausführen'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TerminalEntryView extends StatelessWidget {
  final _TerminalEntry entry;

  const _TerminalEntryView({required this.entry});

  @override
  Widget build(BuildContext context) {
    final statusColor = entry.failed || (entry.exitCode ?? 0) != 0
        ? Colors.redAccent
        : Colors.greenAccent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: const TextStyle(fontFamily: 'monospace', height: 1.45),
              children: [
                const TextSpan(
                  text: 'pi-terminal',
                  style: TextStyle(color: Colors.greenAccent),
                ),
                const TextSpan(text: ':'),
                TextSpan(
                  text: entry.cwd,
                  style: const TextStyle(color: Colors.lightBlueAccent),
                ),
                const TextSpan(text: r'$ '),
                TextSpan(
                  text: entry.command,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          if (entry.output.isNotEmpty)
            Text(
              entry.output,
              style: TextStyle(
                fontFamily: 'monospace',
                color: entry.failed ? Colors.redAccent : Colors.white70,
                height: 1.45,
              ),
            ),
          if (entry.finished)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  if (entry.timedOut) 'Zeitlimit erreicht',
                  if (entry.truncated) 'Ausgabe gekürzt',
                  if (!entry.failed && entry.exitCode != null)
                    'Exit ${entry.exitCode}',
                ].join(' · '),
                style: TextStyle(
                  color: statusColor.withValues(alpha: 0.8),
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TerminalEntry {
  final String command;
  final String cwd;
  String output = '';
  int? exitCode;
  bool timedOut = false;
  bool truncated = false;
  bool failed = false;
  bool finished = false;

  _TerminalEntry({required this.command, required this.cwd});
}
