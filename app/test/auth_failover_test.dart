import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pi_control/auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PiApiClient server failover safety', () {
    test('login credentials are not replayed to fallback servers', () async {
      final requests = <http.BaseRequest>[];
      final client = PiApiClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          throw const SocketException('simulated connection failure');
        }),
      );
      client.activeBase = 'https://selected.example/api';

      await expectLater(
        client.login('test-user', 'do-not-leak-this', rememberMe: false),
        throwsA(isA<ApiException>()),
      );

      expect(requests, hasLength(1));
      expect(requests.single.url.host, 'selected.example');
      expect(requests.single.method, 'POST');
      final body = (requests.single as http.Request).body;
      expect(jsonDecode(body)['password'], 'do-not-leak-this');
      client.close();
    });

    test('remote HTTP server addresses are rejected', () async {
      final client = PiApiClient(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
      );

      await expectLater(
        client.addServer('http://public.example.com'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        client.addServer('https://user:password@private.example.com'),
        throwsA(isA<ApiException>()),
      );
      client.close();
    });

    test('authenticated requests stay on the selected server', () async {
      final requests = <http.BaseRequest>[];
      final client = PiApiClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          throw const SocketException('simulated connection failure');
        }),
      );
      client.activeBase = 'https://selected.example/api';
      client.token = 'test-session-token';

      await expectLater(
        client.get('status'),
        throwsA(isA<ApiException>()),
      );

      expect(requests, hasLength(1));
      expect(requests.single.url.host, 'selected.example');
      expect(
        requests.single.headers['Authorization'],
        'Bearer test-session-token',
      );
      client.close();
    });
  });
}
