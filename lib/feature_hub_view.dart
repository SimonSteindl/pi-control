import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth.dart';

class FeatureHubView extends StatelessWidget {
  final PiApiClient client;
  final AuthSession session;

  const FeatureHubView({
    super.key,
    required this.client,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.photo_library_outlined), text: 'Medien'),
      const Tab(icon: Icon(Icons.checklist_rounded), text: 'Organizer'),
      const Tab(icon: Icon(Icons.devices_rounded), text: 'Geräte'),
      const Tab(icon: Icon(Icons.lock_outline_rounded), text: 'Tresore'),
      if (session.isAdmin)
        const Tab(
          icon: Icon(Icons.admin_panel_settings_outlined),
          text: 'System',
        ),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(isScrollable: true, tabs: tabs),
          Expanded(
            child: TabBarView(
              children: [
                _GalleryTab(client: client),
                _OrganizerTab(client: client),
                _SessionsTab(client: client),
                _VaultsTab(client: client),
                if (session.isAdmin) _SystemToolsTab(client: client),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryTab extends StatefulWidget {
  final PiApiClient client;
  const _GalleryTab({required this.client});
  @override
  State<_GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<_GalleryTab> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  bool backingUp = false;
  String? error;
  final Map<String, Future<String?>> thumbnails = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await widget.client.get(
        'files/gallery',
        timeout: const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw widget.client.responseException(response);
      }
      final raw = widget.client.decodeObject(response)['items'];
      if (!mounted) return;
      setState(() {
        items = raw is List
            ? raw
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : [];
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e.toString();
        });
      }
    }
  }

  IconData iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm')) {
      return Icons.movie_rounded;
    }
    if (lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.flac')) {
      return Icons.music_note_rounded;
    }
    return Icons.image_rounded;
  }

  bool isImage(String name) => RegExp(
    r'\.(jpe?g|png|gif|webp|heic)$',
    caseSensitive: false,
  ).hasMatch(name);

  Future<String?> previewUrl(String path) async {
    final response = await widget.client.post(
      'files/download-token',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'path': path, 'preview': true}),
    );
    if (response.statusCode != 200) return null;
    final token = widget.client.decodeObject(response)['token']?.toString();
    return token == null
        ? null
        : '${widget.client.activeBase}/files/download/$token';
  }

  Future<void> openItem(Map<String, dynamic> item) async {
    final name = item['name']?.toString() ?? '';
    final url = await previewUrl(item['path']?.toString() ?? '');
    if (url == null || !mounted) return;
    if (isImage(name)) {
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
      );
    } else {
      await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
    }
  }

  Future<void> backupPhoneMedia() async {
    final selected = await ImagePicker().pickMultipleMedia(imageQuality: 95);
    if (selected.isEmpty || !mounted) return;
    setState(() => backingUp = true);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.client.activeBase}/mobile-backup'),
      );
      final token = widget.client.token;
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      for (final file in selected) {
        request.files.add(
          http.MultipartFile(
            'files',
            file.openRead(),
            await file.length(),
            filename: file.name,
          ),
        );
      }
      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(minutes: 10)),
      );
      if (response.statusCode != 200) {
        throw widget.client.responseException(response);
      }
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${selected.length} Medien wurden gesichert.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => backingUp = false);
    }
  }

  Future<void> addToPlaylist(Map<String, dynamic> item) async {
    final response = await widget.client.get('playlists');
    final raw = widget.client.decodeObject(response)['playlists'];
    final playlists = raw is List ? raw.whereType<Map>().toList() : <Map>[];
    if (!mounted) return;
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Zu Wiedergabeliste'),
        children: [
          ...playlists.map(
            (playlist) => SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(context, (playlist['id'] as num).toInt()),
              child: ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(playlist['name'].toString()),
                subtitle: Text('${playlist['item_count']} Titel'),
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, -1),
            child: const ListTile(
              leading: Icon(Icons.add_rounded),
              title: Text('Neue Wiedergabeliste'),
            ),
          ),
        ],
      ),
    );
    if (selected == null) return;
    if (!mounted) return;
    var playlistId = selected;
    if (selected == -1) {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Neue Wiedergabeliste'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Erstellen'),
            ),
          ],
        ),
      );
      if (name == null || name.trim().isEmpty) return;
      final created = await widget.client.post(
        'playlists',
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name.trim()}),
      );
      if (!mounted) return;
      playlistId = (widget.client.decodeObject(created)['id'] as num).toInt();
    }
    await widget.client.post(
      'playlists/$playlistId/items',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'path': item['path']}),
    );
  }

  Future<void> openPlaylists() async {
    final response = await widget.client.get('playlists');
    final raw = widget.client.decodeObject(response)['playlists'];
    final playlists = raw is List ? raw.whereType<Map>().toList() : <Map>[];
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Wiedergabelisten'),
        children: playlists.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Noch keine Wiedergabeliste. Halte ein Medium gedrückt, um eine anzulegen.',
                  ),
                ),
              ]
            : playlists
                  .map(
                    (playlist) => SimpleDialogOption(
                      onPressed: () async {
                        final itemsResponse = await widget.client.get(
                          'playlists/${playlist['id']}/items',
                        );
                        final itemsRaw = widget.client.decodeObject(
                          itemsResponse,
                        )['items'];
                        final mediaItems = itemsRaw is List
                            ? itemsRaw
                                  .whereType<Map>()
                                  .map(
                                    (item) => Map<String, dynamic>.from(item),
                                  )
                                  .toList()
                            : <Map<String, dynamic>>[];
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        if (!mounted) return;
                        await showDialog<void>(
                          context: context,
                          builder: (context) => SimpleDialog(
                            title: Text(playlist['name'].toString()),
                            children: mediaItems
                                .map(
                                  (media) => SimpleDialogOption(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      openItem(media);
                                    },
                                    child: ListTile(
                                      leading: Icon(
                                        iconFor(media['name'].toString()),
                                      ),
                                      title: Text(media['name'].toString()),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        );
                      },
                      child: ListTile(
                        leading: const Icon(Icons.queue_music_rounded),
                        title: Text(playlist['name'].toString()),
                        subtitle: Text('${playlist['item_count']} Titel'),
                      ),
                    ),
                  )
                  .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return _ErrorPane(message: error!, onRetry: load);
    if (items.isEmpty) {
      return const _EmptyPane(
        icon: Icons.photo_library_outlined,
        title: 'Noch keine Medien',
        subtitle: 'Fotos, Videos und Musik erscheinen automatisch hier.',
      );
    }
    return Scaffold(
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'playlists',
            onPressed: openPlaylists,
            tooltip: 'Wiedergabelisten',
            child: const Icon(Icons.queue_music_rounded),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'mobile-backup',
            onPressed: backingUp ? null : backupPhoneMedia,
            icon: backingUp
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.backup_rounded),
            label: Text(backingUp ? 'Sichert …' : 'Handy sichern'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisExtent: 180,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final name = item['name']?.toString() ?? 'Medium';
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => openItem(item),
                onLongPress: () => addToPlaylist(item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: isImage(name)
                          ? FutureBuilder<String?>(
                              future: thumbnails.putIfAbsent(
                                item['path'].toString(),
                                () => previewUrl(item['path'].toString()),
                              ),
                              builder: (context, snapshot) =>
                                  snapshot.data == null
                                  ? ColoredBox(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      child: Icon(iconFor(name), size: 54),
                                    )
                                  : Image.network(
                                      snapshot.data!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                    ),
                            )
                          : ColoredBox(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: Icon(iconFor(name), size: 54),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrganizerTab extends StatefulWidget {
  final PiApiClient client;
  const _OrganizerTab({required this.client});
  @override
  State<_OrganizerTab> createState() => _OrganizerTabState();
}

class _OrganizerTabState extends State<_OrganizerTab> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final response = await widget.client.get('personal-items');
    if (!mounted) return;
    if (response.statusCode != 200) {
      setState(() => loading = false);
      return;
    }
    final raw = widget.client.decodeObject(response)['items'];
    setState(() {
      items = raw is List
          ? raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : [];
      loading = false;
    });
  }

  Future<void> add() async {
    final title = TextEditingController();
    String kind = 'note';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Neuer Eintrag'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'note', label: Text('Notiz')),
                  ButtonSegment(value: 'task', label: Text('Aufgabe')),
                  ButtonSegment(value: 'shopping', label: Text('Einkauf')),
                ],
                selected: {kind},
                onSelectionChanged: (value) =>
                    setDialogState(() => kind = value.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Titel'),
              ),
            ],
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
    if (accepted != true || title.text.trim().isEmpty) return;
    await widget.client.post(
      'personal-items',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'kind': kind, 'title': title.text.trim()}),
    );
    await load();
  }

  Future<void> scan() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Mit Kamera scannen'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Bild auswählen'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (image == null) return;
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('Text wird erkannt …')),
          ],
        ),
      ),
    );
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.client.activeBase}/ocr'),
      );
      final token = widget.client.token;
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        http.MultipartFile(
          'file',
          image.openRead(),
          await image.length(),
          filename: image.name,
        ),
      );
      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(minutes: 2)),
      );
      if (!mounted) return;
      Navigator.pop(context);
      if (response.statusCode != 200) {
        throw widget.client.responseException(response);
      }
      final recognized =
          widget.client.decodeObject(response)['text']?.toString() ?? '';
      final title = recognized.trim().split('\n').firstOrNull ?? 'Scan';
      await widget.client.post(
        'personal-items',
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'kind': 'note',
          'title': title.isEmpty ? 'Scan' : title,
          'content': recognized,
        }),
      );
      await load();
    } catch (error) {
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> toggle(Map<String, dynamic> item, bool value) async {
    await widget.client.patch(
      'personal-items/${item['id']}',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'completed': value}),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: 'scan',
          onPressed: scan,
          tooltip: 'Dokument scannen',
          child: const Icon(Icons.document_scanner_outlined),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'organizer-add',
          onPressed: add,
          icon: const Icon(Icons.add),
          label: const Text('Neu'),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : items.isEmpty
        ? const _EmptyPane(
            icon: Icons.edit_note_rounded,
            title: 'Alles an einem Ort',
            subtitle: 'Erstelle Notizen, Aufgaben oder Einkaufslisten.',
          )
        : RefreshIndicator(
            onRefresh: load,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final completable = item['kind'] != 'note';
                return Card(
                  child: CheckboxListTile(
                    value: item['completed'] == 1,
                    onChanged: completable
                        ? (value) => toggle(item, value ?? false)
                        : null,
                    secondary: Icon(
                      item['kind'] == 'shopping'
                          ? Icons.shopping_cart_outlined
                          : item['kind'] == 'task'
                          ? Icons.task_alt_rounded
                          : Icons.note_outlined,
                    ),
                    title: Text(item['title']?.toString() ?? ''),
                    subtitle: Text(
                      item['kind'] == 'shopping'
                          ? 'Einkaufsliste'
                          : item['kind'] == 'task'
                          ? 'Aufgabe'
                          : 'Notiz',
                    ),
                    controlAffinity: ListTileControlAffinity.trailing,
                  ),
                );
              },
            ),
          ),
  );
}

