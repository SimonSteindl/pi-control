import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

import 'changelog_view.dart';
import 'backup_view.dart';

import 'package:http/http.dart' as http;

import 'auth.dart';
import 'file_manager_view.dart';
import 'feature_hub_view.dart';
import 'login_views.dart';
import 'layout_system.dart';
import 'terminal_view.dart';
import 'user_admin_view.dart';
import 'weather_view.dart';
import 'widget_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializePiControlWidgetUpdates();
  } catch (_) {
    // Ein Hintergrund-Widget darf den App-Start nicht verhindern.
  }
  runApp(const PiControlApp());
}

class PiControlApp extends StatefulWidget {
  const PiControlApp({super.key});

  @override
  State<PiControlApp> createState() => _PiControlAppState();
}

class _PiControlAppState extends State<PiControlApp> {
  Color accentColor = const Color(0xFFFF7900);
  PiLayoutStyle layoutStyle = PiLayoutStyle.commandCenter;
  final PiApiClient client = PiApiClient();
  AuthSession? session;
  bool restoringSession = true;
  Locale appLocale = const Locale('de');

  @override
  void initState() {
    super.initState();
    restoreSession();
    loadLanguage();
    loadAppearance();
  }

  Future<void> loadAppearance() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      layoutStyle = piLayoutStyleFromKey(
        preferences.getString('pi_control_layout_style'),
      );
      final accentValue = preferences.getInt('pi_control_accent_color');
      if (accentValue != null) accentColor = Color(accentValue);
    });
  }

  Future<void> changeLayoutStyle(PiLayoutStyle style) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('pi_control_layout_style', style.storageKey);
    if (mounted) setState(() => layoutStyle = style);
  }

  Future<void> loadLanguage() async {
    final preferences = await SharedPreferences.getInstance();
    final code = preferences.getString('pi_control_language') ?? 'de';
    if (mounted) setState(() => appLocale = Locale(code));
  }

  Future<void> changeLanguage(Locale locale) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('pi_control_language', locale.languageCode);
    if (mounted) setState(() => appLocale = locale);
  }

  Future<void> restoreSession() async {
    AuthSession? restored;
    try {
      await client.initialize();
      restored = await client.restoreSession();
    } catch (_) {
      // Bei Netzwerkfehlern wird der normale Login angezeigt.
    }

    if (!mounted) return;
    setState(() {
      session = restored;
      restoringSession = false;
    });
  }

  Future<void> changeAccent(Color color) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt('pi_control_accent_color', color.toARGB32());
    if (mounted) setState(() => accentColor = color);
  }

  Future<void> logout() async {
    await client.logout();
    if (!mounted) return;
    setState(() {
      session = null;
    });
  }

  @override
  void dispose() {
    client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pi Control',
      locale: appLocale,
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildPiLayoutTheme(
        ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: accentColor,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0A0F1C),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0A0F1C),
            surfaceTintColor: Colors.transparent,
            centerTitle: false,
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: const Color(0xFF121A2A),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: const Color(0xFF0E1524),
            indicatorColor: accentColor.withValues(alpha: 0.22),
            labelTextStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        layoutStyle,
        accentColor,
      ),
      home: restoringSession
          ? const _SessionRestoreScreen()
          : session == null
          ? LoginScreen(
              client: client,
              accentColor: accentColor,
              onLoggedIn: (value) {
                setState(() {
                  session = value;
                });
              },
            )
          : session!.mustChangePassword
          ? PasswordChangeScreen(
              client: client,
              session: session!,
              onChanged: (value) {
                setState(() {
                  session = value;
                });
              },
              onLogout: logout,
            )
          : DashboardPage(
              accentColor: accentColor,
              onAccentChanged: changeAccent,
              client: client,
              session: session!,
              onSessionUpdated: (value) {
                setState(() {
                  session = value;
                });
              },
              onLogout: logout,
              onLanguageChanged: changeLanguage,
              layoutStyle: layoutStyle,
              onLayoutChanged: changeLayoutStyle,
            ),
    );
  }
}

