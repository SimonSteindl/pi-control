import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pi_control/auth.dart';

void main() {
  test('the public HTTPS endpoint is an automatic fallback', () {
    expect(PiApiClient.candidates, contains(PiApiClient.publicServerBase));
    expect(PiApiClient.publicServerBase, startsWith('https://'));
  });

  test(
    'API requests include the ngrok browser-warning bypass header',
    () async {
      final originalCandidates = List<String>.from(PiApiClient.candidates);
      addTearDown(() {
        PiApiClient.candidates
          ..clear()
          ..addAll(originalCandidates);
      });
      PiApiClient.candidates
        ..clear()
        ..add(PiApiClient.publicServerBase);

      final transport = MockClient((request) async {
        expect(request.headers['ngrok-skip-browser-warning'], '1');
        return http.Response('{"ok":true}', 200);
      });
      final client = PiApiClient(httpClient: transport);
      addTearDown(client.close);

      expect((await client.get('info')).statusCode, 200);
    },
  );

  test('PiApiClient remembers a working fallback server', () async {
    final originalCandidates = List<String>.from(PiApiClient.candidates);
    addTearDown(() {
      PiApiClient.candidates
        ..clear()
        ..addAll(originalCandidates);
    });
    PiApiClient.candidates
      ..clear()
      ..addAll(['https://offline.test/api', 'https://online.test/api']);

    final requestedHosts = <String>[];
    final transport = MockClient((request) async {
      requestedHosts.add(request.url.host);
      if (request.url.host == 'offline.test') {
        throw const SocketException('offline');
      }
      return http.Response('{"ok":true}', 200);
    });
    final client = PiApiClient(httpClient: transport);
    addTearDown(client.close);

    expect((await client.get('info')).statusCode, 200);
    expect(client.activeBase, 'https://online.test/api');
    expect((await client.get('history')).statusCode, 200);
    expect(requestedHosts, ['offline.test', 'online.test', 'online.test']);
  });
}
