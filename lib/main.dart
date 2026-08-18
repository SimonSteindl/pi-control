import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth.dart';
import 'file_manager_view.dart';
import 'login_views.dart';
import 'terminal_view.dart';
import 'user_admin_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PiControlApp());
}

class PiControlApp extends StatefulWidget {
  const PiControlApp({super.key});

  @override
  State<PiControlApp> createState() => _PiControlAppState();
}

class _PiControlAppState extends State<PiControlApp> {
  Color accentColor = Colors.blue;
  final PiApiClient client = PiApiClient();
  AuthSession? session;
  bool restoringSession = true;

  @override
  void initState() {
    super.initState();
    restoreSession();
  }

  Future<void> restoreSession() async {
    AuthSession? restored;
    try {
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

  void changeAccent(Color color) {
    setState(() {
      accentColor = color;
    });
  }

  Future<void> logout() async {
    await client.logout();
    if (!mounted) return;
    setState(() {
      session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pi Control',
      theme: ThemeData(
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

  const DashboardPage({
    super.key,
    required this.accentColor,
    required this.onAccentChanged,
    required this.client,
    required this.session,
    required this.onSessionUpdated,
    required this.onLogout,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String get activeConnectionName => widget.client.connectionName;

  Map<String, dynamic>? data;
  bool loading = true;
  bool connected = false;
  String? error;

  Timer? refreshTimer;
  Timer? historyTimer;

  int? latencyMs;
  DateTime? lastUpdated;
  double? sessionMaxTemperature;

  bool benchmarkRunning = false;
  Map<String, dynamic>? benchmarkResult;
  List<Map<String, dynamic>> benchmarkHistory = [];

  List<HistoryPoint> history = [];
  int selectedPageIndex = 0;

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
    if (widget.session.can('dashboard_view')) {
      loadAll();

      refreshTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => loadData(),
      );

      historyTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => loadHistory(),
      );
    } else {
      loading = false;
    }
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    historyTimer?.cancel();
    super.dispose();
  }

  Future<void> loadAll() async {
    await Future.wait([loadData(), loadHistory(), loadBenchmarkHistory()]);
  }

  Future<void> loadData() async {
    final stopwatch = Stopwatch()..start();

    try {
      final response = await _apiGet('info');

      stopwatch.stop();

      if (response.statusCode != 200) {
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
    } catch (e) {
      stopwatch.stop();

      if (!mounted) return;

      setState(() {
        connected = false;
        loading = false;
        latencyMs = null;
        error = e.toString();
      });
    }
  }

  Future<void> loadHistory() async {
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
    }
  }

  Future<void> loadBenchmarkHistory() async {
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

  void showAccentPicker() {
    final options = <AccentOption>[
      const AccentOption('Blau', Colors.blue),
      const AccentOption('Grün', Colors.green),
      const AccentOption('Lila', Colors.deepPurple),
      const AccentOption('Orange', Colors.orange),
      const AccentOption('Rot', Colors.red),
      const AccentOption('Türkis', Colors.teal),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'App-Farbe',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Die Temperatur bleibt unabhängig davon grün/orange/rot.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final option in options)
                      ChoiceChip(
                        selected: widget.accentColor == option.color,
                        avatar: CircleAvatar(backgroundColor: option.color),
                        label: Text(option.name),
                        onSelected: (_) {
                          widget.onAccentChanged(option.color);
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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
      if (widget.session.can('files_view')) 'files',
      if (widget.session.can('terminal_access')) 'terminal',
      if (widget.session.can('users_manage')) 'users',
    ];
    final currentPageIndex = selectedPageIndex.clamp(0, pageKeys.length - 1);
    final currentPage = pageKeys[currentPageIndex];
    final pageTitle = switch (currentPage) {
      'files' => 'Dateimanager',
      'terminal' => 'Terminal',
      'users' => 'Admin-Panel',
      _ => 'Stoneys Raspberry Pi',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(
          pageTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: showAccentPicker,
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'App-Farbe',
          ),
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
              child: Text(
                widget.session.displayName.isEmpty
                    ? '?'
                    : widget.session.displayName[0].toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            onSelected: (action) {
              if (action == 'password') {
                changeOwnPassword();
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
      body: IndexedStack(
        index: currentPageIndex,
        children: [
          RefreshIndicator(
            onRefresh: loadAll,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DashboardHeroCard(
                  connected: connected,
                  loading: loading,
                  hostname: data?['hostname']?.toString() ?? 'Raspberry Pi',
                  uptime: data?['uptime']?['formatted']?.toString() ?? '—',
                  temperature: temperature,
                  healthScore: healthScore,
                  accentColor: widget.accentColor,
                  onOpenFiles: widget.session.can('files_view')
                      ? () {
                          setState(() {
                            selectedPageIndex = pageKeys.indexOf('files');
                          });
                        }
                      : null,
                ),

                const SizedBox(height: 12),

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

                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisExtent: 165,
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
                    subtitle: const Text('Auslastung und 24-Stunden-Verlauf'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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

                const SizedBox(height: 20),

                const SectionTitle(icon: Icons.speed, title: 'Benchmark'),

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
                    InfoRowData('Modell', system?['model']?.toString() ?? '—'),
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
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
                          const Icon(Icons.error_outline, color: Colors.red),
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
          ),
          if (widget.session.can('files_view'))
            FileManagerView(
              accentColor: widget.accentColor,
              authToken: widget.session.token,
              canUpload: widget.session.can('files_upload'),
              canManage: widget.session.can('files_manage'),
              apiBase: () => widget.client.activeBase,
              apiGet: (path, headers) => _apiGet(path, headers: headers),
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
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentPageIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedPageIndex = index;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded),
            label: 'Übersicht',
          ),
          if (widget.session.can('files_view'))
            const NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder_rounded),
              label: 'Dateien',
            ),
          if (widget.session.can('terminal_access'))
            const NavigationDestination(
              icon: Icon(Icons.terminal_outlined),
              selectedIcon: Icon(Icons.terminal_rounded),
              label: 'Terminal',
            ),
          if (widget.session.can('users_manage'))
            const NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: Icon(Icons.admin_panel_settings_rounded),
              label: 'Admin',
            ),
        ],
      ),
    );
  }
}

class DashboardHeroCard extends StatelessWidget {
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

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.98),
            colorScheme.tertiary.withValues(alpha: 0.78),
            const Color(0xFF19223A),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.20),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
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
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: const Icon(
                        Icons.developer_board_rounded,
                        color: Colors.white,
                        size: 28,
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Alles im Blick.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hostname,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.76),
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
                      icon: Icons.favorite_rounded,
                      label: 'Status',
                      value: '$healthScore / 100',
                    ),
                    _HeroMetric(
                      icon: Icons.thermostat_rounded,
                      label: 'Temperatur',
                      value: temperature == null
                          ? '—'
                          : '${temperature!.toStringAsFixed(1)} °C',
                    ),
                    _HeroMetric(
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
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF10182A),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
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

  const _HeroMetric({
    required this.icon,
    required this.label,
    required this.value,
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
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
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
                  style: const TextStyle(
                    color: Colors.white,
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