class _SessionsTab extends StatefulWidget {
  final PiApiClient client;
  const _SessionsTab({required this.client});
  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab> {
  List<Map<String, dynamic>> sessions = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final response = await widget.client.get('auth/sessions');
    if (!mounted) return;
    final raw = widget.client.decodeObject(response)['sessions'];
    setState(() {
      sessions = raw is List
          ? raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : [];
      loading = false;
    });
  }

  Future<void> revoke(String id) async {
    await widget.client.post(
      'auth/sessions/revoke',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'id': id}),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => loading
      ? const Center(child: CircularProgressIndicator())
      : RefreshIndicator(
          onRefresh: load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const ListTile(
                title: Text(
                  'Angemeldete Geräte',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  'Unbekannte Sitzungen können sofort abgemeldet werden.',
                ),
              ),
              ...sessions.map(
                (item) => Card(
                  child: ListTile(
                    leading: Icon(
                      item['current'] == true
                          ? Icons.phonelink_lock_rounded
                          : Icons.devices_other_rounded,
                    ),
                    title: Text(item['device_name']?.toString() ?? 'Gerät'),
                    subtitle: Text(
                      '${item['ip_address'] ?? '—'}${item['current'] == true ? ' · Dieses Gerät' : ''}',
                    ),
                    trailing: item['current'] == true
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : IconButton(
                            onPressed: () => revoke(item['id'].toString()),
                            icon: const Icon(Icons.logout_rounded),
                            tooltip: 'Abmelden',
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
}

class _VaultsTab extends StatefulWidget {
  final PiApiClient client;
  const _VaultsTab({required this.client});
  @override
  State<_VaultsTab> createState() => _VaultsTabState();
}

class _VaultsTabState extends State<_VaultsTab> {
  List<Map<String, dynamic>> vaults = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final response = await widget.client.get('vaults');
    if (!mounted) return;
    final raw = widget.client.decodeObject(response)['vaults'];
    setState(() {
      vaults = raw is List
          ? raw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : [];
      loading = false;
    });
  }

  Future<String?> passwordDialog(String title, {bool withName = false}) async {
    final name = TextEditingController();
    final password = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (withName)
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Tresorname'),
              ),
            if (withName) const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              autofocus: !withName,
              decoration: const InputDecoration(
                labelText: 'Tresorpasswort',
                helperText: 'Mindestens 10 Zeichen',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              withName ? '${name.text}\u0000${password.text}' : password.text,
            ),
            child: Text(withName ? 'Erstellen' : 'Öffnen'),
          ),
        ],
      ),
    );
  }

  Future<void> create() async {
    final values = await passwordDialog(
      'Verschlüsselten Tresor erstellen',
      withName: true,
    );
    if (values == null) return;
    final parts = values.split('\u0000');
    final response = await widget.client.post(
      'vaults',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': parts.first,
        'password': parts.length > 1 ? parts[1] : '',
      }),
      timeout: const Duration(seconds: 40),
    );
    if (response.statusCode != 200 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.client.responseException(response).toString()),
        ),
      );
    }
    await load();
  }

  Future<void> toggle(Map<String, dynamic> vault) async {
    final unlocked = vault['unlocked'] == true;
    String password = '';
    if (!unlocked) {
      final value = await passwordDialog('${vault['name']} öffnen');
      if (value == null) return;
      password = value;
    }
    final response = await widget.client.post(
      'vaults/${vault['id']}/${unlocked ? 'lock' : 'unlock'}',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'password': password}),
      timeout: const Duration(seconds: 40),
    );
    if (response.statusCode != 200 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.client.responseException(response).toString()),
        ),
      );
    }
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton.extended(
      onPressed: create,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Tresor'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const ListTile(
                  title: Text(
                    'Private Tresore',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    'Dateinamen und Inhalte werden mit gocryptfs verschlüsselt. Das Passwort wird nicht gespeichert.',
                  ),
                ),
                ...vaults.map(
                  (vault) => Card(
                    child: ListTile(
                      leading: Icon(
                        vault['unlocked'] == true
                            ? Icons.lock_open_rounded
                            : Icons.lock_rounded,
                      ),
                      title: Text(vault['name']?.toString() ?? 'Tresor'),
                      subtitle: Text(
                        vault['unlocked'] == true
                            ? 'Geöffnet · im Dateimanager unter Private'
                            : 'Sicher gesperrt',
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () => toggle(vault),
                        child: Text(
                          vault['unlocked'] == true ? 'Sperren' : 'Öffnen',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
  );
}

class _SystemToolsTab extends StatefulWidget {
  final PiApiClient client;
  const _SystemToolsTab({required this.client});
  @override
  State<_SystemToolsTab> createState() => _SystemToolsTabState();
}

class _SystemToolsTabState extends State<_SystemToolsTab> {
  Map<String, dynamic> storage = {};
  List<dynamic> devices = [];
  List<dynamic> containers = [];
  List<dynamic> events = [];
  List<dynamic> tasks = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final results = await Future.wait([
      widget.client.get(
        'storage-analysis',
        timeout: const Duration(minutes: 2),
      ),
      widget.client.get('network/devices'),
      widget.client.get('docker/containers'),
      widget.client.get('audit?limit=50'),
      widget.client.get('scheduled-tasks'),
    ]);
    if (!mounted) return;
    setState(() {
      storage = widget.client.decodeObject(results[0]);
      devices =
          widget.client.decodeObject(results[1])['devices'] as List? ?? [];
      containers =
          widget.client.decodeObject(results[2])['containers'] as List? ?? [];
      events = widget.client.decodeObject(results[3])['events'] as List? ?? [];
      tasks = widget.client.decodeObject(results[4])['tasks'] as List? ?? [];
      loading = false;
    });
  }

  Future<void> addTask() async {
    final name = TextEditingController();
    final time = TextEditingController(text: '03:00');
    var action = 'backup';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Aufgabe planen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: time,
                decoration: const InputDecoration(labelText: 'Uhrzeit (HH:MM)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: action,
                decoration: const InputDecoration(labelText: 'Aktion'),
                items: const [
                  DropdownMenuItem(
                    value: 'backup',
                    child: Text('Backup erstellen'),
                  ),
                  DropdownMenuItem(
                    value: 'reboot',
                    child: Text('Raspberry Pi neu starten'),
                  ),
                  DropdownMenuItem(
                    value: 'restart_samba',
                    child: Text('Samba neu starten'),
                  ),
                  DropdownMenuItem(
                    value: 'restart_ngrok',
                    child: Text('Internetzugriff neu starten'),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => action = value ?? 'backup'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    final response = await widget.client.post(
      'scheduled-tasks',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name.text,
        'schedule': time.text,
        'action': action,
      }),
    );
    if (response.statusCode == 200) await load();
  }

  Future<void> dockerAction(Map container, String action) async {
    final name =
        container['Names']?.toString() ?? container['ID']?.toString() ?? '';
    if (name.isEmpty) return;
    final response = await widget.client.post(
      'docker/containers/action',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'container': name, 'action': action}),
      timeout: const Duration(seconds: 40),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          response.statusCode == 200
              ? 'Docker-Aktion ausgeführt.'
              : widget.client.responseException(response).toString(),
        ),
      ),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MetricCard(
            icon: Icons.storage_rounded,
            title: 'Speicheranalyse',
            value: '${storage['file_count'] ?? 0} Dateien',
            subtitle:
                '${((storage['total_bytes'] as num? ?? 0) / 1024 / 1024 / 1024).toStringAsFixed(2)} GB belegt · ${(storage['duplicates'] as List?)?.length ?? 0} Duplikatgruppen',
          ),
          _MetricCard(
            icon: Icons.router_rounded,
            title: 'Netzwerkgeräte',
            value: '${devices.length} erkannt',
            subtitle: 'Aus der lokalen Nachbartabelle',
          ),
          _MetricCard(
            icon: Icons.view_in_ar_rounded,
            title: 'Docker',
            value: '${containers.length} Container',
            subtitle: containers.isEmpty
                ? 'Noch keine Container vorhanden'
                : 'Containerverwaltung bereit',
          ),
          ...containers.map(
            (container) => Card(
              child: ListTile(
                leading: const Icon(Icons.view_in_ar_rounded),
                title: Text(
                  container['Names']?.toString() ??
                      container['ID']?.toString() ??
                      'Container',
                ),
                subtitle: Text(
                  '${container['Image'] ?? ''} · ${container['Status'] ?? ''}',
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Docker-Aktion',
                  onSelected: (action) => dockerAction(container, action),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'start', child: Text('Starten')),
                    PopupMenuItem(value: 'stop', child: Text('Stoppen')),
                    PopupMenuItem(value: 'restart', child: Text('Neustarten')),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Geplante Aufgaben',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              FilledButton.icon(
                onPressed: addTask,
                icon: const Icon(Icons.add_alarm_rounded),
                label: const Text('Planen'),
              ),
            ],
          ),
          ...tasks.map(
            (task) => ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: Text(task['name']?.toString() ?? ''),
              subtitle: Text(
                '${task['schedule'] ?? ''} · ${task['action'] ?? ''}',
              ),
              trailing: IconButton(
                onPressed: () async {
                  await widget.client.delete('scheduled-tasks/${task['id']}');
                  await load();
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Letzte Aktivitäten',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          ...events
              .take(20)
              .map(
                (event) => ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: Text(event['action']?.toString() ?? ''),
                  subtitle: Text(
                    '${event['username'] ?? ''} · ${event['target'] ?? ''}',
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon, size: 34),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
  );
}

class _EmptyPane extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyPane({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _ErrorPane extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorPane({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Nochmal'),
        ),
      ],
    ),
  );
}
