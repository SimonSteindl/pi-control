import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

typedef ProtectedFilePost = Future<http.Response> Function(
  String path,
  Map<String, dynamic> payload, {
  Duration? timeout,
});

class FileManagerView extends StatefulWidget {
  final FileApiGet apiGet;
  final FileApiPost apiPost;
  final String Function() apiBase;
  final String authToken;
  final String username;
  final bool canUpload;
  final bool canManage;
  final Color accentColor;

  const FileManagerView({
    super.key,
    required this.apiGet,
    required this.apiPost,
    required this.apiBase,
    required this.authToken,
    required this.username,
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
  double _uploadProgress = 0;
  double _uploadSpeedMbps = 0;
  http.Client? _uploadClient;
  bool _searching = false;
  bool _showingSearch = false;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedPaths = <String>{};
  final Set<String> _favoritePaths = <String>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _loadFavorites();
  }

  @override
  void dispose() {
    _uploadClient?.close();
    _searchController.dispose();
    super.dispose();
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

  Future<List<PiFileEntry>> _loadFavorites() async {
    try {
      final response = await widget.apiGet('files/favorites', null);
      final decoded = jsonDecode(response.body);
      final favorites = <PiFileEntry>[];
      if (decoded is Map && decoded['items'] is List) {
        for (final item in decoded['items'] as List) {
          if (item is Map) favorites.add(PiFileEntry.fromJson(item));
        }
      }
      if (mounted) {
        setState(() {
          _favoritePaths
            ..clear()
            ..addAll(favorites.map((item) => item.path));
        });
      }
      return favorites;
    } catch (_) {
      return [];
    }
  }

  Future<void> _toggleFavorite(PiFileEntry entry) async {
    final response = await _protectedPost('files/favorites/toggle', {
      'path': entry.path,
    });
    if (response.statusCode == 200) await _loadFavorites();
  }

  Future<void> _openFavorites() async {
    final favorites = await _loadFavorites();
    await _openSavedFiles('Favoriten', favorites, 'Noch keine Favoriten.');
  }

  Future<void> _openRecent() async {
    var recent = <PiFileEntry>[];
    try {
      final response = await widget.apiGet('files/recent', null);
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['items'] is List) {
        recent = (decoded['items'] as List)
            .whereType<Map>()
            .map(PiFileEntry.fromJson)
            .toList();
      }
    } catch (_) {
      // Der Dialog zeigt bei einem Verbindungsproblem einfach keine Einträge.
    }
    await _openSavedFiles(
      'Zuletzt verwendet',
      recent,
      'Noch keine zuletzt verwendeten Dateien.',
    );
  }

  Future<void> _openSavedFiles(
    String title,
    List<PiFileEntry> entries,
    String emptyMessage,
  ) async {
    if (!mounted) return;
    final selected = await showDialog<PiFileEntry>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: entries.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(emptyMessage),
                ),
              ]
            : entries
                  .map(
                    (entry) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, entry),
                      child: ListTile(
                        leading: Icon(
                          entry.isDirectory
                              ? Icons.folder_rounded
                              : Icons.insert_drive_file_outlined,
                        ),
                        title: Text(entry.name),
                        subtitle: Text(entry.path),
                      ),
                    ),
                  )
                  .toList(),
      ),
    );
    if (selected == null) return;
    if (selected.isDirectory) {
      await _load(path: selected.path);
    } else if (_canPreview(selected)) {
      await _preview(selected);
    } else {
      await _download(selected);
    }
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
        _selectedPaths.clear();
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

  Future<void> _move(PiFileEntry entry) async {
    final destination = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _MoveDestinationDialog(
        apiGet: widget.apiGet,
        initialPath: _path,
        sourcePath: entry.path,
        sourceName: entry.name,
        rootName: _rootName,
      ),
    );

    if (destination == null) return;

    await _runFileAction(
      () => _protectedPost('files/move', {
        'path': entry.path,
        'destination': destination,
      }),
      success: '„${entry.name}“ wurde verschoben.',
    );
  }

  Future<void> _delete(PiFileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
        title: Text('${entry.isDirectory ? 'Ordner' : 'Datei'} löschen?'),
        content: Text('„${entry.name}“ wird in den Papierkorb verschoben.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('In Papierkorb'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _runFileAction(
      () => _protectedPost('files/delete', {'path': entry.path}),
      success: '„${entry.name}“ wurde in den Papierkorb verschoben.',
    );
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      _showMessage('Bitte mindestens zwei Zeichen eingeben.');
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final response = await widget.apiGet(
        'files/search?q=${Uri.encodeQueryComponent(query)}',
        null,
      );
      if (response.statusCode != 200) {
        throw Exception(_responseError(response));
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['results'] is! List) {
        throw Exception('Ungültige Suchantwort vom Raspberry Pi.');
      }

      final results = <PiFileEntry>[];
      for (final item in decoded['results'] as List) {
        if (item is Map) results.add(PiFileEntry.fromJson(item));
      }
      if (!mounted) return;
      setState(() {
        _entries = results;
        _showingSearch = true;
        _searching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _clearSearch() async {
    _searchController.clear();
    setState(() => _showingSearch = false);
    await _load();
  }

  bool _isImage(PiFileEntry entry) => {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
  }.contains(entry.extension);

  bool _isVideo(PiFileEntry entry) =>
      {'mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v'}.contains(entry.extension);

  bool _canPreview(PiFileEntry entry) => _isImage(entry) || _isVideo(entry);

  Future<Uri> _previewUri(PiFileEntry entry) async {
    final response = await _protectedPost('files/download-token', {
      'path': entry.path,
      'preview': true,
    });
    if (response.statusCode != 200) {
      throw Exception(_responseError(response));
    }
    final decoded = jsonDecode(response.body);
    final token = decoded is Map ? decoded['token']?.toString() : null;
    if (token == null || token.isEmpty) {
      throw Exception('Vorschau-Link konnte nicht erstellt werden.');
    }
    return Uri.parse(
      '${widget.apiBase()}/files/download/${Uri.encodeComponent(token)}',
    );
  }

  Future<void> _preview(PiFileEntry entry) async {
    try {
      final uri = await _previewUri(entry);
      if (!mounted) return;

      if (_isImage(entry)) {
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: Text(entry.name),
                    trailing: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                  Flexible(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 5,
                      child: Image.network(
                        uri.toString(),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Padding(
                              padding: EdgeInsets.all(40),
                              child: Text(
                                'Bildvorschau konnte nicht geladen werden.',
                              ),
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      } else {
        final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
        if (!launched) {
          throw Exception('Videovorschau konnte nicht geöffnet werden.');
        }
      }
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _share(PiFileEntry entry) async {
    final passwordController = TextEditingController();
    final limitController = TextEditingController();
    var hours = 24;
    final configured = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Freigabelink erstellen'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: hours,
                  decoration: const InputDecoration(labelText: 'Gültigkeit'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 Stunde')),
                    DropdownMenuItem(value: 24, child: Text('24 Stunden')),
                    DropdownMenuItem(value: 72, child: Text('3 Tage')),
                    DropdownMenuItem(value: 168, child: Text('7 Tage')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => hours = value ?? 24),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Passwort (optional)',
                    helperText: 'Mindestens 6 Zeichen',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: limitController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Downloadlimit (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Erstellen'),
            ),
          ],
        ),
      ),
    );
    if (configured != true) return;
    try {
      final response = await _protectedPost('files/share', {
        'path': entry.path,
        'hours': hours,
        'password': passwordController.text,
        'download_limit': int.tryParse(limitController.text),
      });
      if (response.statusCode != 200) {
        throw Exception(_responseError(response));
      }
      final decoded = jsonDecode(response.body);
      final token = decoded is Map ? decoded['token']?.toString() : null;
      if (token == null || token.isEmpty) {
        throw Exception('Freigabelink konnte nicht erstellt werden.');
      }
      final link =
          '${widget.apiBase()}/files/share/${Uri.encodeComponent(token)}';
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.link_rounded),
          title: const Text('Freigabelink kopiert'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 190, height: 190, child: QrImageView(data: link)),
              const SizedBox(height: 16),
              SelectableText(
                '$link\n\nDer Link ist $hours Stunden gültig${passwordController.text.isEmpty ? ' und funktioniert ohne Anmeldung.' : ' und mit einem Passwort geschützt.'}',
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fertig'),
            ),
          ],
        ),
      );
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openTrash() async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _TrashDialog(apiGet: widget.apiGet, post: _protectedPost),
    );
    await _load();
  }

  Future<void> _openShares() {
    return showDialog<void>(
      context: context,
      builder: (context) =>
          _ShareManagerDialog(apiGet: widget.apiGet, post: _protectedPost),
    );
  }

  Future<void> _openVersions(PiFileEntry entry) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _VersionsDialog(
        entry: entry,
        apiGet: widget.apiGet,
        post: _protectedPost,
      ),
    );
    await _load();
  }

  void _toggleSelection(PiFileEntry entry) {
    setState(() {
      if (!_selectedPaths.add(entry.path)) {
        _selectedPaths.remove(entry.path);
      }
    });
  }

  Future<void> _bulkDelete() async {
    final selected = _entries
        .where((entry) => _selectedPaths.contains(entry.path))
        .toList();
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${selected.length} Elemente in den Papierkorb?'),
        content: const Text(
          'Die Auswahl kann später wiederhergestellt werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('In Papierkorb'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    var completed = 0;
    for (final entry in selected) {
      final response = await _protectedPost('files/delete', {
        'path': entry.path,
      });
      if (response.statusCode == 200) completed++;
    }
    _selectedPaths.clear();
    _showMessage('$completed von ${selected.length} Elementen verschoben.');
    await _load();
  }

  Future<void> _bulkMove() async {
    final selected = _entries
        .where((entry) => _selectedPaths.contains(entry.path))
        .toList();
    if (selected.isEmpty) return;

    final destination = await showDialog<String>(
      context: context,
      builder: (context) => _MoveDestinationDialog(
        apiGet: widget.apiGet,
        initialPath: _path,
        sourcePath: selected.first.path,
        sourceName: '${selected.length} Elemente',
        rootName: _rootName,
      ),
    );
    if (destination == null) return;

    var completed = 0;
    for (final entry in selected) {
      final response = await _protectedPost('files/move', {
        'path': entry.path,
        'destination': destination,
      });
      if (response.statusCode == 200) completed++;
    }
    _selectedPaths.clear();
    _showMessage('$completed von ${selected.length} Elementen verschoben.');
    await _load();
  }

  Future<void> _bulkArchive() async {
    final name = await _askForText(
      title: 'ZIP-Archiv erstellen',
      label: 'Dateiname',
      confirmText: 'Erstellen',
      initialValue: 'Archiv.zip',
    );
    if (name == null) return;
    await _runFileAction(
      () => _protectedPost('files/archive', {
        'paths': _selectedPaths.toList(),
        'destination': _path,
        'name': name,
      }, timeout: const Duration(minutes: 5)),
      success: 'ZIP-Archiv wurde erstellt.',
    );
    if (mounted) setState(() => _selectedPaths.clear());
  }

  Future<void> _extract(PiFileEntry entry) => _runFileAction(
    () => _protectedPost('files/extract', {
      'path': entry.path,
    }, timeout: const Duration(minutes: 5)),
    success: '„${entry.name}“ wurde entpackt.',
  );

  Future<void> _dropIntoFolder(PiFileEntry source, PiFileEntry folder) async {
    if (source.path == folder.path) return;
    await _runFileAction(
      () => _protectedPost('files/move', {
        'path': source.path,
        'destination': folder.path,
      }),
      success: '„${source.name}“ wurde nach „${folder.name}“ verschoben.',
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
      _uploadProgress = 0;
      _uploadSpeedMbps = 0;
    });

    try {
      var replace = false;
      while (true) {
        final response = await _sendUploadAttempt(file, replace: replace);
        if (response.statusCode == 409 && !replace && mounted) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Datei ersetzen?'),
              content: const Text(
                'Die vorhandene Datei wird als ältere Version aufbewahrt.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Ersetzen'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            replace = true;
            continue;
          }
          return;
        }
        if (response.statusCode != 200) {
          throw Exception(_responseError(response));
        }
        break;
      }

      _showMessage('„${file.name}“ wurde hochgeladen.');
      await _load();
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = 0;
          _uploadSpeedMbps = 0;
          _uploadClient?.close();
          _uploadClient = null;
        });
      }
    }
  }

  Future<http.Response> _sendUploadAttempt(
    PlatformFile file, {
    required bool replace,
  }) async {
    final fileLength = await file.length();
    var uploadedBytes = 0;
    final stopwatch = Stopwatch()..start();
    var lastUpdate = Duration.zero;
    Stream<List<int>> progressStream() async* {
      await for (final chunk in file.readAsByteStream()) {
        uploadedBytes += chunk.length;
        final elapsed = stopwatch.elapsed;
        if (elapsed - lastUpdate > const Duration(milliseconds: 120) &&
            mounted) {
          lastUpdate = elapsed;
          setState(() {
            _uploadProgress = fileLength == 0 ? 1 : uploadedBytes / fileLength;
            _uploadSpeedMbps = elapsed.inMilliseconds == 0
                ? 0
                : uploadedBytes / 1024 / 1024 / (elapsed.inMilliseconds / 1000);
          });
        }
        yield chunk;
      }
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${widget.apiBase()}/files/upload'),
    );
    request.headers['Authorization'] = 'Bearer ${widget.authToken}';
    request.fields['path'] = _path;
    request.fields['replace'] = replace.toString();
    request.files.add(
      http.MultipartFile(
        'file',
        progressStream(),
        fileLength,
        filename: file.name,
      ),
    );
    _uploadClient?.close();
    _uploadClient = http.Client();
    final streamed = await _uploadClient!
        .send(request)
        .timeout(const Duration(minutes: 5));
    return http.Response.fromStream(streamed);
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

  String get _webDavUrl {
    final apiUri = Uri.parse(widget.apiBase());
    final segments = apiUri.pathSegments.toList();
    if (segments.isNotEmpty && segments.last == 'api') {
      segments.removeLast();
    }
    return apiUri
        .replace(pathSegments: [...segments, 'webdav', ''], query: null)
        .toString();
  }

  Future<void> _openWebDavInfo() async {
    final url = _webDavUrl;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.cloud_sync_outlined),
        title: const Text('WebDAV-Zugriff'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Füge diese Adresse in deiner WebDAV-App oder als Netzlaufwerk hinzu. '
                'Es gelten dieselben Ordnerrechte und Speicherlimits wie in Pi Control.',
              ),
              const SizedBox(height: 18),
              const Text(
                'Serveradresse',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              SelectableText(url),
              const SizedBox(height: 14),
              const Text(
                'Benutzername',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              SelectableText(widget.username),
              const SizedBox(height: 14),
              const Text(
                'Passwort: dein aktuelles Pi-Control-Passwort. Verwende unterwegs nur die HTTPS-Adresse.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('WebDAV-Adresse kopiert.')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Adresse kopieren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fertig'),
          ),
        ],
      ),
    );
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

  Widget _entryLeading(PiFileEntry entry, ColorScheme colorScheme) {
    if (_selectedPaths.isNotEmpty) {
      return Checkbox(
        value: _selectedPaths.contains(entry.path),
        onChanged: (_) => _toggleSelection(entry),
      );
    }

    final icon = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: entryColor(entry, colorScheme).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(_iconFor(entry), color: entryColor(entry, colorScheme)),
    );

    final draggable = LongPressDraggable<PiFileEntry>(
      data: entry,
      feedback: Material(
        color: Colors.transparent,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconFor(entry)),
                const SizedBox(width: 8),
                Text(entry.name),
              ],
            ),
          ),
        ),
      ),
      child: icon,
    );

    if (entry.isDirectory && widget.canManage) {
      return DragTarget<PiFileEntry>(
        onWillAcceptWithDetails: (details) => details.data.path != entry.path,
        onAcceptWithDetails: (details) => _dropIntoFolder(details.data, entry),
        builder: (context, candidates, rejected) => AnimatedScale(
          scale: candidates.isEmpty ? 1 : 1.15,
          duration: const Duration(milliseconds: 120),
          child: draggable,
        ),
      );
    }
    return draggable;
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
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      labelText: 'Dateien und Ordner suchen',
                      hintText: 'Mindestens zwei Zeichen',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _showingSearch
                          ? IconButton(
                              onPressed: _clearSearch,
                              tooltip: 'Suche schließen',
                              icon: const Icon(Icons.close_rounded),
                            )
                          : IconButton(
                              onPressed: _searching ? null : _search,
                              tooltip: 'Suchen',
                              icon: _searching
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_forward_rounded),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (_showingSearch) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_entries.length} Treffer für „${_searchController.text.trim()}“',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
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
                      if (_uploading)
                        OutlinedButton.icon(
                          onPressed: () {
                            _uploadClient?.close();
                            setState(() => _uploading = false);
                          },
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Abbrechen'),
                        ),
                      if (widget.canManage)
                        OutlinedButton.icon(
                          onPressed: _createFolder,
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('Neuer Ordner'),
                        ),
                      if (widget.canManage)
                        OutlinedButton.icon(
                          onPressed: _openTrash,
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Papierkorb'),
                        ),
                      OutlinedButton.icon(
                        onPressed: _openShares,
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('Freigaben'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openWebDavInfo,
                        icon: const Icon(Icons.cloud_sync_outlined),
                        label: const Text('WebDAV'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openFavorites,
                        icon: const Icon(Icons.star_outline_rounded),
                        label: const Text('Favoriten'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openRecent,
                        icon: const Icon(Icons.history_rounded),
                        label: const Text('Zuletzt'),
                      ),
                      if (_parentPath != null)
                        OutlinedButton.icon(
                          onPressed: () => _load(path: _parentPath),
                          icon: const Icon(Icons.arrow_upward_rounded),
                          label: const Text('Eine Ebene höher'),
                        ),
                    ],
                  ),
                  if (_uploading) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _uploadProgress.clamp(0, 1),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${(_uploadProgress * 100).toStringAsFixed(0)} % · ${_uploadSpeedMbps.toStringAsFixed(1)} MB/s',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_selectedPaths.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_selectedPaths.length} ausgewählt',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _bulkMove,
                              tooltip: 'Auswahl verschieben',
                              icon: const Icon(Icons.drive_file_move_outline),
                            ),
                            IconButton(
                              onPressed: _bulkArchive,
                              tooltip: 'Auswahl als ZIP speichern',
                              icon: const Icon(Icons.archive_outlined),
                            ),
                            IconButton(
                              onPressed: _bulkDelete,
                              tooltip: 'Auswahl in Papierkorb',
                              icon: const Icon(Icons.delete_outline),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() => _selectedPaths.clear());
                              },
                              tooltip: 'Auswahl aufheben',
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                            Text(
                              _showingSearch
                                  ? 'Keine Treffer gefunden'
                                  : 'Dieser Ordner ist leer',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _showingSearch
                                  ? 'Versuche einen anderen Suchbegriff.'
                                  : 'Lade eine Datei hoch oder erstelle einen Ordner.',
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
                                  leading: _entryLeading(
                                    _entries[index],
                                    colorScheme,
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
                                    _showingSearch
                                        ? _entries[index].path
                                        : '${_formatSize(_entries[index].size)}  •  ${_formatDate(_entries[index].modified)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {
                                    final entry = _entries[index];
                                    if (_selectedPaths.isNotEmpty) {
                                      _toggleSelection(entry);
                                      return;
                                    }
                                    if (entry.isDirectory) {
                                      _searchController.clear();
                                      setState(() => _showingSearch = false);
                                      _load(path: entry.path);
                                    } else if (_canPreview(entry)) {
                                      _preview(entry);
                                    } else {
                                      _download(entry);
                                    }
                                  },
                                  onLongPress: () =>
                                      _toggleSelection(_entries[index]),
                                  trailing:
                                      (!_entries[index].isDirectory ||
                                          widget.canManage)
                                      ? PopupMenuButton<String>(
                                          tooltip: 'Aktionen',
                                          onSelected: (action) {
                                            if (action == 'download') {
                                              _download(_entries[index]);
                                            } else if (action == 'preview') {
                                              _preview(_entries[index]);
                                            } else if (action == 'share') {
                                              _share(_entries[index]);
                                            } else if (action == 'favorite') {
                                              _toggleFavorite(_entries[index]);
                                            } else if (action == 'versions') {
                                              _openVersions(_entries[index]);
                                            } else if (action == 'rename') {
                                              _rename(_entries[index]);
                                            } else if (action == 'move') {
                                              _move(_entries[index]);
                                            } else if (action == 'extract') {
                                              _extract(_entries[index]);
                                            } else if (action == 'delete') {
                                              _delete(_entries[index]);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'favorite',
                                              child: ListTile(
                                                leading: Icon(
                                                  _favoritePaths.contains(
                                                        _entries[index].path,
                                                      )
                                                      ? Icons.star_rounded
                                                      : Icons
                                                            .star_outline_rounded,
                                                ),
                                                title: Text(
                                                  _favoritePaths.contains(
                                                        _entries[index].path,
                                                      )
                                                      ? 'Favorit entfernen'
                                                      : 'Als Favorit',
                                                ),
                                              ),
                                            ),
                                            if (_canPreview(_entries[index]))
                                              const PopupMenuItem(
                                                value: 'preview',
                                                child: ListTile(
                                                  leading: Icon(
                                                    Icons.visibility_outlined,
                                                  ),
                                                  title: Text('Vorschau'),
                                                ),
                                              ),
                                            if (!_entries[index].isDirectory)
                                              const PopupMenuItem(
                                                value: 'versions',
                                                child: ListTile(
                                                  leading: Icon(
                                                    Icons.history_rounded,
                                                  ),
                                                  title: Text('Dateiversionen'),
                                                ),
                                              ),
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
                                            if (!_entries[index].isDirectory)
                                              const PopupMenuItem(
                                                value: 'share',
                                                child: ListTile(
                                                  leading: Icon(
                                                    Icons.share_outlined,
                                                  ),
                                                  title: Text('Freigabelink'),
                                                ),
                                              ),
                                            if (widget.canManage)
                                              if (_entries[index].extension ==
                                                  'zip')
                                                const PopupMenuItem(
                                                  value: 'extract',
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons.unarchive_outlined,
                                                    ),
                                                    title: Text('Entpacken'),
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
                                                value: 'move',
                                                child: ListTile(
                                                  leading: Icon(
                                                    Icons
                                                        .drive_file_move_outline,
                                                  ),
                                                  title: Text('Verschieben'),
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

  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';

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

class _MoveDestinationDialog extends StatefulWidget {
  final FileApiGet apiGet;
  final String initialPath;
  final String sourcePath;
  final String sourceName;
  final String rootName;

  const _MoveDestinationDialog({
    required this.apiGet,
    required this.initialPath,
    required this.sourcePath,
    required this.sourceName,
    required this.rootName,
  });

  @override
  State<_MoveDestinationDialog> createState() => _MoveDestinationDialogState();
}

class _MoveDestinationDialogState extends State<_MoveDestinationDialog> {
  String _path = '';
  String? _parentPath;
  List<PiFileEntry> _folders = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _load(_path);
  }

  String get _sourceParent {
    final separator = widget.sourcePath.lastIndexOf('/');
    return separator < 0 ? '' : widget.sourcePath.substring(0, separator);
  }

  bool get _canSelect => _path != _sourceParent;

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final encodedPath = Uri.encodeQueryComponent(path);
      final response = await widget.apiGet('files?path=$encodedPath', null);

      if (response.statusCode != 200) {
        throw Exception(_responseError(response));
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['entries'] is! List) {
        throw Exception('Ungültige Antwort vom Raspberry Pi.');
      }

      final folders = <PiFileEntry>[];
      for (final item in decoded['entries'] as List) {
        if (item is! Map) continue;
        final entry = PiFileEntry.fromJson(item);
        if (!entry.isDirectory) continue;
        if (entry.path == widget.sourcePath ||
            entry.path.startsWith('${widget.sourcePath}/')) {
          continue;
        }
        folders.add(entry);
      }

      if (!mounted) return;
      setState(() {
        _path = decoded['path']?.toString() ?? '';
        _parentPath = decoded['parent']?.toString();
        _folders = folders;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentLabel = _path.isEmpty ? widget.rootName : _path;

    return AlertDialog(
      icon: const Icon(Icons.drive_file_move_outline),
      title: Text('„${widget.sourceName}“ verschieben'),
      content: SizedBox(
        width: 430,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Zielordner: $currentLabel',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (_parentPath != null)
              ListTile(
                leading: const Icon(Icons.arrow_upward_rounded),
                title: const Text('Eine Ebene nach oben'),
                onTap: _loading ? null : () => _load(_parentPath!),
              ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colorScheme.error),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => _load(_path),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Nochmal'),
                          ),
                        ],
                      ),
                    )
                  : _folders.isEmpty
                  ? const Center(child: Text('Keine Unterordner vorhanden.'))
                  : ListView.builder(
                      itemCount: _folders.length,
                      itemBuilder: (context, index) {
                        final folder = _folders[index];
                        return ListTile(
                          leading: const Icon(Icons.folder_rounded),
                          title: Text(
                            folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _load(folder.path),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: !_loading && _error == null && _canSelect
              ? () => Navigator.of(context).pop(_path)
              : null,
          icon: const Icon(Icons.drive_file_move_outline),
          label: const Text('Hierher verschieben'),
        ),
      ],
    );
  }
}

class _TrashDialog extends StatefulWidget {
  final FileApiGet apiGet;
  final ProtectedFilePost post;

  const _TrashDialog({required this.apiGet, required this.post});

  @override
  State<_TrashDialog> createState() => _TrashDialogState();
}

class _TrashDialogState extends State<_TrashDialog> {
  List<_TrashItem> _items = [];
  bool _loading = true;
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
      // Der HTTP-Status wird als Rückfall verwendet.
    }
    return 'HTTP ${response.statusCode}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.apiGet('files/trash', null);
      if (response.statusCode != 200) {
        throw Exception(_responseError(response));
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['items'] is! List) {
        throw Exception('Ungültige Papierkorb-Antwort.');
      }
      final items = <_TrashItem>[];
      for (final item in decoded['items'] as List) {
        if (item is Map) items.add(_TrashItem.fromJson(item));
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
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _restore(_TrashItem item) async {
    final response = await widget.post('files/trash/restore', {'id': item.id});
    if (response.statusCode != 200) {
      if (mounted) {
        setState(() => _error = _responseError(response));
      }
      return;
    }
    await _load();
  }

  Future<void> _permanentDelete(_TrashItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
        title: const Text('Endgültig löschen?'),
        content: Text(
          '„${item.name}“ kann danach nicht wiederhergestellt werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Endgültig löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final response = await widget.post('files/trash/permanent-delete', {
      'id': item.id,
    });
    if (response.statusCode != 200) {
      if (mounted) setState(() => _error = _responseError(response));
      return;
    }
    await _load();
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year}, '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 700),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text(
                'Papierkorb',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Dateien wiederherstellen oder endgültig löschen',
              ),
              trailing: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colorScheme.error),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Nochmal'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _items.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 52),
                          SizedBox(height: 10),
                          Text('Der Papierkorb ist leer.'),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return ListTile(
                          leading: Icon(
                            item.isDirectory
                                ? Icons.folder_outlined
                                : Icons.insert_drive_file_outlined,
                          ),
                          title: Text(item.name),
                          subtitle: Text(
                            '${item.originalPath}\nGelöscht: ${_formatDate(item.deletedAt)}',
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'restore') {
                                _restore(item);
                              } else if (action == 'delete') {
                                _permanentDelete(item);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'restore',
                                child: ListTile(
                                  leading: Icon(Icons.restore_rounded),
                                  title: Text('Wiederherstellen'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  leading: Icon(
                                    Icons.delete_forever_outlined,
                                    color: Colors.redAccent,
                                  ),
                                  title: Text('Endgültig löschen'),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrashItem {
  final int id;
  final String name;
  final String originalPath;
  final bool isDirectory;
  final DateTime deletedAt;

  const _TrashItem({
    required this.id,
    required this.name,
    required this.originalPath,
    required this.isDirectory,
    required this.deletedAt,
  });

  factory _TrashItem.fromJson(Map<dynamic, dynamic> json) {
    final deleted = json['deleted_at'];
    return _TrashItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? 'Unbekannt',
      originalPath: json['original_path']?.toString() ?? '',
      isDirectory: json['is_directory'] == true,
      deletedAt: DateTime.fromMillisecondsSinceEpoch(
        (deleted is num ? deleted.toInt() : 0) * 1000,
      ),
    );
  }
}

class _ShareManagerDialog extends StatefulWidget {
  final FileApiGet apiGet;
  final ProtectedFilePost post;

  const _ShareManagerDialog({required this.apiGet, required this.post});

  @override
  State<_ShareManagerDialog> createState() => _ShareManagerDialogState();
}

class _ShareManagerDialogState extends State<_ShareManagerDialog> {
  List<_ShareItem> _items = [];
  bool _loading = true;
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
    } catch (_) {}
    return 'HTTP ${response.statusCode}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.apiGet('files/shares', null);
      if (response.statusCode != 200) {
        throw Exception(_responseError(response));
      }
      final decoded = jsonDecode(response.body);
      final items = <_ShareItem>[];
      if (decoded is Map && decoded['shares'] is List) {
        for (final item in decoded['shares'] as List) {
          if (item is Map) items.add(_ShareItem.fromJson(item));
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
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _revoke(_ShareItem item) async {
    final response = await widget.post('files/shares/revoke', {'id': item.id});
    if (response.statusCode != 200) {
      if (mounted) setState(() => _error = _responseError(response));
      return;
    }
    await _load();
  }

  String _date(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}.${two(value.month)}.${value.year}, '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text(
                'Aktive Freigabelinks',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Links anzeigen und vorzeitig deaktivieren'),
              trailing: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.error),
                      ),
                    )
                  : _items.isEmpty
                  ? const Center(child: Text('Keine aktiven Freigabelinks.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return ListTile(
                          leading: const Icon(Icons.insert_link_rounded),
                          title: Text(item.name),
                          subtitle: Text(
                            '${item.path}\nGültig bis ${_date(item.expiresAt)} · ${item.passwordProtected ? 'Passwort' : 'Ohne Passwort'} · ${item.downloadCount}${item.downloadLimit == null ? '' : '/${item.downloadLimit}'} Downloads',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            onPressed: () => _revoke(item),
                            tooltip: 'Link deaktivieren',
                            icon: const Icon(
                              Icons.link_off_rounded,
                              color: Colors.redAccent,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionsDialog extends StatefulWidget {
  final PiFileEntry entry;
  final FileApiGet apiGet;
  final ProtectedFilePost post;

  const _VersionsDialog({
    required this.entry,
    required this.apiGet,
    required this.post,
  });

  @override
  State<_VersionsDialog> createState() => _VersionsDialogState();
}

class _VersionsDialogState extends State<_VersionsDialog> {
  List<Map<String, dynamic>> versions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final response = await widget.apiGet(
      'files/versions?path=${Uri.encodeQueryComponent(widget.entry.path)}',
      null,
    );
    final decoded = jsonDecode(response.body);
    if (!mounted) return;
    setState(() {
      final raw = decoded is Map ? decoded['versions'] : null;
      versions = raw is List
          ? raw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : [];
      loading = false;
    });
  }

  Future<void> restore(Map<String, dynamic> version) async {
    final response = await widget.post('files/versions/restore', {
      'path': widget.entry.path,
      'id': version['id'],
    });
    if (!mounted) return;
    if (response.statusCode == 200) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Versionen von ${widget.entry.name}'),
    content: SizedBox(
      width: 560,
      height: 380,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : versions.isEmpty
          ? const Center(child: Text('Noch keine ältere Version vorhanden.'))
          : ListView.builder(
              itemCount: versions.length,
              itemBuilder: (context, index) {
                final version = versions[index];
                final date = DateTime.fromMillisecondsSinceEpoch(
                  ((version['created_at'] as num?)?.toInt() ?? 0) * 1000,
                );
                return ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: Text(
                    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                  ),
                  subtitle: Text(
                    '${((version['size'] as num? ?? 0) / 1024).toStringAsFixed(0)} KB',
                  ),
                  trailing: TextButton(
                    onPressed: () => restore(version),
                    child: const Text('Wiederherstellen'),
                  ),
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Schließen'),
      ),
    ],
  );
}

class _ShareItem {
  final String id;
  final String name;
  final String path;
  final DateTime expiresAt;
  final bool passwordProtected;
  final int downloadCount;
  final int? downloadLimit;

  const _ShareItem({
    required this.id,
    required this.name,
    required this.path,
    required this.expiresAt,
    required this.passwordProtected,
    required this.downloadCount,
    required this.downloadLimit,
  });

  factory _ShareItem.fromJson(Map<dynamic, dynamic> json) => _ShareItem(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Datei',
    path: json['path']?.toString() ?? '',
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      ((json['expires_at'] as num?)?.toInt() ?? 0) * 1000,
    ),
    passwordProtected: json['password_protected'] == true,
    downloadCount: (json['download_count'] as num?)?.toInt() ?? 0,
    downloadLimit: (json['download_limit'] as num?)?.toInt(),
  );
}
