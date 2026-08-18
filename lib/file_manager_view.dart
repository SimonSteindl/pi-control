import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

typedef FileApiGet = Future<http.Response> Function(
  String path,
  Map<String, String>? headers,
);

typedef FileApiPost = Future<http.Response> Function(
  String path,
  Map<String, String>? headers,
  Object? body,
  Duration? timeout,
);

class FileManagerView extends StatefulWidget {
  final FileApiGet apiGet;
  final FileApiPost apiPost;
  final String Function() apiBase;
  final String authToken;
  final bool canUpload;
  final bool canManage;
  final Color accentColor;

  const FileManagerView({
    super.key,
    required this.apiGet,
    required this.apiPost,
    required this.apiBase,
    required this.authToken,
    required this.canUpload,
    required this.canManage,
    required this.accentColor,
  });

  @override
  State<FileManagerView> createState() => _FileManagerViewState();
}

class _FileManagerViewState extends State<FileManagerView> {
  String _path = '';
  String? _parentPath;
  String _rootName = 'NAS / USB-Stick';
  String _storagePath = '';
  int _storageUsedBytes = 0;
  int? _storageQuotaBytes;
  List<PiFileEntry> _entries = [];
  bool _loading = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _responseError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      // Bei einer ungültigen Antwort wird der HTTP-Status angezeigt.
    }

    return 'HTTP ${response.statusCode}';
  }

  Future<void> _load({String? path}) async {
    final targetPath = path ?? _path;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final encodedPath = Uri.encodeQueryComponent(targetPath);
      final response = await widget.apiGet('files?path=$encodedPath', null);

      if (response.statusCode != 200) {
        throw Exception(_responseError(response));
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['entries'] is! List) {
        throw Exception('Ungültige Antwort vom Raspberry Pi.');
      }

      final entries = <PiFileEntry>[];
      for (final item in decoded['entries'] as List) {
        if (item is Map) {
          entries.add(PiFileEntry.fromJson(item));
        }
      }

      if (!mounted) return;

      setState(() {
        _path = decoded['path']?.toString() ?? '';
        _parentPath = decoded['parent']?.toString();
        _rootName = decoded['root_name']?.toString() ?? 'NAS / USB-Stick';
        _storagePath = decoded['storage_path']?.toString() ?? '';
        _storageUsedBytes = decoded['storage_used_bytes'] is num
            ? (decoded['storage_used_bytes'] as num).toInt()
            : 0;
        _storageQuotaBytes = decoded['storage_quota_bytes'] is num
            ? (decoded['storage_quota_bytes'] as num).toInt()
            : null;
        _entries = entries;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<http.Response> _protectedPost(
    String path,
    Map<String, dynamic> payload, {
    Duration? timeout,
  }) {
    return widget.apiPost(
      path,
      {'Content-Type': 'application/json'},
      jsonEncode(payload),
      timeout,
    );
  }

  Future<void> _createFolder() async {
    final name = await _askForText(
      title: 'Neuer Ordner',
      label: 'Ordnername',
      confirmText: 'Erstellen',
    );

    if (name == null || name.trim().isEmpty) return;

    await _runFileAction(
      () =>
          _protectedPost('files/folder', {'path': _path, 'name': name.trim()}),
      success: 'Ordner wurde erstellt.',
    );
  }

  Future<void> _rename(PiFileEntry entry) async {
    final name = await _askForText(
      title: 'Umbenennen',
      label: 'Neuer Name',
      initialValue: entry.name,
      confirmText: 'Speichern',
    );

    if (name == null || name.trim().isEmpty || name.trim() == entry.name) {
      return;
    }

    await _runFileAction(
      () => _protectedPost('files/rename', {
        'path': entry.path,
        'name': name.trim(),
      }),
      success: '„${entry.name}“ wurde umbenannt.',
    );
  }

  Future<void> _delete(PiFileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
        title: Text('${entry.isDirectory ? 'Ordner' : 'Datei'} löschen?'),
        content: Text(
          '„${entry.name}“ wird dauerhaft gelöscht. Nicht leere Ordner werden aus Sicherheitsgründen nicht gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _runFileAction(
      () => _protectedPost('files/delete', {'path': entry.path}),
      success: '„${entry.name}“ wurde gelöscht.',
    );
  }

  Future<void> _runFileAction(
    Future<http.Response> Function() action, {
    required String success,
  }) async {
    try {
      final response = await action();
      if (response.statusCode != 200) {
        throw Exception(_responseError(response));
      }

      _showMessage(success);
      await _load();
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _upload() async {
    if (_uploading) return;

    final file = await FilePicker.pickFile();

    if (file == null) return;

    setState(() {
      _uploading = true;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.apiBase()}/files/upload'),
      );

      request.headers['Authorization'] = 'Bearer ${widget.authToken}';
      request.fields['path'] = _path;

      request.files.add(
        http.MultipartFile(
          'file',
          file.readAsByteStream(),
          await file.length(),
          filename: file.name,
        ),
      );

      final streamed = await request.send().timeout(const Duration(minutes: 5));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        throw Exception(_responseError(response));
      }

      _showMessage('„${file.name}“ wurde hochgeladen.');
      await _load();
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
      }
    }
  }

  Future<void> _download(PiFileEntry entry) async {
    try {
      final response = await _protectedPost('files/download-token', {
        'path': entry.path,
      });

      if (response.statusCode != 200) {
        throw Exception(_responseError(response));
      }

      final decoded = jsonDecode(response.body);
      final token = decoded is Map ? decoded['token']?.toString() : null;

      if (token == null || token.isEmpty) {
        throw Exception('Download-Link konnte nicht erstellt werden.');
      }

      final url = Uri.parse(
        '${widget.apiBase()}/files/download/${Uri.encodeComponent(token)}',
      );
      final launched = await launchUrl(url, mode: LaunchMode.platformDefault);

      if (!launched) {
        throw Exception('Download konnte nicht geöffnet werden.');
      }
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<String?> _askForText({
    required String title,
    required String label,
    required String confirmText,
    String initialValue = '',
    bool obscure = false,
    TextInputType? keyboardType,
    int? maxLength,
  }) async {
    final controller = TextEditingController(text: initialValue);

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          keyboardType: keyboardType,
          maxLength: maxLength,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(confirmText),
          ),
        ],
      ),
    );

    controller.dispose();
    return value;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  IconData _iconFor(PiFileEntry entry) {
    if (entry.isDirectory) return Icons.folder_rounded;

    final extension = entry.name.contains('.')
        ? entry.name.split('.').last.toLowerCase()
        : '';

    if ({'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'}.contains(extension)) {
      return Icons.image_outlined;
    }
    if ({'mp4', 'mov', 'mkv', 'avi', 'webm'}.contains(extension)) {
      return Icons.movie_outlined;
    }
    if ({'mp3', 'wav', 'flac', 'aac', 'm4a'}.contains(extension)) {
      return Icons.audio_file_outlined;
    }
    if ({'zip', 'rar', '7z', 'tar', 'gz'}.contains(extension)) {
      return Icons.folder_zip_outlined;
    }
    if ({'pdf'}.contains(extension)) return Icons.picture_as_pdf_outlined;
    if ({'txt', 'md', 'log'}.contains(extension)) {
      return Icons.description_outlined;
    }

    return Icons.insert_drive_file_outlined;
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return 'Ordner';
    if (bytes < 1024) return '$bytes B';

    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';

    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';

    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year}, ${two(date.hour)}:${two(date.minute)}';
  }

  Widget _buildBreadcrumbs() {
    final segments = _path.isEmpty ? <String>[] : _path.split('/');
    final items = <Widget>[];

    items.add(
      ActionChip(
        avatar: const Icon(Icons.usb_rounded, size: 18),
        label: Text(_storagePath.isEmpty ? 'NAS' : _rootName),
        onPressed: _path.isEmpty ? null : () => _load(path: ''),
      ),
    );

    var cumulative = '';
    for (final segment in segments) {
      cumulative = cumulative.isEmpty ? segment : '$cumulative/$segment';
      final target = cumulative;
      items
        ..add(const Icon(Icons.chevron_right_rounded, size: 18))
        ..add(
          ActionChip(
            label: Text(segment),
            onPressed: target == _path ? null : () => _load(path: target),
          ),
        );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.accentColor.withValues(alpha: 0.92),
                          colorScheme.tertiary.withValues(alpha: 0.78),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: const Icon(
                            Icons.folder_copy_rounded,
                            color: Colors.white,
                            size: 29,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Deine Dateien',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _storagePath.isEmpty
                                    ? 'Gesamten NAS / USB-Stick verwalten'
                                    : 'Zugewiesener Ordner: $_rootName',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildBreadcrumbs(),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.storage_rounded),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _storageQuotaBytes == null
                                      ? '${_formatSize(_storageUsedBytes)} verwendet · unbegrenzt'
                                      : '${_formatSize(_storageUsedBytes)} von ${_formatSize(_storageQuotaBytes)} verwendet',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_storageQuotaBytes != null) ...[
                            const SizedBox(height: 12),
                            LinearProgressIndicator(
                              value: _storageQuotaBytes == 0
                                  ? 0
                                  : (_storageUsedBytes / _storageQuotaBytes!)
                                        .clamp(0.0, 1.0),
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(99),
                              color: _storageUsedBytes >= _storageQuotaBytes!
                                  ? Colors.redAccent
                                  : widget.accentColor,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (widget.canUpload)
                        FilledButton.icon(
                          onPressed: _uploading ? null : _upload,
                          icon: _uploading
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.upload_file_rounded),
                          label: Text(
                            _uploading ? 'Wird hochgeladen …' : 'Hochladen',
                          ),
                        ),
                      if (widget.canManage)
                        OutlinedButton.icon(
                          onPressed: _createFolder,
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('Neuer Ordner'),
                        ),
                      if (_parentPath != null)
                        OutlinedButton.icon(
                          onPressed: () => _load(path: _parentPath),
                          icon: const Icon(Icons.arrow_upward_rounded),
                          label: const Text('Eine Ebene höher'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_error != null)
                    Card(
                      color: colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_error!)),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Nochmal'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_entries.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(36),
                        child: Column(
                          children: [
                            Icon(
                              Icons.folder_open_rounded,
                              size: 48,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Dieser Ordner ist leer',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Lade eine Datei hoch oder erstelle einen Ordner.',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var index = 0; index < _entries.length; index++)
                            Column(
                              children: [
                                ListTile(
                                  leading: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: entryColor(
                                        _entries[index],
                                        colorScheme,
                                      ).withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    child: Icon(
                                      _iconFor(_entries[index]),
                                      color: entryColor(
                                        _entries[index],
                                        colorScheme,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    _entries[index].name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${_formatSize(_entries[index].size)}  •  ${_formatDate(_entries[index].modified)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => _entries[index].isDirectory
                                      ? _load(path: _entries[index].path)
                                      : _download(_entries[index]),
                                  trailing:
                                      (!_entries[index].isDirectory ||
                                          widget.canManage)
                                      ? PopupMenuButton<String>(
                                          tooltip: 'Aktionen',
                                          onSelected: (action) {
                                            if (action == 'download') {
                                              _download(_entries[index]);
                                            } else if (action == 'rename') {
                                              _rename(_entries[index]);
                                            } else if (action == 'delete') {
                                              _delete(_entries[index]);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            if (!_entries[index].isDirectory)
                                              const PopupMenuItem(
                                                value: 'download',
                                                child: ListTile(
                                                  leading: Icon(
                                                    Icons.download_rounded,
                                                  ),
                                                  title: Text('Herunterladen'),
                                                ),
                                              ),
                                            if (widget.canManage)
                                              const PopupMenuItem(
                                                value: 'rename',
                                                child: ListTile(
                                                  leading: Icon(
                                                    Icons.edit_outlined,
                                                  ),
                                                  title: Text('Umbenennen'),
                                                ),
                                              ),
                                            if (widget.canManage)
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: ListTile(
                                                  leading: Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.redAccent,
                                                  ),
                                                  title: Text('Löschen'),
                                                ),
                                              ),
                                          ],
                                        )
                                      : null,
                                ),
                                if (index != _entries.length - 1)
                                  const Divider(height: 1, indent: 72),
                              ],
                            ),
                        ],
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

  Color entryColor(PiFileEntry entry, ColorScheme colorScheme) {
    if (entry.isDirectory) return widget.accentColor;
    return colorScheme.tertiary;
  }
}

class PiFileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;

  const PiFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

  factory PiFileEntry.fromJson(Map<dynamic, dynamic> json) {
    final modified = json['modified'];
    return PiFileEntry(
      name: json['name']?.toString() ?? 'Unbekannt',
      path: json['path']?.toString() ?? '',
      isDirectory: json['is_directory'] == true,
      size: json['size'] is num ? (json['size'] as num).toInt() : null,
      modified: modified is num
          ? DateTime.fromMillisecondsSinceEpoch(modified.toInt() * 1000)
          : null,
    );
  }
}