class _SessionRestoreScreen extends StatelessWidget {
  const _SessionRestoreScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.developer_board_rounded, size: 52),
            SizedBox(height: 18),
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('Anmeldung wird wiederhergestellt …'),
          ],
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  final Color accentColor;
  final ValueChanged<Color> onAccentChanged;
  final PiApiClient client;
  final AuthSession session;
  final ValueChanged<AuthSession> onSessionUpdated;
  final VoidCallback onLogout;
  final ValueChanged<Locale> onLanguageChanged;
  final PiLayoutStyle layoutStyle;
  final ValueChanged<PiLayoutStyle> onLayoutChanged;

  const DashboardPage({
    super.key,
    required this.accentColor,
    required this.onAccentChanged,
    required this.client,
    required this.session,
    required this.onSessionUpdated,
    required this.onLogout,
    required this.onLanguageChanged,
    required this.layoutStyle,
    required this.onLayoutChanged,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  String get activeConnectionName => widget.client.connectionName;

  Map<String, dynamic>? data;
  bool loading = true;
  bool connected = false;
  bool maintenance = false;
  String? error;

  Timer? refreshTimer;
  Timer? historyTimer;
  bool _dataRequestInFlight = false;
  bool _historyRequestInFlight = false;
  bool _benchmarkHistoryRequestInFlight = false;
  DateTime? _lastDashboardCacheWrite;

  int? latencyMs;
  DateTime? lastUpdated;
  double? sessionMaxTemperature;

  bool benchmarkRunning = false;
  Map<String, dynamic>? benchmarkResult;
  List<Map<String, dynamic>> benchmarkHistory = [];

  List<HistoryPoint> history = [];
  ImageProvider? _profilePicture;
  int selectedPageIndex = 0;
  bool showUpdateNotice = true;
  String? availableAppVersion;
  String? androidUpdatePath;
  List<String> dashboardShortcuts = ['files', 'more', 'backups', 'search'];

  static const clientAppVersion = '2.4.0';

  Future<http.Response> _apiGet(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final response = await widget.client.get(
      path,
      headers: headers,
      timeout: timeout,
    );
    if (response.statusCode == 401) widget.onLogout();
    return response;
  }

  Future<http.Response> _apiPost(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final response = await widget.client.post(
      path,
      headers: headers,
      body: body,
      timeout: timeout,
    );
    if (response.statusCode == 401) widget.onLogout();
    return response;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    checkAppVersion();
    loadCachedDashboard();
    loadDashboardLayout();
    loadProfilePicture();
    if (widget.session.can('dashboard_view')) {
      loadAll();
      _startRefreshTimers();
    } else {
      loading = false;
    }
  }

  void _startRefreshTimers() {
    refreshTimer?.cancel();
    historyTimer?.cancel();
    final isHandheld =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final dashboardRefreshInterval = Duration(seconds: isHandheld ? 15 : 5);
    refreshTimer = Timer.periodic(dashboardRefreshInterval, (_) {
      if (selectedPageIndex == 0) loadData();
    });
    historyTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (selectedPageIndex == 0) loadHistory();
    });
  }

  void _stopRefreshTimers() {
    refreshTimer?.cancel();
    historyTimer?.cancel();
    refreshTimer = null;
    historyTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.session.can('dashboard_view')) return;
    if (state == AppLifecycleState.resumed) {
      _startRefreshTimers();
      if (selectedPageIndex == 0) {
        loadData();
        loadHistory();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopRefreshTimers();
    }
  }

  bool _isNewerVersion(String candidate, String current) {
    final candidateParts = candidate
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final currentParts = current
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final length = candidateParts.length > currentParts.length
        ? candidateParts.length
        : currentParts.length;
    for (var index = 0; index < length; index++) {
      final candidatePart =
          index < candidateParts.length ? candidateParts[index] : 0;
      final currentPart =
          index < currentParts.length ? currentParts[index] : 0;
      if (candidatePart != currentPart) return candidatePart > currentPart;
    }
    return false;
  }

  Future<void> checkAppVersion() async {
    try {
      final response = await _apiGet(
        'app-version',
        timeout: const Duration(seconds: 8),
      );
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return;
      final latest = decoded['latest_version']?.toString();
      if (latest == null ||
          !_isNewerVersion(latest, clientAppVersion) ||
          !mounted) {
        return;
      }
      setState(() {
        availableAppVersion = latest;
        androidUpdatePath = decoded['android_download']?.toString();
      });
    } catch (_) {
      // Die Updateprüfung darf die normale App-Nutzung nicht blockieren.
    }
  }

  Future<void> openAndroidUpdate() async {
    final path = androidUpdatePath;
    if (path == null) return;
    final base = Uri.parse(widget.client.activeBase);
    final url = Uri.parse('${base.origin}$path');
    await launchUrl(url, mode: LaunchMode.platformDefault);
  }

  Future<void> showGlobalSearch() async {
    final controller = TextEditingController();
    var results = <Map<String, dynamic>>[];
    var searching = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> search() async {
            if (controller.text.trim().length < 2) return;
            setDialogState(() => searching = true);
            final response = await _apiGet(
              'global-search?q=${Uri.encodeQueryComponent(controller.text.trim())}',
              timeout: const Duration(seconds: 30),
            );
            final raw = widget.client.decodeObject(response)['results'];
            setDialogState(() {
              results = raw is List
                  ? raw
                        .whereType<Map>()
                        .map((item) => Map<String, dynamic>.from(item))
                        .toList()
                  : [];
              searching = false;
            });
          }

          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      onSubmitted: (_) => search(),
                      decoration: InputDecoration(
                        labelText: 'Alles durchsuchen',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          onPressed: search,
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                      ),
                    ),
                  ),
                  if (searching) const LinearProgressIndicator(),
                  Expanded(
                    child: results.isEmpty
                        ? const Center(
                            child: Text('Dateien, Notizen und Benutzer finden'),
                          )
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final item = results[index];
                              return ListTile(
                                leading: const Icon(Icons.search_rounded),
                                title: Text(item['title']?.toString() ?? ''),
                                subtitle: Text(
                                  item['subtitle']?.toString() ?? '',
                                ),
                                trailing: Text(item['type']?.toString() ?? ''),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopRefreshTimers();
    super.dispose();
  }

  Future<void> loadAll() async {
    await Future.wait([loadData(), loadHistory(), loadBenchmarkHistory()]);
  }

  Future<void> loadCachedDashboard() async {
    final preferences = await SharedPreferences.getInstance();
    final cached = preferences.getString('pi_control_cached_dashboard');
    if (cached == null || !mounted || data != null) return;
    try {
      final decoded = jsonDecode(cached);
      if (decoded is Map) {
        setState(() {
          data = Map<String, dynamic>.from(decoded);
          loading = false;
        });
      }
    } catch (_) {}
  }

  Future<void> loadDashboardLayout() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getStringList('pi_control_dashboard_shortcuts');
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() => dashboardShortcuts = saved);
    }
  }

  String get _profilePictureKey =>
      'pi_control_profile_picture_${widget.session.username.toLowerCase()}';

  Future<void> loadProfilePicture() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_profilePictureKey);
    ImageProvider? picture;
    try {
      if (saved != null) picture = MemoryImage(base64Decode(saved));
    } catch (_) {
      await preferences.remove(_profilePictureKey);
    }
    if (mounted) setState(() => _profilePicture = picture);
  }

  Future<void> chooseProfilePicture() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 82,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (bytes.length > 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bitte ein kleineres Bild auswählen (max. 1 MB).'),
          ),
        );
        return;
      }

      final encoded = base64Encode(bytes);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_profilePictureKey, encoded);
      if (mounted) setState(() => _profilePicture = MemoryImage(bytes));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profilbild konnte nicht geladen werden: $error'),
        ),
      );
    }
  }

  Future<void> removeProfilePicture() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_profilePictureKey);
    if (mounted) setState(() => _profilePicture = null);
  }

  Future<void> showLayoutPicker() async {
    final accentOptions = <AccentOption>[
      const AccentOption('Blau', Colors.blue),
      const AccentOption('Grün', Colors.green),
      const AccentOption('Lila', Colors.deepPurple),
      const AccentOption('Orange', Colors.orange),
      const AccentOption('Rot', Colors.red),
      const AccentOption('Türkis', Colors.teal),
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Design Studio',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              const Text(
                'Wähle Aufbau und Farbe. Beides bleibt auf diesem Gerät gespeichert.',
              ),
              const SizedBox(height: 18),
              for (final style in PiLayoutStyle.values) ...[
                PiLayoutOptionCard(
                  style: style,
                  selected: widget.layoutStyle == style,
                  onTap: () async {
                    widget.onLayoutChanged(style);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 10),
              Text(
                'Akzentfarbe',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final option in accentOptions)
                    ChoiceChip(
                      selected: widget.accentColor == option.color,
                      avatar: CircleAvatar(backgroundColor: option.color),
                      label: Text(option.name),
                      onSelected: (_) => widget.onAccentChanged(option.color),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> customizeDashboard() async {
    final working = List<String>.from(dashboardShortcuts);
    final saved = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Dashboard anordnen'),
          content: SizedBox(
            width: 440,
            height: 360,
            child: ReorderableListView(
              onReorderItem: (oldIndex, newIndex) {
                setDialogState(() {
                  working.insert(newIndex, working.removeAt(oldIndex));
                });
              },
              children: [
                for (final key in working)
                  ListTile(
                    key: ValueKey(key),
                    leading: const Icon(Icons.drag_handle_rounded),
                    title: Text(switch (key) {
                      'files' => 'Dateien',
                      'more' => 'Medien und Werkzeuge',
                      'backups' => 'Backups',
                      _ => 'Globale Suche',
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context, working),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (saved == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList('pi_control_dashboard_shortcuts', saved);
    if (mounted) setState(() => dashboardShortcuts = saved);
  }

  Future<void> loadData() async {
    if (_dataRequestInFlight) return;
    _dataRequestInFlight = true;
    final stopwatch = Stopwatch()..start();

    try {
      final response = await _apiGet('info');

      stopwatch.stop();

      if (response.statusCode != 200) {
        final responseData = widget.client.decodeObject(response);
        if (responseData['code'] == 'maintenance') {
          if (!mounted) return;
          setState(() {
            maintenance = true;
            connected = false;
            loading = false;
            error = null;
          });
          return;
        }
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw Exception('Ungültige API-Antwort');
      }

      final result = Map<String, dynamic>.from(decoded);

      if (!mounted) return;

      final temperature = asDouble(result['temperature']);

      setState(() {
        data = result;
        connected = true;
        maintenance = false;
        loading = false;
        error = null;
        latencyMs = stopwatch.elapsedMilliseconds;
        lastUpdated = DateTime.now();

        if (temperature != null) {
          if (sessionMaxTemperature == null ||
              temperature > sessionMaxTemperature!) {
            sessionMaxTemperature = temperature;
          }

          if (history.isEmpty) {
            history.add(
              HistoryPoint(
                timestamp: DateTime.now(),
                cpu: asDouble(result['cpu']?['usage']),
                ram: asDouble(result['ram']?['percent']),
                temperature: temperature,
              ),
            );

            if (history.length > 12) {
              history.removeAt(0);
            }
          }
        }
      });

      unawaited(_cacheDashboard(result));
      unawaited(updatePiControlWidgets(result, status: 'ONLINE'));
    } catch (e) {
      stopwatch.stop();

      if (!mounted) return;

      setState(() {
        connected = false;
        loading = false;
        latencyMs = null;
        error = e.toString();
      });
      unawaited(updatePiControlWidgets(data ?? const {}, status: 'OFFLINE'));
    } finally {
      _dataRequestInFlight = false;
    }
  }

  Future<void> _cacheDashboard(Map<String, dynamic> result) async {
    final now = DateTime.now();
    final previous = _lastDashboardCacheWrite;
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 30)) {
      return;
    }
    _lastDashboardCacheWrite = now;

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'pi_control_cached_dashboard',
        jsonEncode(result),
      );
    } catch (_) {
      // Ein Cache-Fehler darf den Live-Status nicht als offline markieren.
    }
  }

  Future<void> loadHistory() async {
    if (_historyRequestInFlight) return;
    _historyRequestInFlight = true;
    try {
      final response = await _apiGet('history');

      if (response.statusCode != 200) {
        return;
      }

      final decoded = jsonDecode(response.body);
      final rawHistory = decoded is Map ? decoded['history'] : null;

      if (rawHistory is! List) return;

      final parsed = <HistoryPoint>[];

      for (final item in rawHistory) {
        if (item is Map) {
          final timestamp = item['ts'];
          if (timestamp is num) {
            parsed.add(
              HistoryPoint(
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                  timestamp.toInt() * 1000,
                ),
                cpu: asDouble(item['cpu']),
                ram: asDouble(item['ram']),
                temperature: asDouble(item['temperature']),
              ),
            );
          }
        }
      }

      if (!mounted) return;

      setState(() {
        history = parsed;
      });
    } catch (_) {
      // Die App bleibt auch mit einem älteren Backend benutzbar.
    } finally {
      _historyRequestInFlight = false;
    }
  }

  Future<void> loadBenchmarkHistory() async {
    if (_benchmarkHistoryRequestInFlight) return;
    _benchmarkHistoryRequestInFlight = true;
    try {
      final response = await _apiGet('benchmark/history');

      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      final raw = decoded is Map ? decoded['history'] : null;

      if (raw is! List) return;

      final parsed = <Map<String, dynamic>>[];

      for (final item in raw) {
        if (item is Map) {
          parsed.add(Map<String, dynamic>.from(item));
        }
      }

      if (!mounted) return;

      setState(() {
        benchmarkHistory = parsed;
      });
    } catch (_) {
      // App bleibt mit einem älteren Backend benutzbar.
    } finally {
      _benchmarkHistoryRequestInFlight = false;
    }
  }

  Future<bool> confirmCommand(String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: const Text(
            'Möchtest du diese Systemaktion wirklich ausführen?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Ausführen'),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> sendProtectedCommand({
    required String path,
    required String title,
    required String successText,
  }) async {
    if (!await confirmCommand(title)) return;

    try {
      final response = await _apiPost(
        path,
        headers: const {'Content-Type': 'application/json'},
        body: '{}',
      );

      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);

      if (response.statusCode != 200) {
        final message = decoded is Map ? decoded['error']?.toString() : null;
        throw Exception(message ?? 'HTTP ${response.statusCode}');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successText)));

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          loadData();
        }
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> reboot() async {
    await sendProtectedCommand(
      path: 'reboot',
      title: 'Raspberry Pi neu starten',
      successText: 'Raspberry Pi wird neu gestartet...',
    );
  }

  Future<void> restartService(String service, String label) async {
    await sendProtectedCommand(
      path: 'service/$service/restart',
      title: '$label neu starten',
      successText: '$label wird neu gestartet...',
    );
  }

  Future<void> runCpuBenchmark() async {
    if (!mounted) return;

    setState(() {
      benchmarkRunning = true;
    });

    try {
      final response = await _apiPost(
        'benchmark/cpu',
        headers: const {'Content-Type': 'application/json'},
        body: '{}',
        timeout: const Duration(seconds: 15),
      );

      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);

      if (response.statusCode != 200) {
        final message = decoded is Map ? decoded['error']?.toString() : null;

        throw Exception(message ?? 'HTTP ${response.statusCode}');
      }

      if (!mounted) return;

      setState(() {
        benchmarkResult = Map<String, dynamic>.from(decoded as Map);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CPU-Benchmark abgeschlossen.')),
      );

      await Future.wait([loadData(), loadBenchmarkHistory()]);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Benchmark-Fehler: $e')));
    } finally {
      if (mounted) {
        setState(() {
          benchmarkRunning = false;
        });
      }
    }
  }

  int calculateHealthScore() {
    if (!connected) return 0;

    int score = 100;

    final temperature = asDouble(data?['temperature']);
    final cpu = asDouble(data?['cpu']?['usage']);
    final ram = asDouble(data?['ram']?['percent']);
    final sd = asDouble(data?['sd']?['percent']);
    final usb = asDouble(data?['usb']?['percent']);

    if (temperature != null) {
      if (temperature >= 80) {
        score -= 35;
      } else if (temperature >= 70) {
        score -= 18;
      } else if (temperature >= 60) {
        score -= 5;
      }
    }

    if (ram != null) {
      if (ram >= 95) {
        score -= 18;
      } else if (ram >= 90) {
        score -= 12;
      } else if (ram >= 80) {
        score -= 5;
      }
    }

    if (sd != null) {
      if (sd >= 95) {
        score -= 18;
      } else if (sd >= 90) {
        score -= 12;
      } else if (sd >= 80) {
        score -= 5;
      }
    }

    if (usb != null) {
      if (usb >= 95) {
        score -= 18;
      } else if (usb >= 90) {
        score -= 12;
      } else if (usb >= 80) {
        score -= 5;
      }
    }

    if (data?['samba'] != true) {
      score -= 10;
    }

    if (data?['tailscale']?['online'] != true) {
      score -= 10;
    }

    if (latencyMs != null) {
      if (latencyMs! >= 500) {
        score -= 10;
      } else if (latencyMs! >= 150) {
        score -= 4;
      }
    }

    if (cpu != null && cpu >= 98) {
      score -= 2;
    }

    return score.clamp(0, 100).toInt();
  }

  List<AlertItem> get alerts {
    final backendAlerts = data?['alerts'];

    if (backendAlerts is List) {
      return backendAlerts
          .whereType<Map>()
          .map(
            (item) => AlertItem(
              key: item['key']?.toString() ?? '',
              level: item['level']?.toString() ?? 'warning',
              title: item['title']?.toString() ?? 'Warnung',
              message: item['message']?.toString() ?? '',
            ),
          )
          .toList();
    }

    return buildFallbackAlerts();
  }

  List<AlertItem> buildFallbackAlerts() {
    final result = <AlertItem>[];

    if (!connected) {
      result.add(
        const AlertItem(
          key: 'offline',
          level: 'critical',
          title: 'Raspberry Pi offline',
          message: 'Die App kann den Pi nicht erreichen.',
        ),
      );
      return result;
    }

    final temperature = asDouble(data?['temperature']);
    final ramPercent = asDouble(data?['ram']?['percent']);
    final sdPercent = asDouble(data?['sd']?['percent']);
    final usbPercent = asDouble(data?['usb']?['percent']);
    final usbFree = asDouble(data?['usb']?['free_gb']);

    if (temperature != null && temperature >= 80) {
      result.add(
        AlertItem(
          key: 'temperature',
          level: 'critical',
          title: 'Temperatur kritisch',
          message:
              '${temperature.toStringAsFixed(1)} °C – der Pi ist sehr heiß.',
        ),
      );
    } else if (temperature != null && temperature >= 70) {
      result.add(
        AlertItem(
          key: 'temperature',
          level: 'warning',
          title: 'Temperatur erhöht',
          message: '${temperature.toStringAsFixed(1)} °C – Kühlung prüfen.',
        ),
      );
    }

    if (ramPercent != null && ramPercent >= 90) {
      result.add(
        AlertItem(
          key: 'ram',
          level: 'warning',
          title: 'RAM fast voll',
          message: '${ramPercent.toStringAsFixed(0)} % RAM belegt.',
        ),
      );
    }

    if (sdPercent != null && sdPercent >= 90) {
      result.add(
        AlertItem(
          key: 'sd',
          level: 'critical',
          title: 'SD-Karte fast voll',
          message: '${sdPercent.toStringAsFixed(0)} % Speicher belegt.',
        ),
      );
    }

    if (usbPercent != null && usbPercent >= 90) {
      result.add(
        AlertItem(
          key: 'usb',
          level: 'critical',
          title: 'NAS fast voll',
          message: '${usbPercent.toStringAsFixed(0)} % Speicher belegt.',
        ),
      );
    } else if (usbFree != null && usbFree < 10) {
      result.add(
        AlertItem(
          key: 'usb',
          level: 'warning',
          title: 'NAS-Speicher wird knapp',
          message: '${usbFree.toStringAsFixed(1)} GB sind noch frei.',
        ),
      );
    }

    if (data?['samba'] != true) {
      result.add(
        const AlertItem(
          key: 'samba',
          level: 'warning',
          title: 'Samba offline',
          message: 'Der NAS-Dateidienst läuft nicht.',
        ),
      );
    }

    final tailscale = data?['tailscale'];
    if (tailscale?['online'] != true) {
      result.add(
        const AlertItem(
          key: 'tailscale',
          level: 'warning',
          title: 'Tailscale offline',
          message: 'Der Fernzugriff ist nicht verbunden.',
        ),
      );
    }

    return result;
  }

  List<double> historyValues(double? Function(HistoryPoint point) getter) {
    final result = <double>[];

    for (final point in history) {
      final value = getter(point);
      if (value != null) {
        result.add(value);
      }
    }

    return result;
  }

  String formatNumber(dynamic value) {
    if (value == null) return '—';

    if (value is num) {
      return value % 1 == 0
          ? value.toInt().toString()
          : value.toStringAsFixed(1);
    }

    return value.toString();
  }

  String formatLastUpdated() {
    final date = lastUpdated;
    if (date == null) return 'Noch nicht aktualisiert';

    return 'Zuletzt ${twoDigits(date.hour)}:${twoDigits(date.minute)}:${twoDigits(date.second)}';
  }

  Future<void> changeOwnPassword() async {
    final updated = await showDialog<AuthSession>(
      context: context,
      builder: (context) =>
          PasswordChangeDialog(client: widget.client, session: widget.session),
    );

    if (updated == null || !mounted) return;
    widget.onSessionUpdated(updated);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Passwort wurde geändert.')));
  }

  @override
  Widget build(BuildContext context) {
    final layoutStyle = widget.layoutStyle;
    final english = Localizations.localeOf(context).languageCode == 'en';
    final cpu = data?['cpu'];
    final ram = data?['ram'];
    final sd = data?['sd'];
    final usb = data?['usb'];
    final tailscale = data?['tailscale'];
    final system = data?['system'];

    final cpuUsage = asDouble(cpu?['usage']);
    final cpuFrequency = asDouble(cpu?['frequency_mhz']);
    final temperature = asDouble(data?['temperature']);

    final ramUsed = asDouble(ram?['used_mb']);
    final ramTotal = asDouble(ram?['total_mb']);
    final ramPercent = asDouble(ram?['percent']);

    final sdUsed = asDouble(sd?['used_gb']);
    final sdTotal = asDouble(sd?['total_gb']);
    final sdFree = asDouble(sd?['free_gb']);
    final sdPercent = asDouble(sd?['percent']);

    final usbUsed = asDouble(usb?['used_gb']);
    final usbFree = asDouble(usb?['free_gb']);
    final usbTotal = asDouble(usb?['total_gb']);
    final usbPercent = asDouble(usb?['percent']);

    final sambaOnline = data?['samba'] == true;
    final tailscaleOnline = tailscale?['online'] == true;

    final cpuHistory = historyValues((point) => point.cpu);
    final ramHistory = historyValues((point) => point.ram);
    final temperatureHistory = historyValues((point) => point.temperature);

    final max24hTemperature = temperatureHistory.isEmpty
        ? null
        : temperatureHistory.reduce((a, b) => a > b ? a : b);

    final alertItems = alerts;
    final healthScore = calculateHealthScore();

    final currentBenchmark =
        benchmarkResult ??
        (data?['benchmark'] is Map
            ? Map<String, dynamic>.from(data?['benchmark'] as Map)
            : null);

    final pageKeys = <String>[
      'dashboard',
      'weather',
      if (widget.session.can('files_view')) 'files',
      if (widget.session.can('terminal_access')) 'terminal',
      if (widget.session.can('users_manage')) 'users',
      'more',
    ];
    final currentPageIndex = selectedPageIndex.clamp(0, pageKeys.length - 1);
    final currentPage = pageKeys[currentPageIndex];
    final narrowScreen = MediaQuery.sizeOf(context).width < 600;
    final pageTitle = switch (currentPage) {
      'weather' => english ? 'Flight weather' : 'Flugwetter',
      'files' => english ? 'Files' : 'Dateimanager',
      'terminal' => 'Terminal',
      'users' => english ? 'Admin panel' : 'Admin-Panel',
      'more' => english ? 'More' : 'Mehr',
      _ => english ? "Stoney's Raspberry Pi" : 'Stoneys Raspberry Pi',
    };

    final navigationItems = [
      for (final key in pageKeys)
        switch (key) {
          'dashboard' => PiNavigationItem(
            keyName: key,
            label: english ? 'Overview' : 'Übersicht',
            icon: Icons.space_dashboard_outlined,
            selectedIcon: Icons.space_dashboard_rounded,
          ),
          'weather' => PiNavigationItem(
            keyName: key,
            label: english ? 'Weather' : 'Flugwetter',
            icon: Icons.flight_outlined,
            selectedIcon: Icons.flight_rounded,
          ),
          'files' => PiNavigationItem(
            keyName: key,
            label: english ? 'Files' : 'Dateien',
            icon: Icons.folder_outlined,
            selectedIcon: Icons.folder_rounded,
          ),
          'terminal' => PiNavigationItem(
            keyName: key,
            label: 'Terminal',
            icon: Icons.terminal_outlined,
            selectedIcon: Icons.terminal_rounded,
          ),
          'users' => PiNavigationItem(
            keyName: key,
            label: 'Admin',
            icon: Icons.admin_panel_settings_outlined,
            selectedIcon: Icons.admin_panel_settings_rounded,
          ),
          _ => PiNavigationItem(
            keyName: key,
            label: english ? 'More' : 'Mehr',
            icon: Icons.apps_outlined,
            selectedIcon: Icons.apps_rounded,
          ),
        },
    ];

    void selectPage(int index) {
      setState(() => selectedPageIndex = index);
      if (index == 0) {
        loadData();
        loadHistory();
      }
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: narrowScreen
            ? 56
            : layoutStyle == PiLayoutStyle.compact
            ? 58
            : 70,
        flexibleSpace:
            layoutStyle == PiLayoutStyle.aurora ||
                layoutStyle == PiLayoutStyle.commandCenter
            ? DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.accentColor.withValues(
                        alpha: layoutStyle == PiLayoutStyle.commandCenter
                            ? 0.11
                            : 0.20,
                      ),
                      const Color(0xFF0B1220),
                      const Color(0xFF080D16),
                    ],
                  ),
                ),
              )
            : null,
        title: Text(
          pageTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: showGlobalSearch,
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Globale Suche',
          ),
          if (narrowScreen)
            PopupMenuButton<String>(
              tooltip: 'Ansicht anpassen',
              icon: const Icon(Icons.tune_rounded),
              onSelected: (action) {
                if (action == 'design') showLayoutPicker();
                if (action == 'dashboard') customizeDashboard();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'design',
                  child: ListTile(
                    leading: Icon(Icons.design_services_rounded),
                    title: Text('Design Studio'),
                  ),
                ),
                if (currentPage == 'dashboard')
                  const PopupMenuItem(
                    value: 'dashboard',
                    child: ListTile(
                      leading: Icon(Icons.dashboard_customize_outlined),
                      title: Text('Übersicht anordnen'),
                    ),
                  ),
              ],
            )
          else ...[
            IconButton(
              onPressed: showLayoutPicker,
              icon: const Icon(Icons.design_services_rounded),
              tooltip: 'Design Studio',
            ),
            if (currentPage == 'dashboard')
              IconButton(
                onPressed: customizeDashboard,
                icon: const Icon(Icons.dashboard_customize_outlined),
                tooltip: 'Dashboard anordnen',
              ),
          ],
          if (currentPage == 'dashboard')
            IconButton(
              onPressed: loadAll,
              icon: const Icon(Icons.refresh),
              tooltip: 'Aktualisieren',
            ),
          PopupMenuButton<String>(
            tooltip: 'Konto',
            icon: CircleAvatar(
              radius: 16,
              backgroundImage: _profilePicture,
              child: _profilePicture == null
                  ? Text(
                      widget.session.displayName.isEmpty
                          ? '?'
                          : widget.session.displayName[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    )
                  : null,
            ),
            onSelected: (action) {
              if (action == 'changelog') {
                showPiControlChangelog(context);
              } else if (action == 'profile-picture') {
                chooseProfilePicture();
              } else if (action == 'profile-picture-remove') {
                removeProfilePicture();
              } else if (action == 'backups') {
                showBackupManager(context, widget.client);
              } else if (action == 'password') {
                changeOwnPassword();
              } else if (action == 'language') {
                showDialog<void>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    title: const Text('Sprache / Language'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () {
                          widget.onLanguageChanged(const Locale('de'));
                          Navigator.pop(context);
                        },
                        child: const ListTile(
                          leading: Text('🇩🇪', style: TextStyle(fontSize: 24)),
                          title: Text('Deutsch'),
                        ),
                      ),
                      SimpleDialogOption(
                        onPressed: () {
                          widget.onLanguageChanged(const Locale('en'));
                          Navigator.pop(context);
                        },
                        child: const ListTile(
                          leading: Text('🇬🇧', style: TextStyle(fontSize: 24)),
                          title: Text('English'),
                        ),
                      ),
                    ],
                  ),
                );
              } else if (action == 'logout') {
                widget.onLogout();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.session.displayName),
                  subtitle: Text('@${widget.session.username}'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'profile-picture',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.add_a_photo_outlined),
                  title: Text('Profilbild auswählen'),
                  subtitle: Text('Aus deiner Galerie · nur auf diesem Gerät'),
                ),
              ),
              if (_profilePicture != null)
                const PopupMenuItem(
                  value: 'profile-picture-remove',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.person_remove_outlined),
                    title: Text('Profilbild entfernen'),
                  ),
                ),
              const PopupMenuDivider(),
              if (widget.session.isAdmin)
                const PopupMenuItem(
                  value: 'backups',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.backup_outlined),
                    title: Text('Backups'),
                    subtitle: Text('Automatisch und manuell'),
                  ),
                ),
              if (widget.session.isAdmin) const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'changelog',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.auto_awesome_outlined),
                  title: Text('Was ist neu?'),
                  subtitle: Text('Changelog'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'language',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.language_rounded),
                  title: Text('Sprache / Language'),
                ),
              ),
              const PopupMenuItem(
                value: 'password',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.password_rounded),
                  title: Text('Passwort ändern'),
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Abmelden'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: PiPageSurface(
        child: maintenance
            ? const _MaintenanceView()
            : PiLayoutFrame(
                style: layoutStyle,
                selectedIndex: currentPageIndex,
                items: navigationItems,
                onSelected: selectPage,
                child: IndexedStack(
                  index: currentPageIndex,
                  children: [
                    PiDashboardList(
                      onRefresh: loadAll,
                      style: layoutStyle,
                      children: [
                        DashboardHeroCard(
                          style: layoutStyle,
                          connected: connected,
                          loading: loading,
                          hostname:
                              data?['hostname']?.toString() ?? 'Raspberry Pi',
                          uptime:
                              data?['uptime']?['formatted']?.toString() ?? '—',
                          temperature: temperature,
                          healthScore: healthScore,
                          accentColor: widget.accentColor,
                          onOpenFiles: widget.session.can('files_view')
                              ? () {
                                  setState(() {
                                    selectedPageIndex = pageKeys.indexOf(
                                      'files',
                                    );
                                  });
                                }
                              : null,
                        ),

                        const SizedBox(height: 12),

                        PiQuickActions(
                          style: layoutStyle,
                          keys: dashboardShortcuts,
                          onPressed: (key) {
                            if (key == 'files' && pageKeys.contains('files')) {
                              setState(
                                () => selectedPageIndex = pageKeys.indexOf(
                                  'files',
                                ),
                              );
                            } else if (key == 'more') {
                              setState(
                                () => selectedPageIndex = pageKeys.indexOf(
                                  'more',
                                ),
                              );
                            } else if (key == 'backups' &&
                                widget.session.isAdmin) {
                              showBackupManager(context, widget.client);
                            } else {
                              showGlobalSearch();
                            }
                          },
                        ),

                        const SizedBox(height: 12),

                        if (availableAppVersion != null && !kIsWeb) ...[
                          Card(
                            color: Theme.of(context)
                                .colorScheme
                                .tertiaryContainer,
                            child: ListTile(
                              leading: const Icon(
                                Icons.download_for_offline_rounded,
                              ),
                              title: Text(
                                'App-Update $availableAppVersion verfügbar',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                defaultTargetPlatform == TargetPlatform.android
                                    ? 'Neue APK herunterladen und installieren.'
                                    : 'Die iPhone-Version wird über TestFlight/App Store aktualisiert.',
                              ),
                              trailing:
                                  defaultTargetPlatform ==
                                      TargetPlatform.android
                                  ? FilledButton(
                                      onPressed: openAndroidUpdate,
                                      child: const Text('Herunterladen'),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (showUpdateNotice) ...[
                          Card(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            child: ListTile(
                              leading: const Icon(
                                Icons.system_update_alt_rounded,
                              ),
                              title: const Text(
                                'Pi Control 2.0.1 ist da',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: const Text(
                                'Backups, Freigabeverwaltung, Mehrfachauswahl und App-Updates sind neu.',
                              ),
                              onTap: () => showPiControlChangelog(context),
                              trailing: IconButton(
                                onPressed: () {
                                  setState(() => showUpdateNotice = false);
                                },
                                tooltip: 'Hinweis schließen',
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        StatusOverviewCard(
                          connected: connected,
                          loading: loading,
                          alerts: alertItems,
                          lastUpdated: formatLastUpdated(),
                        ),

                        if (alertItems.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          AlertsCard(alerts: alertItems),
                        ],

                        const SizedBox(height: 12),

                        HealthScoreCard(
                          score: healthScore,
                          alertCount: alertItems.length,
                        ),

                        const SizedBox(height: 20),

                        const SectionTitle(
                          icon: Icons.monitor_heart_outlined,
                          title: 'System',
                        ),

                        const SizedBox(height: 12),

                        PiSystemGrid(
                          style: layoutStyle,
                          children: [
                            SystemCard(
                              icon: Icons.memory,
                              title: 'CPU',
                              value: cpuUsage == null
                                  ? '—'
                                  : '${formatNumber(cpuUsage)} %',
                              subtitle: cpuFrequency == null
                                  ? 'Auslastung'
                                  : '${formatNumber(cpuFrequency)} MHz',
                              numericValue: cpuUsage,
                              type: SystemCardType.percent,
                              accentColor: widget.accentColor,
                            ),
                            SystemCard(
                              icon: Icons.thermostat,
                              title: 'Temperatur',
                              value: temperature == null
                                  ? '—'
                                  : '${formatNumber(temperature)} °C',
                              subtitle: 'CPU',
                              numericValue: temperature,
                              type: SystemCardType.temperature,
                              accentColor: widget.accentColor,
                            ),
                            SystemCard(
                              icon: Icons.memory,
                              title: 'RAM',
                              value: ramPercent == null
                                  ? '—'
                                  : '${formatNumber(ramPercent)} %',
                              subtitle: ramUsed == null || ramTotal == null
                                  ? 'Speicher'
                                  : '${formatNumber(ramUsed)} / ${formatNumber(ramTotal)} MB',
                              numericValue: ramPercent,
                              type: SystemCardType.percent,
                              accentColor: widget.accentColor,
                            ),
                            SystemCard(
                              icon: Icons.sd_storage,
                              title: 'SD-Karte',
                              value: sdPercent == null
                                  ? '—'
                                  : '${formatNumber(sdPercent)} %',
                              subtitle: sdUsed == null || sdTotal == null
                                  ? 'Speicher'
                                  : '${formatNumber(sdUsed)} / ${formatNumber(sdTotal)} GB',
                              numericValue: sdPercent,
                              type: SystemCardType.percent,
                              accentColor: widget.accentColor,
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        TemperatureStatsCard(
                          current: temperature,
                          sessionMax: sessionMaxTemperature,
                          max24h: max24hTemperature,
                        ),

                        const SizedBox(height: 12),

                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            leading: const Icon(Icons.analytics_outlined),
                            title: const Text(
                              'Detaillierte Systemdaten',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              'Auslastung und 24-Stunden-Verlauf',
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                child: Column(
                                  children: [
                                    DetailBar(
                                      title: 'CPU',
                                      value: cpuUsage,
                                      suffix: '%',
                                      icon: Icons.memory,
                                      color: widget.accentColor,
                                    ),
                                    const SizedBox(height: 16),
                                    DetailBar(
                                      title: 'RAM',
                                      value: ramPercent,
                                      suffix: '%',
                                      icon: Icons.memory,
                                      color: widget.accentColor,
                                    ),
                                    const SizedBox(height: 16),
                                    DetailBar(
                                      title: 'SD-Karte',
                                      value: sdPercent,
                                      suffix: '%',
                                      icon: Icons.sd_storage,
                                      color: widget.accentColor,
                                    ),
                                    const SizedBox(height: 22),
                                    LiveChartCard(
                                      title: 'CPU – 24 Stunden',
                                      values: cpuHistory,
                                      unit: '%',
                                      icon: Icons.memory,
                                      maxValue: 100,
                                      lineColor: widget.accentColor,
                                    ),
                                    const SizedBox(height: 12),
                                    LiveChartCard(
                                      title: 'RAM – 24 Stunden',
                                      values: ramHistory,
                                      unit: '%',
                                      icon: Icons.storage,
                                      maxValue: 100,
                                      lineColor: widget.accentColor,
                                    ),
                                    const SizedBox(height: 12),
                                    LiveChartCard(
                                      title: 'Temperatur – 24 Stunden',
                                      values: temperatureHistory,
                                      unit: '°C',
                                      icon: Icons.thermostat,
                                      maxValue: 100,
                                      lineColor: Colors.green,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        const SectionTitle(
                          icon: Icons.storage_outlined,
                          title: 'Speicher',
                        ),

                        const SizedBox(height: 12),

                        StorageCard(
                          title: 'NAS / USB-Stick',
                          icon: Icons.usb,
                          used: usbUsed,
                          free: usbFree,
                          total: usbTotal,
                          percent: usbPercent,
                          mounted: usb != null,
                        ),

                        const SizedBox(height: 12),

                        StorageCard(
                          title: 'SD-Karte',
                          icon: Icons.sd_storage,
                          used: sdUsed,
                          free: sdFree,
                          total: sdTotal,
                          percent: sdPercent,
                          mounted: sd != null,
                        ),

                        const SizedBox(height: 20),

                        const SectionTitle(
                          icon: Icons.network_check,
                          title: 'Netzwerk',
                        ),

                        const SizedBox(height: 12),

                        NetworkCard(
                          lanIp: data?['ip']?.toString(),
                          tailscaleIp: tailscale?['ip']?.toString(),
                          tailscaleOnline: tailscaleOnline,
                          latencyMs: latencyMs,
                          activeConnection: activeConnectionName,
                        ),

                        const SizedBox(height: 12),

                        ServiceControlCard(
                          title: 'Samba / NAS',
                          icon: Icons.folder_shared,
                          online: sambaOnline,
                          description: sambaOnline
                              ? 'Dateifreigabe läuft'
                              : 'Dateifreigabe ist gestoppt',
                          onRestart: widget.session.can('system_control')
                              ? () {
                                  restartService('samba', 'Samba');
                                }
                              : null,
                        ),

                        const SizedBox(height: 12),

                        ServiceControlCard(
                          title: 'Tailscale',
                          icon: Icons.vpn_lock,
                          online: tailscaleOnline,
                          description: tailscaleOnline
                              ? 'Fernzugriff verbunden'
                              : 'Fernzugriff nicht verbunden',
                          onRestart: widget.session.can('system_control')
                              ? () {
                                  restartService('tailscale', 'Tailscale');
                                }
                              : null,
                        ),

                        const SizedBox(height: 12),

                        ServiceControlCard(
                          title: 'Ngrok-Tunnel',
                          icon: Icons.public_rounded,
                          online: data?['system']?['ngrok'] == true,
                          description: data?['system']?['ngrok'] == true
                              ? 'Fernzugriff-Tunnel läuft'
                              : 'Fernzugriff-Tunnel ist gestoppt',
                          onRestart: widget.session.can('system_control')
                              ? () {
                                  restartService('ngrok', 'Ngrok-Tunnel');
                                }
                              : null,
                        ),

                        const SizedBox(height: 20),

                        const SectionTitle(
                          icon: Icons.speed,
                          title: 'Benchmark',
                        ),

                        const SizedBox(height: 12),

                        BenchmarkCard(
                          running: benchmarkRunning,
                          result: currentBenchmark,
                          history: benchmarkHistory,
                          onRun: widget.session.can('benchmark_run')
                              ? runCpuBenchmark
                              : null,
                        ),

                        const SizedBox(height: 20),

                        const SectionTitle(
                          icon: Icons.info_outline,
                          title: 'Systeminformationen',
                        ),

                        const SizedBox(height: 12),

                        SystemInfoCard(
                          rows: [
                            InfoRowData(
                              'Hostname',
                              data?['hostname']?.toString() ?? '—',
                            ),
                            InfoRowData(
                              'Modell',
                              system?['model']?.toString() ?? '—',
                            ),
                            InfoRowData(
                              'Betriebssystem',
                              system?['os']?.toString() ?? '—',
                            ),
                            InfoRowData(
                              'Kernel',
                              data?['kernel']?.toString() ??
                                  system?['kernel']?.toString() ??
                                  '—',
                            ),
                            InfoRowData(
                              'CPU-Takt',
                              cpuFrequency == null
                                  ? '—'
                                  : '${formatNumber(cpuFrequency)} MHz',
                            ),
                            InfoRowData(
                              'Load Average',
                              system?['load_average']?.toString() ?? '—',
                            ),
                            InfoRowData(
                              'Uptime',
                              data?['uptime']?['formatted']?.toString() ?? '—',
                            ),
                            InfoRowData(
                              'Warn-Push',
                              system?['notifications']?.toString() ?? 'ntfy',
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        if (widget.session.can('system_control')) ...[
                          const SectionTitle(
                            icon: Icons.settings_remote,
                            title: 'Steuerung',
                          ),

                          const SizedBox(height: 12),

                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: reboot,
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Raspberry Pi neu starten'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),
                        ],

                        if (error != null) ...[
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Verbindungsfehler: $error',
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        const Center(
                          child: Text(
                            'Erstellt mit Liebe von Stoney22',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),
                      ],
                    ),
                    AviationWeatherView(
                      accentColor: widget.accentColor,
                      english: english,
                      apiGet: (path, headers) => _apiGet(
                        path,
                        headers: headers,
                        timeout: const Duration(seconds: 15),
                      ),
                    ),
                    if (widget.session.can('files_view'))
                      FileManagerView(
                        accentColor: widget.accentColor,
                        authToken: widget.session.token,
                        username: widget.session.username,
                        canUpload: widget.session.can('files_upload'),
                        canManage: widget.session.can('files_manage'),
                        isAdmin: widget.session.isAdmin,
                        apiBase: () => widget.client.activeBase,
                        apiGet: (path, headers) =>
                            _apiGet(path, headers: headers),
                        apiPost: (path, headers, body, timeout) => _apiPost(
                          path,
                          headers: headers,
                          body: body,
                          timeout: timeout ?? const Duration(seconds: 10),
                        ),
                      ),
                    if (widget.session.can('terminal_access'))
                      TerminalView(
                        accentColor: widget.accentColor,
                        apiPost: (path, headers, body, timeout) => _apiPost(
                          path,
                          headers: headers,
                          body: body,
                          timeout: timeout ?? const Duration(seconds: 20),
                        ),
                      ),
                    if (widget.session.can('users_manage'))
                      UserAdminView(
                        client: widget.client,
                        session: widget.session,
                        onSessionUpdated: widget.onSessionUpdated,
                        accentColor: widget.accentColor,
                      ),
                    FeatureHubView(
                      client: widget.client,
                      session: widget.session,
                    ),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: maintenance || layoutStyle.ownsNavigation
          ? null
          : PiBottomNavigation(
              style: layoutStyle,
              selectedIndex: currentPageIndex,
              items: navigationItems,
              onSelected: selectPage,
            ),
    );
  }
}

class PiDashboardList extends StatelessWidget {
  final PiLayoutStyle style;
  final RefreshCallback onRefresh;
  final List<Widget> children;

  const PiDashboardList({
    super.key,
    required this.style,
    required this.onRefresh,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final design = context.piDesign;
    final maxWidth = switch (style) {
      PiLayoutStyle.aurora => 1120.0,
      PiLayoutStyle.commandCenter => 1480.0,
      PiLayoutStyle.compact => 1560.0,
      PiLayoutStyle.classic => 1040.0,
    };
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.all(design.pagePadding),
        children: [
          for (final child in children)
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: SizedBox(width: double.infinity, child: child),
              ),
            ),
        ],
      ),
    );
  }
}

class PiQuickActions extends StatelessWidget {
  final PiLayoutStyle style;
  final List<String> keys;
  final ValueChanged<String> onPressed;

  const PiQuickActions({
    super.key,
    required this.style,
    required this.keys,
    required this.onPressed,
  });

  (IconData, String) _details(String key) => switch (key) {
    'files' => (Icons.folder_rounded, 'Dateien'),
    'more' => (Icons.photo_library_rounded, 'Medien & Mehr'),
    'backups' => (Icons.backup_rounded, 'Backups'),
    _ => (Icons.search_rounded, 'Suche'),
  };

  @override
  Widget build(BuildContext context) {
    if (style == PiLayoutStyle.compact) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final key in keys)
                ActionChip(
                  avatar: Icon(_details(key).$1, size: 18),
                  label: Text(_details(key).$2),
                  onPressed: () => onPressed(key),
                ),
            ],
          ),
        ),
      );
    }

    if (style == PiLayoutStyle.classic) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final key in keys)
                OutlinedButton.icon(
                  onPressed: () => onPressed(key),
                  icon: Icon(_details(key).$1),
                  label: Text(_details(key).$2),
                ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final key in keys)
              SizedBox(
                width: wide
                    ? (constraints.maxWidth - 36) / 4
                    : (constraints.maxWidth - 12) / 2,
                child: _QuickActionTile(
                  style: style,
                  icon: _details(key).$1,
                  label: _details(key).$2,
                  onTap: () => onPressed(key),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final PiLayoutStyle style;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.style,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration:
              style == PiLayoutStyle.aurora ||
                  style == PiLayoutStyle.commandCenter
              ? BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.primary.withValues(
                        alpha: style == PiLayoutStyle.commandCenter ? .10 : .22,
                      ),
                      const Color(0xFF101827).withValues(alpha: .15),
                    ],
                  ),
                )
              : null,
          child: Row(
            children: [
              Icon(icon, color: colors.primary),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class PiSystemGrid extends StatelessWidget {
  final PiLayoutStyle style;
  final List<Widget> children;

  const PiSystemGrid({super.key, required this.style, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = switch (style) {
          PiLayoutStyle.commandCenter when constraints.maxWidth >= 900 => 4,
          PiLayoutStyle.compact when constraints.maxWidth >= 760 => 4,
          PiLayoutStyle.aurora when constraints.maxWidth >= 1050 => 4,
          _ => 2,
        };
        return GridView.count(
          crossAxisCount: count,
          crossAxisSpacing: context.piDesign.sectionGap,
          mainAxisSpacing: context.piDesign.sectionGap,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisExtent: style == PiLayoutStyle.compact ? 138 : 165,
          children: children,
        );
      },
    );
  }
}

class DashboardHeroCard extends StatelessWidget {
  final PiLayoutStyle style;
  final bool connected;
  final bool loading;
  final String hostname;
  final String uptime;
  final double? temperature;
  final int healthScore;
  final Color accentColor;
  final VoidCallback? onOpenFiles;

  const DashboardHeroCard({
    super.key,
    required this.style,
    required this.connected,
    required this.loading,
    required this.hostname,
    required this.uptime,
    required this.temperature,
    required this.healthScore,
    required this.accentColor,
    required this.onOpenFiles,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = connected
        ? const Color(0xFF60E6A8)
        : Colors.orangeAccent;
    final foreground = style == PiLayoutStyle.classic
        ? colorScheme.onSurface
        : Colors.white;
    final gradient = switch (style) {
      PiLayoutStyle.aurora => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accentColor.withValues(alpha: 0.98),
          colorScheme.tertiary.withValues(alpha: 0.78),
          const Color(0xFF19223A),
        ],
      ),
      PiLayoutStyle.commandCenter => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF101827), Color(0xFF0D2029), Color(0xFF111827)],
      ),
      PiLayoutStyle.compact => LinearGradient(
        colors: [const Color(0xFF171D27), accentColor.withValues(alpha: .20)],
      ),
      PiLayoutStyle.classic => null,
    };

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: style == PiLayoutStyle.classic ? colorScheme.surface : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(context.piDesign.radius + 4),
        border: Border.all(
          color: style == PiLayoutStyle.commandCenter
              ? accentColor.withValues(alpha: .30)
              : Colors.white.withValues(alpha: .08),
        ),
        boxShadow:
            style == PiLayoutStyle.aurora ||
                style == PiLayoutStyle.commandCenter
            ? [
                BoxShadow(
                  color: accentColor.withValues(
                    alpha: style == PiLayoutStyle.commandCenter ? .10 : .20,
                  ),
                  blurRadius: style == PiLayoutStyle.commandCenter ? 34 : 30,
                  offset: const Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          if (style == PiLayoutStyle.commandCenter)
            Positioned(
              right: -72,
              top: -86,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accentColor.withValues(alpha: .10),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          if (style == PiLayoutStyle.aurora)
            Positioned(
              right: -54,
              top: -62,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
          if (style == PiLayoutStyle.aurora)
            Positioned(
              right: 40,
              bottom: -85,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.10),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.all(style == PiLayoutStyle.compact ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: style == PiLayoutStyle.compact ? 42 : 52,
                      height: style == PiLayoutStyle.compact ? 42 : 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Icon(
                        Icons.developer_board_rounded,
                        color: foreground,
                        size: style == PiLayoutStyle.compact ? 23 : 28,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: loading ? Colors.white54 : statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            loading
                                ? 'Verbinde …'
                                : connected
                                ? 'Online'
                                : 'Offline',
                            style: TextStyle(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: style == PiLayoutStyle.compact ? 14 : 24),
                Text(
                  switch (style) {
                    PiLayoutStyle.commandCenter => 'SERVER COMMAND CENTER',
                    PiLayoutStyle.compact => 'Systemübersicht',
                    PiLayoutStyle.classic => 'Raspberry Pi Übersicht',
                    PiLayoutStyle.aurora => 'Alles im Blick.',
                  },
                  style: TextStyle(
                    color: foreground,
                    fontSize: style == PiLayoutStyle.compact ? 22 : 30,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hostname,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.76),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HeroMetric(
                      foreground: foreground,
                      icon: Icons.favorite_rounded,
                      label: 'Status',
                      value: '$healthScore / 100',
                    ),
                    _HeroMetric(
                      foreground: foreground,
                      icon: Icons.thermostat_rounded,
                      label: 'Temperatur',
                      value: temperature == null
                          ? '—'
                          : '${temperature!.toStringAsFixed(1)} °C',
                    ),
                    _HeroMetric(
                      foreground: foreground,
                      icon: Icons.schedule_rounded,
                      label: 'Laufzeit',
                      value: uptime,
                    ),
                  ],
                ),
                if (onOpenFiles != null) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onOpenFiles,
                    style: style == PiLayoutStyle.aurora
                        ? FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF10182A),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text(
                      'Dateimanager öffnen',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color foreground;

  const _HeroMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground.withValues(alpha: .72), size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.62),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w800,
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

class HealthScoreCard extends StatelessWidget {
  final int score;
  final int alertCount;

  const HealthScoreCard({
    super.key,
    required this.score,
    required this.alertCount,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    if (score >= 90) {
      color = Colors.green;
      label = 'Sehr gut';
      icon = Icons.favorite;
    } else if (score >= 75) {
      color = Colors.lightGreen;
      label = 'Gut';
      icon = Icons.thumb_up_alt_outlined;
    } else if (score >= 50) {
      color = Colors.orange;
      label = 'Achtung';
      icon = Icons.warning_amber_rounded;
    } else {
      color = Colors.red;
      label = 'Kritisch';
      icon = Icons.error_outline;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 7,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.12),
                  ),
                  Center(
                    child: Text(
                      '$score',
                      style: TextStyle(
                        color: color,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 20, color: color),
                      const SizedBox(width: 7),
                      const Text(
                        'Systemzustand',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$label · $score von 100 Punkten',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    alertCount == 0
                        ? 'Keine aktiven Warnungen'
                        : '$alertCount aktive Warnung${alertCount == 1 ? '' : 'en'}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BenchmarkCard extends StatelessWidget {
  final bool running;
  final Map<String, dynamic>? result;
  final List<Map<String, dynamic>> history;
  final VoidCallback? onRun;

  const BenchmarkCard({
    super.key,
    required this.running,
    required this.result,
    required this.history,
    required this.onRun,
  });

  String formatScore(dynamic value) {
    final number = asDouble(value);
    if (number == null) return '—';

    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(2)} Mio.';
    }

    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)} Tsd.';
    }

    return number.toStringAsFixed(0);
  }

  String formatTemp(dynamic value) {
    final number = asDouble(value);
    if (number == null) return '—';
    return '${number.toStringAsFixed(1)} °C';
  }

  String formatFrequency(dynamic value) {
    final number = asDouble(value);
    if (number == null) return '—';
    return '${number.toStringAsFixed(0)} MHz';
  }

  String formatTimestamp(dynamic value) {
    if (value is! num) return '—';

    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);

    return '${twoDigits(date.day)}.${twoDigits(date.month)}. '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }

  List<double> get scoreHistory {
    final values = <double>[];

    for (final item in history) {
      final score = asDouble(item['score']);
      if (score != null) {
        values.add(score);
      }
    }

    return values;
  }

  @override
  Widget build(BuildContext context) {
    final score = result?['score'];
    final best = result?['best_score'];
    final before = result?['temperature_before'];
    final after = result?['temperature_after'];
    final delta = asDouble(result?['temperature_delta']);
    final duration = asDouble(result?['duration_seconds']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.bolt,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CPU-Kurzbenchmark',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        '5 Sekunden · SHA-256 · höher = besser',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (result != null) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: 'Letzter Score',
                      value: formatScore(score),
                    ),
                  ),
                  Expanded(
                    child: _MiniStat(
                      label: 'Bestwert',
                      value: formatScore(best),
                    ),
                  ),
                  Expanded(
                    child: _MiniStat(
                      label: 'Dauer',
                      value: duration == null
                          ? '—'
                          : '${duration.toStringAsFixed(1)} s',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: 'Temp. vorher',
                      value: formatTemp(before),
                    ),
                  ),
                  Expanded(
                    child: _MiniStat(
                      label: 'Temp. nachher',
                      value: formatTemp(after),
                    ),
                  ),
                  Expanded(
                    child: _MiniStat(
                      label: 'Δ Temperatur',
                      value: delta == null
                          ? '—'
                          : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} °C',
                    ),
                  ),
                ],
              ),
            ],

            if (history.isNotEmpty) ...[
              const SizedBox(height: 18),

              const Divider(),

              const SizedBox(height: 10),

              Row(
                children: [
                  const Icon(Icons.timeline, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Benchmark-Verlauf',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    '${history.length} Runs',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              SizedBox(
                height: 105,
                width: double.infinity,
                child: CustomPaint(
                  painter: BenchmarkHistoryPainter(
                    values: scoreHistory,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'älter',
                    style: TextStyle(color: Colors.grey, fontSize: 9),
                  ),
                  Text(
                    'höher = besser',
                    style: TextStyle(color: Colors.grey, fontSize: 9),
                  ),
                  Text(
                    'neu',
                    style: TextStyle(color: Colors.grey, fontSize: 9),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                child: Column(
                  children: [
                    for (
                      int i = history.length - 1;
                      i >= 0 && i >= history.length - 8;
                      i--
                    )
                      BenchmarkHistoryRow(
                        item: history[i],
                        bestScore: history
                            .map((e) => asDouble(e['score']) ?? 0)
                            .fold<double>(0, (a, b) => a > b ? a : b),
                        formatScore: formatScore,
                        formatFrequency: formatFrequency,
                        formatTemp: formatTemp,
                        formatTimestamp: formatTimestamp,
                        showDivider: i > 0 && i > history.length - 8,
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: running || onRun == null ? null : onRun,
                icon: running
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  running ? 'Benchmark läuft...' : 'CPU-Benchmark starten',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Der Test belastet die CPU nur kurz. Nach einem Lauf gilt ein Cooldown von 30 Sekunden.',
              style: TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class BenchmarkHistoryRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final double bestScore;
  final String Function(dynamic value) formatScore;
  final String Function(dynamic value) formatFrequency;
  final String Function(dynamic value) formatTemp;
  final String Function(dynamic value) formatTimestamp;
  final bool showDivider;

  const BenchmarkHistoryRow({
    super.key,
    required this.item,
    required this.bestScore,
    required this.formatScore,
    required this.formatFrequency,
    required this.formatTemp,
    required this.formatTimestamp,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final score = asDouble(item['score']);
    final frequency =
        item['frequency_before_mhz'] ?? item['frequency_after_mhz'];

    final isBest = score != null && bestScore > 0 && score >= bestScore;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      (isBest
                              ? Colors.green
                              : Theme.of(context).colorScheme.primary)
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  isBest ? Icons.emoji_events : Icons.speed,
                  size: 18,
                  color: isBest
                      ? Colors.green
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          formatScore(score),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isBest ? Colors.green : null,
                          ),
                        ),
                        if (isBest) ...[
                          const SizedBox(width: 6),
                          const Text(
                            'BEST',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatFrequency(frequency)} · '
                      '${formatTemp(item['temperature_after'])}',
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Text(
                formatTimestamp(item['timestamp']),
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, indent: 58),
      ],
    );
  }
}

class BenchmarkHistoryPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  BenchmarkHistoryPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);

    final range = (maxValue - minValue).abs() < 1 ? 1.0 : maxValue - minValue;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;

    final linePath = Path();
    final fillPath = Path();

    for (int i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : i * size.width / (values.length - 1);

      final normalized = (values[i] - minValue) / range;

      final y =
          size.height -
          (normalized * size.height * 0.82) -
          (size.height * 0.09);

      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    if (values.length > 1) {
      fillPath.lineTo(size.width, size.height);
      fillPath.close();

      canvas.drawPath(fillPath, fillPaint);

      canvas.drawPath(linePath, linePaint);
    } else {
      final dot = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(size.width / 2, size.height / 2), 5, dot);
    }

    if (values.length > 1) {
      final last = values.last;
      final normalized = (last - minValue) / range;

      final y =
          size.height -
          (normalized * size.height * 0.82) -
          (size.height * 0.09);

      canvas.drawCircle(
        Offset(size.width, y),
        4.5,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BenchmarkHistoryPainter oldDelegate) {
    return true;
  }
}

class SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const SectionTitle({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class StatusOverviewCard extends StatelessWidget {
  final bool connected;
  final bool loading;
  final List<AlertItem> alerts;
  final String lastUpdated;

  const StatusOverviewCard({
    super.key,
    required this.connected,
    required this.loading,
    required this.alerts,
    required this.lastUpdated,
  });

  @override
  Widget build(BuildContext context) {
    final criticalCount = alerts
        .where((item) => item.level == 'critical')
        .length;

    Color color;
    IconData icon;
    String title;
    String subtitle;

    if (loading && !connected) {
      color = Colors.orange;
      icon = Icons.sync;
      title = 'Raspberry Pi';
      subtitle = 'Verbinde...';
    } else if (!connected) {
      color = Colors.red;
      icon = Icons.cloud_off;
      title = 'Raspberry Pi offline';
      subtitle = 'Keine Verbindung';
    } else if (criticalCount > 0) {
      color = Colors.red;
      icon = Icons.error;
      title =
          '$criticalCount kritische Warnung${criticalCount == 1 ? '' : 'en'}';
      subtitle =
          '${alerts.length} Problem${alerts.length == 1 ? '' : 'e'} erkannt';
    } else if (alerts.isNotEmpty) {
      color = Colors.orange;
      icon = Icons.warning_amber_rounded;
      title = '${alerts.length} Warnung${alerts.length == 1 ? '' : 'en'}';
      subtitle = 'Pi läuft, aber etwas braucht Aufmerksamkeit';
    } else {
      color = Colors.green;
      icon = Icons.check_circle;
      title = 'Alles läuft normal';
      subtitle = 'Raspberry Pi ist online';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle),
                  const SizedBox(height: 3),
                  Text(
                    lastUpdated,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.circle,
              size: 13,
              color: connected ? Colors.green : Colors.red,
            ),
          ],
        ),
      ),
    );
  }
}

class AlertsCard extends StatelessWidget {
  final List<AlertItem> alerts;

  const AlertsCard({super.key, required this.alerts});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.notifications_active_outlined),
        title: Text(
          '${alerts.length} aktive Warnung${alerts.length == 1 ? '' : 'en'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        children: [
          for (final alert in alerts)
            ListTile(
              leading: Icon(
                alert.level == 'critical'
                    ? Icons.error
                    : Icons.warning_amber_rounded,
                color: alert.level == 'critical' ? Colors.red : Colors.orange,
              ),
              title: Text(alert.title),
              subtitle: Text(alert.message),
            ),
        ],
      ),
    );
  }
}

enum SystemCardType { percent, temperature }

class SystemCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final double? numericValue;
  final SystemCardType type;
  final Color accentColor;

  const SystemCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.numericValue,
    required this.type,
    required this.accentColor,
  });

  Color get statusColor {
    final number = numericValue;

    if (type == SystemCardType.temperature) {
      if (number == null) return Colors.green;
      if (number >= 80) return Colors.red;
      if (number >= 70) return Colors.orange;
      return Colors.green;
    }

    if (number == null) return accentColor;
    if (number >= 90) return Colors.red;
    if (number >= 70) return Colors.orange;
    return Colors.green;
  }

  double get progress {
    final number = numericValue;
    if (number == null) return 0;

    return (number / 100).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final color = statusColor;
    final showProgress = type == SystemCardType.percent;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  color: type == SystemCardType.temperature ? color : null,
                ),
              ),
            ),
            const SizedBox(height: 6),
            if (showProgress)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: color.withValues(alpha: 0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                subtitle,
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TemperatureStatsCard extends StatelessWidget {
  final double? current;
  final double? sessionMax;
  final double? max24h;

  const TemperatureStatsCard({
    super.key,
    required this.current,
    required this.sessionMax,
    required this.max24h,
  });

  String text(double? value) {
    if (value == null) return '—';
    return '${value.toStringAsFixed(1)} °C';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.thermostat, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(label: 'Jetzt', value: text(current)),
            ),
            Expanded(
              child: _MiniStat(
                label: 'Max. App-Start',
                value: text(sessionMax),
              ),
            ),
            Expanded(
              child: _MiniStat(label: 'Max. 24h', value: text(max24h)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class DetailBar extends StatelessWidget {
  final String title;
  final double? value;
  final String suffix;
  final IconData icon;
  final Color color;

  const DetailBar({
    super.key,
    required this.title,
    required this.value,
    required this.suffix,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final number = value ?? 0;
    final progress = (number / 100).clamp(0.0, 1.0);

    Color barColor;
    if (number >= 90) {
      barColor = Colors.red;
    } else if (number >= 70) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.green;
    }

    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        SizedBox(
          width: 80,
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              color: barColor,
              backgroundColor: barColor.withValues(alpha: 0.12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 55,
          child: Text(
            '${number.toStringAsFixed(0)}$suffix',
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class LiveChartCard extends StatelessWidget {
  final String title;
  final List<double> values;
  final String unit;
  final IconData icon;
  final double maxValue;
  final Color lineColor;

  const LiveChartCard({
    super.key,
    required this.title,
    required this.values,
    required this.unit,
    required this.icon,
    required this.maxValue,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final current = values.isEmpty ? null : values.last;
    final minimum = values.isEmpty
        ? null
        : values.reduce((a, b) => a < b ? a : b);
    final maximum = values.isEmpty
        ? null
        : values.reduce((a, b) => a > b ? a : b);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: lineColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: lineColor, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text(
                        '1 Messpunkt/min · bis zu 24h',
                        style: TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Text(
                  current == null ? '—' : '${current.toStringAsFixed(1)} $unit',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 110,
              width: double.infinity,
              child: CustomPaint(
                painter: LiveChartPainter(
                  values: values,
                  maxValue: maxValue,
                  color: lineColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  minimum == null
                      ? 'Min —'
                      : 'Min ${minimum.toStringAsFixed(1)} $unit',
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
                Text(
                  maximum == null
                      ? 'Max —'
                      : 'Max ${maximum.toStringAsFixed(1)} $unit',
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LiveChartPainter extends CustomPainter {
  final List<double> values;
  final double maxValue;
  final Color color;

  LiveChartPainter({
    required this.values,
    required this.maxValue,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;

    final linePath = Path();
    final fillPath = Path();

    final effectiveValues = _downsample(values, size.width);

    for (int i = 0; i < effectiveValues.length; i++) {
      final x = effectiveValues.length == 1
          ? size.width / 2
          : i * size.width / (effectiveValues.length - 1);

      final normalized = (effectiveValues[i] / maxValue).clamp(0.0, 1.0);

      final y = size.height - (normalized * size.height);

      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    if (effectiveValues.length > 1) {
      fillPath.lineTo(size.width, size.height);
      fillPath.close();
      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(linePath, linePaint);
    }

    final lastValue = effectiveValues.last;
    final normalized = (lastValue / maxValue).clamp(0.0, 1.0);

    final lastX = effectiveValues.length == 1 ? size.width / 2 : size.width;

    final lastY = size.height - (normalized * size.height);

    canvas.drawCircle(
      Offset(lastX, lastY),
      4.5,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  List<double> _downsample(List<double> source, double width) {
    final maxPoints = width.ceil().clamp(60, 400);

    if (source.length <= maxPoints) {
      return source;
    }

    final result = <double>[];
    final step = source.length / maxPoints;

    for (int i = 0; i < maxPoints; i++) {
      final index = (i * step).floor().clamp(0, source.length - 1);
      result.add(source[index]);
    }

    result.add(source.last);
    return result;
  }

  @override
  bool shouldRepaint(covariant LiveChartPainter oldDelegate) {
    return true;
  }
}

class StorageCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double? used;
  final double? free;
  final double? total;
  final double? percent;
  final bool mounted;

  const StorageCard({
    super.key,
    required this.title,
    required this.icon,
    required this.used,
    required this.free,
    required this.total,
    required this.percent,
    required this.mounted,
  });

  @override
  Widget build(BuildContext context) {
    final p = percent ?? 0;

    Color color;
    String status;

    if (!mounted) {
      color = Colors.red;
      status = 'NICHT VERFÜGBAR';
    } else if (p >= 90) {
      color = Colors.red;
      status = 'FAST VOLL';
    } else if (free != null && free! < 10) {
      color = Colors.orange;
      status = 'WIRD KNAPP';
    } else {
      color = Colors.green;
      status = 'SPEICHER OK';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: (p / 100).clamp(0.0, 1.0),
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Belegt',
                    value: used == null
                        ? '—'
                        : '${used!.toStringAsFixed(1)} GB',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Frei',
                    value: free == null
                        ? '—'
                        : '${free!.toStringAsFixed(1)} GB',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Gesamt',
                    value: total == null
                        ? '—'
                        : '${total!.toStringAsFixed(1)} GB',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Belegt %',
                    value: percent == null
                        ? '—'
                        : '${percent!.toStringAsFixed(0)} %',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class NetworkCard extends StatelessWidget {
  final String? lanIp;
  final String? tailscaleIp;
  final bool tailscaleOnline;
  final int? latencyMs;
  final String activeConnection;

  const NetworkCard({
    super.key,
    required this.lanIp,
    required this.tailscaleIp,
    required this.tailscaleOnline,
    required this.latencyMs,
    required this.activeConnection,
  });

  @override
  Widget build(BuildContext context) {
    final latency = latencyMs;

    Color latencyColor;
    if (latency == null) {
      latencyColor = Colors.grey;
    } else if (latency >= 500) {
      latencyColor = Colors.red;
    } else if (latency >= 150) {
      latencyColor = Colors.orange;
    } else {
      latencyColor = Colors.green;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _InfoLine(
              icon: Icons.route,
              label: 'Aktive Verbindung',
              value: activeConnection,
              valueColor: Colors.green,
            ),
            const Divider(height: 24),
            _InfoLine(icon: Icons.lan, label: 'LAN-IP', value: lanIp ?? '—'),
            const Divider(height: 24),
            _InfoLine(
              icon: Icons.vpn_lock,
              label: 'Tailscale-IP',
              value: tailscaleOnline ? (tailscaleIp ?? '—') : 'Offline',
              valueColor: tailscaleOnline ? Colors.green : Colors.red,
            ),
            const Divider(height: 24),
            _InfoLine(
              icon: Icons.speed,
              label: 'API-Latenz',
              value: latency == null ? '—' : '$latency ms',
              valueColor: latencyColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: valueColor),
        ),
      ],
    );
  }
}

class ServiceControlCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool online;
  final String description;
  final VoidCallback? onRestart;

  const ServiceControlCard({
    super.key,
    required this.title,
    required this.icon,
    required this.online,
    required this.description,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final color = online ? Colors.green : Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (onRestart != null)
              IconButton.filledTonal(
                onPressed: onRestart,
                icon: const Icon(Icons.restart_alt),
                tooltip: '$title neu starten',
              ),
          ],
        ),
      ),
    );
  }
}

class SystemInfoCard extends StatelessWidget {
  final List<InfoRowData> rows;

  const SystemInfoCard({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.developer_board),
        title: const Text(
          'Raspberry Pi Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Modell, OS, Kernel, Uptime und mehr'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                for (int i = 0; i < rows.length; i++) ...[
                  _SystemInfoRow(data: rows[i]),
                  if (i != rows.length - 1) const Divider(height: 18),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemInfoRow extends StatelessWidget {
  final InfoRowData data;

  const _SystemInfoRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(data.label, style: const TextStyle(color: Colors.grey)),
        ),
        Expanded(
          child: Text(
            data.value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class AlertItem {
  final String key;
  final String level;
  final String title;
  final String message;

  const AlertItem({
    required this.key,
    required this.level,
    required this.title,
    required this.message,
  });
}

class HistoryPoint {
  final DateTime timestamp;
  final double? cpu;
  final double? ram;
  final double? temperature;

  const HistoryPoint({
    required this.timestamp,
    required this.cpu,
    required this.ram,
    required this.temperature,
  });
}

class AccentOption {
  final String name;
  final Color color;

  const AccentOption(this.name, this.color);
}

class InfoRowData {
  final String label;
  final String value;

  const InfoRowData(this.label, this.value);
}

class _MaintenanceView extends StatelessWidget {
  const _MaintenanceView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.primaryContainer.withValues(alpha: 0.9),
                  colors.tertiaryContainer.withValues(alpha: 0.72),
                ],
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: colors.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.16),
                  blurRadius: 48,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(27),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 43,
                    color: colors.onPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Pi Control wird verbessert',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Gerade wird sicher an der App gearbeitet. Du musst nichts '
                  'tun – sobald das Update fertig ist, erscheint Pi Control '
                  'automatisch wieder.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: colors.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 28),
                const LinearProgressIndicator(
                  borderRadius: BorderRadius.all(Radius.circular(99)),
                ),
                const SizedBox(height: 12),
                Text(
                  'Update wird installiert …',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

double? asDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  if (value is String) {
    return double.tryParse(value);
  }

  return null;
}

String twoDigits(int value) {
  return value.toString().padLeft(2, '0');
}
