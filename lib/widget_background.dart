import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import 'auth.dart';

const _widgetRefreshTask = 'piControlWidgetRefresh';
const _widgetRefreshUniqueName = 'pi-control-widget-refresh';
const _widgetRefreshNowUniqueName = 'pi-control-widget-refresh-now';

Future<void> initializePiControlWidgetUpdates() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

  await Workmanager().initialize(piControlWidgetCallbackDispatcher);
  // Refresh once right away when Pi Control is opened, then keep the
  // periodic background refresh registered for when the app is closed.
  await Workmanager().registerOneOffTask(
    _widgetRefreshNowUniqueName,
    _widgetRefreshTask,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.connected),
  );
  await Workmanager().registerPeriodicTask(
    _widgetRefreshUniqueName,
    _widgetRefreshTask,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

@pragma('vm:entry-point')
void piControlWidgetCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != _widgetRefreshTask) return true;

    final client = PiApiClient();
    try {
      await client.initialize();
      final session = await client.restoreSession();
      if (session == null) {
        await updatePiControlWidgets(const {}, status: 'LOGIN_REQUIRED');
        return true;
      }

      final response = await client.get(
        'info',
        timeout: const Duration(seconds: 12),
      );
      if (response.statusCode != 200) {
        await updatePiControlWidgets(const {}, status: 'OFFLINE');
        return response.statusCode < 500;
      }

      await updatePiControlWidgets(
        client.decodeObject(response),
        status: 'ONLINE',
      );
      return true;
    } catch (_) {
      await updatePiControlWidgets(const {}, status: 'OFFLINE');
      return false;
    } finally {
      client.close();
    }
  });
}

Future<void> updatePiControlWidgets(
  Map<String, dynamic> snapshot, {
  required String status,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

  final cpu = snapshot['cpu'];
  final ram = snapshot['ram'];
  final sd = snapshot['sd'];
  final values = <String, String>{
    'pi_widget_status': status,
    'pi_widget_updated': DateTime.now().millisecondsSinceEpoch.toString(),
  };
  if (status != 'OFFLINE' || snapshot.isNotEmpty) {
    values.addAll({
      'pi_widget_temperature': _widgetNumber(
        snapshot['temperature'],
        '— °C',
        suffix: ' °C',
      ),
      'pi_widget_cpu': _widgetNumber(
        cpu is Map ? cpu['usage'] : null,
        '—%',
        suffix: '%',
      ),
      'pi_widget_ram': _widgetNumber(
        ram is Map ? ram['percent'] : null,
        '—%',
        suffix: '%',
      ),
      'pi_widget_sd': _widgetNumber(
        sd is Map ? sd['percent'] : null,
        '—%',
        suffix: '%',
      ),
    });
  }

  try {
    for (final entry in values.entries) {
      await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
    }
    await Future.wait([
      HomeWidget.updateWidget(androidName: 'PiControlCompactWidgetProvider'),
      HomeWidget.updateWidget(androidName: 'PiControlStatusWidgetProvider'),
      HomeWidget.updateWidget(androidName: 'PiControlLargeWidgetProvider'),
    ]);
  } catch (_) {
    // Widget-Sync darf die App oder den Pi-Status nicht stören.
  }
}

String _widgetNumber(Object? value, String fallback, {required String suffix}) {
  if (value is! num || !value.isFinite) return fallback;
  return '${value.toStringAsFixed(0)}$suffix';
}
