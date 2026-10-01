import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pi_control/file_manager_view.dart';

void main() {
  Future<void> pumpFileManager(WidgetTester tester, {required bool isAdmin}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileManagerView(
            apiGet: (path, headers) async {
              if (path == 'files/favorites') {
                return http.Response('{"ok":true,"items":[]}', 200);
              }
              return http.Response(
                '{"ok":true,"entries":[],"path":"","root_name":"NAS","storage_path":""}',
                200,
              );
            },
            apiPost: (path, headers, body, timeout) async =>
                http.Response('{"ok":true}', 200),
            apiBase: () => 'https://example.test/api',
            authToken: 'test-token',
            username: 'test',
            canUpload: true,
            canManage: true,
            isAdmin: isAdmin,
            accentColor: Colors.blue,
          ),
        ),
      ),
    );
  }

  testWidgets('Papierkorb ist für normale Benutzer ausgeblendet', (
    tester,
  ) async {
    await pumpFileManager(tester, isAdmin: false);
    await tester.pumpAndSettle();

    expect(find.text('Papierkorb'), findsNothing);
  });

  testWidgets('Papierkorb ist für Administratoren sichtbar', (tester) async {
    await pumpFileManager(tester, isAdmin: true);
    await tester.pumpAndSettle();

    expect(find.text('Papierkorb'), findsOneWidget);
  });
}
