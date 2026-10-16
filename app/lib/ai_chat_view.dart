import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';

class AiChatView extends StatefulWidget {
  final PiApiClient client;
  final Color accentColor;
  final bool english;

  const AiChatView({
    super.key,
    required this.client,
    required this.accentColor,
    required this.english,
  });

  @override
  State<AiChatView> createState() => _AiChatViewState();
}

class _AiChatViewState extends State<AiChatView> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Map<String, String>> _messages = [];
  final Map<int, Map<String, dynamic>> _actionRequests = {};
  final Map<int, String> _actionResults = {};
  final Set<int> _actionBusy = {};
  List<Map<String, dynamic>> _memories = [];
  String _model = 'qwen3:1.7b';
  bool _busy = false;
  bool _loadingMemories = false;
  String? _error;
  static const String _chatStorageKey = 'pi_control_ai_chat_messages';

  bool get _en => widget.english;

  @override
  void initState() {
    super.initState();
    _restoreChat();
    _loadMemories();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _restoreChat() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_chatStorageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List || !mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(decoded.whereType<Map>().map((item) => {
            'role': '${item['role'] ?? 'assistant'}',
            'content': '${item['content'] ?? ''}',
          }));
      });
      _scrollToBottom();
    } catch (_) {
      // Ignore malformed saved chat and let the user start a fresh conversation.
    }
  }

  Future<void> _saveChat() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_chatStorageKey, jsonEncode(_messages));
    } catch (_) {
      // Chat still works if local persistence is unavailable.
    }
  }

  Future<void> _loadMemories() async {
    if (_loadingMemories) return;
    setState(() => _loadingMemories = true);
    try {
      final response = await widget.client.get(
        'ai/memory',
        timeout: const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        throw widget.client.responseException(response);
      }
      final data = widget.client.decodeObject(response);
      final values = data['memories'];
      if (mounted) {
        setState(() {
          _memories = values is List
              ? values.whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList()
              : <Map<String, dynamic>>[];
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loadingMemories = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;

    _input.clear();
    final history = <Map<String, String>>[
      ..._messages,
      {'role': 'user', 'content': text},
    ];
    final boundedHistory = history.length > 12
        ? history.sublist(history.length - 12)
        : history;
    setState(() {
      _error = null;
      _busy = true;
      _messages.add({'role': 'user', 'content': text});
    });
    await _saveChat();
    _scrollToBottom();

    try {
      final response = await widget.client.post(
        'ai/chat',
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'model': _model, 'messages': boundedHistory}),
        timeout: const Duration(seconds: 160),
      );
      if (response.statusCode != 200) {
        throw widget.client.responseException(response);
      }
      final data = widget.client.decodeObject(response);
      final message = data['message'];
      final content = message is Map ? message['content']?.toString() : null;
      if (content == null || content.trim().isEmpty) {
        throw ApiException(_en ? 'The AI returned an empty answer.' : 'Die KI hat keine Antwort geliefert.');
      }
      if (!mounted) return;
      setState(() {
        final index = _messages.length;
        _messages.add({'role': 'assistant', 'content': content.trim()});
        final action = data['action_request'];
        if (action is Map) {
          _actionRequests[index] = Map<String, dynamic>.from(action);
        }
      });
      await _saveChat();
      if (RegExp(r'^\s*(merk(?:e)?\s+dir|speicher|remember)', caseSensitive: false).hasMatch(text)) {
        await _loadMemories();
      }
      _scrollToBottom();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _actionTitle(Map<String, dynamic> action) {
    final type = '${action['action'] ?? ''}';
    if (_en) {
      switch (type) {
        case 'write_file': return 'Write or replace a file';
        case 'delete_file': return 'Move file/folder to agent trash';
        case 'run_command': return 'Run command on your PC';
        case 'open': return 'Open an application';
      }
      return 'PC action';
    }
    switch (type) {
      case 'write_file': return 'Datei schreiben/überschreiben';
      case 'delete_file': return 'Datei/Ordner in den Agent-Papierkorb verschieben';
      case 'run_command': return 'Befehl auf deinem PC ausführen';
      case 'open': return 'Programm öffnen';
    }
    return 'PC-Aktion';
  }

  String _actionDetails(Map<String, dynamic> action) {
    final type = '${action['action'] ?? ''}';
    if (type == 'run_command') {
      final command = action['command'];
      return command is List ? jsonEncode(command) : '$command';
    }
    if (type == 'write_file') {
      final content = '${action['content'] ?? ''}';
      return 'Pfad: ${action['path'] ?? ''}\n\nVollständiger Inhalt:\n$content';
    }
    if (type == 'delete_file') return 'Pfad: ${action['path'] ?? ''}\n\nDer Eintrag wird in den Agent-Papierkorb verschoben, nicht sofort endgültig gelöscht.';
    if (type == 'open') return 'Programm: ${action['app'] ?? ''}';
    return '${action['path'] ?? ''}';
  }

  Future<void> _rejectAction(int index) async {
    if (!mounted) return;
    setState(() {
      _actionRequests.remove(index);
      _actionResults[index] = _en ? 'Rejected. Nothing was executed.' : 'Abgelehnt. Es wurde nichts ausgeführt.';
    });
  }

  Future<void> _approveAction(int index) async {
    final action = _actionRequests[index];
    if (action == null || _actionBusy.contains(index)) return;
    setState(() => _actionBusy.add(index));
    try {
      final payload = Map<String, dynamic>.from(action)..['approved'] = true;
      final response = await widget.client.post(
        'pc-agent/action',
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
        timeout: const Duration(seconds: 140),
      );
      final data = widget.client.decodeObject(response);
      if (response.statusCode != 200 || data['ok'] != true) {
        throw ApiException('${data['error'] ?? (_en ? 'PC action failed.' : 'PC-Aktion fehlgeschlagen.')}');
      }
      final result = (data['output']?.toString().trim().isNotEmpty ?? false)
          ? data['output'].toString()
          : JsonEncoder.withIndent('  ').convert(data);
      if (!mounted) return;
      setState(() {
        _actionRequests.remove(index);
        _actionResults[index] = result.length > 5000 ? '${result.substring(0, 5000)}…' : result;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _actionRequests.remove(index);
          _actionResults[index] = '${_en ? 'Action failed' : 'Aktion fehlgeschlagen'}: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _actionBusy.remove(index));
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _deleteMemory(Map<String, dynamic> memory) async {
    final id = int.tryParse('${memory['id'] ?? ''}');
    if (id == null) return;
    final response = await widget.client.delete('ai/memory/$id');
    if (response.statusCode != 200) {
      throw widget.client.responseException(response);
    }
    await _loadMemories();
  }

  Future<void> _showMemories() async {
    await _loadMemories();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    const Icon(Icons.psychology_alt_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _en ? 'Saved memories' : 'Gespeicherte Erinnerungen',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _memories.isEmpty
                    ? Center(child: Text(_en ? 'No saved memories yet.' : 'Noch keine Erinnerungen gespeichert.'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _memories.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _memories[index];
                          return ListTile(
                            leading: const Icon(Icons.bookmark_outline_rounded),
                            title: Text('${item['memory'] ?? item['content'] ?? item['text'] ?? ''}'),
                            trailing: IconButton(
                              tooltip: _en ? 'Delete memory' : 'Erinnerung löschen',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () async {
                                try {
                                  await _deleteMemory(item);
                                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                                  await _showMemories();
                                } catch (error) {
                                  if (mounted) setState(() => _error = error.toString());
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextSpan _formatMessage(String content, TextStyle? baseStyle) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
    var cursor = 0;
    for (final match in pattern.allMatches(content)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: content.substring(cursor, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ));
      cursor = match.end;
    }
    if (cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor)));
    }
    return TextSpan(style: baseStyle, children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.auto_awesome_rounded, color: widget.accentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pi-Control AI', style: theme.textTheme.titleLarge),
                        Text(_en ? 'Private assistant' : 'Dein privater Assistent', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _en ? 'Saved memories' : 'Erinnerungen',
                    onPressed: _showMemories,
                    icon: Badge(
                      label: Text('${_memories.length}'),
                      isLabelVisible: _memories.isNotEmpty,
                      child: const Icon(Icons.psychology_alt_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(_en ? 'Model' : 'Modell'),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _model,
                onChanged: _busy ? null : (value) {
                  if (value != null) setState(() => _model = value);
                },
                items: const [
                  DropdownMenuItem(value: 'qwen3:1.7b', child: Text('Qwen3 1.7B')),
                  DropdownMenuItem(value: 'qwen3:4b', child: Text('Qwen3 4B')),
                ],
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _busy || _messages.isEmpty ? null : () async {
                  setState(() {
                    _messages.clear();
                    _actionRequests.clear();
                    _actionResults.clear();
                    _actionBusy.clear();
                    _error = null;
                  });
                  await _saveChat();
                },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(_en ? 'Clear' : 'Leeren'),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                ),
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forum_outlined, size: 56, color: widget.accentColor),
                          const SizedBox(height: 12),
                          Text(_en ? 'What can I help you with?' : 'Wobei kann ich dir helfen?', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          Text(
                            _en
                                ? 'Ask a question or say “Remember …” to save a memory.'
                                : 'Stell eine Frage oder schreibe „Merk dir …“, um eine Erinnerung zu speichern.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length + (_busy ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_busy && index == _messages.length) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        );
                      }
                      final message = _messages[index];
                      final isUser = message['role'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Card(
                            color: isUser
                                ? widget.accentColor.withValues(alpha: 0.16)
                                : theme.colorScheme.surfaceContainerHighest,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText.rich(_formatMessage(message['content'] ?? '', theme.textTheme.bodyMedium)),
                                  if (_actionRequests.containsKey(index)) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.55)),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
                                              const SizedBox(width: 8),
                                              Expanded(child: Text(_actionTitle(_actionRequests[index]!), style: theme.textTheme.titleSmall)),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          SelectableText(_actionDetails(_actionRequests[index]!)),
                                          const SizedBox(height: 10),
                                          Text(
                                            _en
                                                ? 'This action will not run unless you approve it.'
                                                : 'Diese Aktion wird erst nach deiner Bestätigung ausgeführt.',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              TextButton(
                                                onPressed: _actionBusy.contains(index) ? null : () => _rejectAction(index),
                                                child: Text(_en ? 'Reject' : 'Ablehnen'),
                                              ),
                                              const SizedBox(width: 8),
                                              FilledButton.icon(
                                                onPressed: _actionBusy.contains(index) ? null : () => _approveAction(index),
                                                icon: _actionBusy.contains(index)
                                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                                    : const Icon(Icons.check_rounded),
                                                label: Text(_en ? 'Approve and run' : 'Bestätigen & ausführen'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (_actionResults.containsKey(index)) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surface,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: SelectableText(_actionResults[index]!),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: _en ? 'Message Pi-Control AI…' : 'Nachricht an Pi-Control AI…',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send_rounded),
                tooltip: _en ? 'Send' : 'Senden',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
