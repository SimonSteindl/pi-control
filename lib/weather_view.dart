import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

typedef AviationWeatherApiGet = Future<http.Response> Function(
  String path,
  Map<String, String>? headers,
);

class AviationWeatherView extends StatefulWidget {
  final Color accentColor;
  final bool english;
  final AviationWeatherApiGet apiGet;

  const AviationWeatherView({
    super.key,
    required this.accentColor,
    required this.english,
    required this.apiGet,
  });

  @override
  State<AviationWeatherView> createState() => _AviationWeatherViewState();
}

class _AviationWeatherViewState extends State<AviationWeatherView> {
  static const quickAirports = <(String, String)>[
    ('LOWL', 'Linz'),
    ('LOWW', 'Wien'),
    ('LOWS', 'Salzburg'),
    ('LOWI', 'Innsbruck'),
    ('LOWG', 'Graz'),
  ];

  final icaoController = TextEditingController(text: 'LOWL');
  Map<String, dynamic>? weather;
  bool loading = true;
  String? error;

  bool get english => widget.english;

  @override
  void initState() {
    super.initState();
    restoreAirport();
  }

  @override
  void dispose() {
    icaoController.dispose();
    super.dispose();
  }

  Future<void> restoreAirport() async {
    final preferences = await SharedPreferences.getInstance();
    icaoController.text =
        preferences.getString('pi_control_weather_icao') ?? 'LOWL';
    await loadWeather();
  }

