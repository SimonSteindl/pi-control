import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_control/layout_system.dart';

const _items = [
  PiNavigationItem(
    keyName: 'dashboard',
    label: 'Übersicht',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
  ),
  PiNavigationItem(
    keyName: 'files',
    label: 'Dateien',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
  ),
];

void main() {
  test('alle gespeicherten Layout-Namen werden wiederhergestellt', () {
    for (final style in PiLayoutStyle.values) {
      expect(piLayoutStyleFromKey(style.storageKey), style);
    }
    expect(piLayoutStyleFromKey('unbekannt'), PiLayoutStyle.aurora);
  });

  test('jede Variante erzeugt eigene globale Designtokens', () {
    for (final style in PiLayoutStyle.values) {
      final theme = buildPiLayoutTheme(
        ThemeData.dark(useMaterial3: true),
        style,
        Colors.blue,
      );
      final tokens = theme.extension<PiDesignTokens>();
      expect(tokens, isNotNull);
      expect(tokens!.style, style);
    }
    final compact = buildPiLayoutTheme(
      ThemeData.dark(useMaterial3: true),
      PiLayoutStyle.compact,
      Colors.blue,
    ).extension<PiDesignTokens>();
    expect(compact!.dense, isTrue);
  });

  testWidgets('Command Center verwendet eine Seitenleiste', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 1200,
          height: 800,
          child: PiLayoutFrame(
            style: PiLayoutStyle.commandCenter,
            selectedIndex: 0,
            items: _items,
            onSelected: _ignoreSelection,
            child: Text('Inhalt'),
          ),
        ),
      ),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('PI CONTROL'), findsOneWidget);
    expect(find.text('Inhalt'), findsOneWidget);
  });

  testWidgets('Kompakt verwendet die obere Chip-Navigation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PiLayoutFrame(
          style: PiLayoutStyle.compact,
          selectedIndex: 0,
          items: _items,
          onSelected: _ignoreSelection,
          child: Text('Inhalt'),
        ),
      ),
    );

    expect(find.byType(FilterChip), findsNWidgets(2));
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('Aurora verwendet eine schwebende untere Navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          bottomNavigationBar: PiBottomNavigation(
            style: PiLayoutStyle.aurora,
            selectedIndex: 0,
            items: _items,
            onSelected: _ignoreSelection,
          ),
        ),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(ClipRRect), findsOneWidget);
  });
}

void _ignoreSelection(int _) {}