  Future<void> loadWeather([String? requestedIcao]) async {
    final icao = (requestedIcao ?? icaoController.text).trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(icao)) {
      setState(() {
        loading = false;
        error = english
            ? 'Please enter a four-character ICAO code.'
            : 'Bitte einen vierstelligen ICAO-Code eingeben.';
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
      icaoController.text = icao;
    });
    try {
      final response = await widget.apiGet(
        'aviation-weather?icao=${Uri.encodeQueryComponent(icao)}',
        const {'Accept': 'application/json'},
      );
      final decoded = jsonDecode(response.body);
      final payload = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      if (response.statusCode != 200 || payload['ok'] != true) {
        throw Exception(payload['error'] ?? 'HTTP ${response.statusCode}');
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('pi_control_weather_icao', icao);
      if (!mounted) return;
      setState(() {
        weather = payload;
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = exception.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Map<String, dynamic>? mapValue(String key) {
    final value = weather?[key];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  String displayTime(dynamic value) {
    DateTime? time;
    if (value is num) {
      time = DateTime.fromMillisecondsSinceEpoch(
        value.toInt() * 1000,
        isUtc: true,
      ).toLocal();
    } else if (value != null) {
      time = DateTime.tryParse(value.toString())?.toLocal();
    }
    if (time == null) return '—';
    return '${time.day.toString().padLeft(2, '0')}.'
        '${time.month.toString().padLeft(2, '0')}. '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  Color categoryColor(String category) => switch (category) {
    'VFR' => const Color(0xff2eae68),
    'MVFR' => const Color(0xff3185e8),
    'IFR' => const Color(0xffe34b4b),
    'LIFR' => const Color(0xffb455d4),
    _ => Colors.blueGrey,
  };

  String cloudSummary(Map<String, dynamic>? metar) {
    final clouds = metar?['clouds'];
    if (clouds is! List || clouds.isEmpty) return 'CAVOK / —';
    return clouds
        .whereType<Map>()
        .map((cloud) {
          final cover = cloud['cover']?.toString() ?? '—';
          final base = cloud['base'];
          return base == null ? cover : '$cover $base ft';
        })
        .join(' · ');
  }

  Future<void> openMetarTaf() async {
    final url = weather?['metar_taf_url']?.toString();
    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metar = mapValue('metar');
    final taf = mapValue('taf');
    final category = metar?['fltCat']?.toString() ?? 'N/A';
    final airportName =
        metar?['name']?.toString() ??
        taf?['name']?.toString() ??
        icaoController.text;

    return RefreshIndicator(
      onRefresh: loadWeather,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                colors: [
                  widget.accentColor,
                  Color.lerp(widget.accentColor, Colors.indigo, .55)!,
                ],
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.flight_takeoff_rounded,
                  size: 42,
                  color: Colors.white,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        english ? 'Flight weather' : 'Flugwetter',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        english
                            ? 'Worldwide METAR and TAF at a glance'
                            : 'METAR und TAF weltweit auf einen Blick',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  TextField(
                    controller: icaoController,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 4,
                    onSubmitted: (_) => loadWeather(),
                    decoration: InputDecoration(
                      counterText: '',
                      labelText: english
                          ? 'Airport ICAO code'
                          : 'ICAO-Code des Flughafens',
                      hintText: 'LOWL',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        onPressed: loading ? null : loadWeather,
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: quickAirports.map((airport) {
                        return ChoiceChip(
                          selected: icaoController.text == airport.$1,
                          label: Text('${airport.$2} · ${airport.$1}'),
                          onSelected: (_) => loadWeather(airport.$1),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (loading) ...[
            const SizedBox(height: 48),
            const Center(child: CircularProgressIndicator()),
          ] else if (error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.cloud_off_rounded),
                title: Text(error!),
                trailing: TextButton(
                  onPressed: loadWeather,
                  child: Text(english ? 'Retry' : 'Nochmal'),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                weather?['icao']?.toString() ?? '',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(airportName),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: categoryColor(category),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            category,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        WeatherValue(
                          icon: Icons.air_rounded,
                          label: 'Wind',
                          value: metar == null
                              ? '—'
                              : '${metar['wdir'] ?? 'VRB'}° · '
                                    '${metar['wspd'] ?? '—'} kt'
                                    '${metar['wgst'] == null ? '' : ' G ${metar['wgst']} kt'}',
                        ),
                        WeatherValue(
                          icon: Icons.visibility_rounded,
                          label: english ? 'Visibility' : 'Sicht',
                          value: '${metar?['visib'] ?? '—'} SM',
                        ),
                        WeatherValue(
                          icon: Icons.thermostat_rounded,
                          label: english ? 'Temperature' : 'Temperatur',
                          value: '${metar?['temp'] ?? '—'} °C',
                        ),
                        WeatherValue(
                          icon: Icons.water_drop_outlined,
                          label: english ? 'Dew point' : 'Taupunkt',
                          value: '${metar?['dewp'] ?? '—'} °C',
                        ),
                        WeatherValue(
                          icon: Icons.speed_rounded,
                          label: 'QNH',
                          value: '${metar?['altim'] ?? '—'} hPa',
                        ),
                        WeatherValue(
                          icon: Icons.cloud_queue_rounded,
                          label: english ? 'Clouds' : 'Wolken',
                          value: cloudSummary(metar),
                        ),
                        WeatherValue(
                          icon: Icons.schedule_rounded,
                          label: english ? 'Observed' : 'Beobachtet',
                          value: displayTime(
                            metar?['reportTime'] ?? metar?['obsTime'],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            RawWeatherCard(
              title: 'METAR',
              icon: Icons.cloud_rounded,
              raw: metar?['rawOb']?.toString(),
              emptyText: english
                  ? 'No METAR available.'
                  : 'Kein METAR verfügbar.',
            ),
            const SizedBox(height: 12),
            RawWeatherCard(
              title: 'TAF',
              icon: Icons.timeline_rounded,
              raw: taf?['rawTAF']?.toString(),
              subtitle: taf == null
                  ? null
                  : '${english ? 'Valid' : 'Gültig'}: '
                        '${displayTime(taf['validTimeFrom'])} – '
                        '${displayTime(taf['validTimeTo'])}',
              emptyText: english ? 'No TAF available.' : 'Kein TAF verfügbar.',
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: Text(
                  english
                      ? 'Open detailed view on metar-taf.com'
                      : 'Detailansicht auf metar-taf.com öffnen',
                ),
                subtitle: Text(
                  english
                      ? 'Raw data: AviationWeather.gov · not for flight planning'
                      : 'Rohdaten: AviationWeather.gov · nicht zur Flugplanung',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: openMetarTaf,
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class WeatherValue extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const WeatherValue({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 172,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RawWeatherCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? raw;
  final String? subtitle;
  final String emptyText;

  const RawWeatherCard({
    super.key,
    required this.title,
    required this.icon,
    required this.raw,
    required this.emptyText,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = raw?.trim().isNotEmpty == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 14),
            SelectableText(
              hasData ? raw! : emptyText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 15,
                height: 1.55,
                color: hasData ? null : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
