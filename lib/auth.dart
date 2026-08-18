import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;

  const ApiException(this.message, {this.statusCode, this.code});

  @override
  String toString() => message;
}

class AuthSession {
  final String token;
  final int userId;
  final String username;
  final String displayName;
  final bool isAdmin;
  final bool isActive;
  final bool mustChangePassword;
  final Set<String> permissions;

  const AuthSession({
    required this.token,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.isAdmin,
    required this.isActive,
    required this.mustChangePassword,
    required this.permissions,
  });

  factory AuthSession.fromJson(String token, Map<dynamic, dynamic> json) {
    final rawPermissions = json['permissions'];
    return AuthSession(
      token: token,
      userId: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? 'Benutzer',
      isAdmin: json['is_admin'] == true,
      isActive: json['is_active'] != false,
      mustChangePassword: json['must_change_password'] == true,
      permissions: rawPermissions is List
          ? rawPermissions.map((value) => value.toString()).toSet()
          : <String>{},
    );
  }

  bool can(String permission) => isAdmin || permissions.contains(permission);
}

class PiApiClient {
  static const _sessionTokenKey = 'pi_control_session_token';
  static const _secureStorage = FlutterSecureStorage();

  static final List<String> candidates = [
    if (kIsWeb) '${Uri.base.origin}/api',
    'http://192.168.0.123:8080/api',
    'http://100.73.19.27:8080/api',
  ];

  String activeBase = candidates.first;
  String? token;

  String get connectionName {
    if (kIsWeb && activeBase == '${Uri.base.origin}/api') return 'Website';
    if (activeBase.contains('100.73.19.27')) return 'Tailscale';
    return 'LAN';
  }

  Map<String, String> _headers(Map<String, String>? headers) {
    return {if (token != null) 'Authorization': 'Bearer $token', ...?headers};
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final orderedBases = <String>[
      activeBase,
      ...candidates.where((base) => base != activeBase),
    ];
    Object? lastError;

    for (final base in orderedBases) {
      try {
        final uri = Uri.parse('$base/$path');
        final mergedHeaders = _headers(headers);
        late final http.Response response;

        if (method == 'GET') {
          response = await http
              .get(uri, headers: mergedHeaders)
              .timeout(timeout);
        } else if (method == 'POST') {
          response = await http
              .post(uri, headers: mergedHeaders, body: body)
              .timeout(timeout);
        } else if (method == 'PATCH') {
          response = await http
              .patch(uri, headers: mergedHeaders, body: body)
              .timeout(timeout);
        } else {
          throw UnsupportedError('Unbekannte HTTP-Methode: $method');
        }

        activeBase = base;
        return response;
      } catch (error) {
        lastError = error;
      }
    }

    throw ApiException('Raspberry Pi nicht erreichbar: $lastError');
  }

  Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _request('GET', path, headers: headers, timeout: timeout);
  }

  Future<http.Response> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _request(
      'POST',
      path,
      headers: headers,
      body: body,
      timeout: timeout,
    );
  }

  Future<http.Response> patch(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _request(
      'PATCH',
      path,
      headers: headers,
      body: body,
      timeout: timeout,
    );
  }

  Map<String, dynamic> decodeObject(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Der HTTP-Status wird als Rückfall verwendet.
    }
    return <String, dynamic>{};
  }

  ApiException responseException(http.Response response) {
    final decoded = decodeObject(response);
    return ApiException(
      decoded['error']?.toString() ?? 'HTTP ${response.statusCode}',
      statusCode: response.statusCode,
      code: decoded['code']?.toString(),
    );
  }

  Future<AuthSession> login(
    String username,
    String password, {
    required bool rememberMe,
  }) async {
    token = null;
    final response = await post(
      'auth/login',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'remember_me': rememberMe,
        'cookie_only': kIsWeb,
      }),
    );

    if (response.statusCode != 200) throw responseException(response);

    final decoded = decodeObject(response);
    final newToken = decoded['token']?.toString();
    final user = decoded['user'];
    if (user is! Map || (!kIsWeb && newToken == null)) {
      throw const ApiException('Ungültige Login-Antwort.');
    }

    final sessionToken = kIsWeb ? '' : newToken!;
    token = sessionToken.isEmpty ? null : sessionToken;
    if (!kIsWeb) {
      try {
        if (rememberMe) {
          await _secureStorage.write(
            key: _sessionTokenKey,
            value: sessionToken,
          );
        } else {
          await _secureStorage.delete(key: _sessionTokenKey);
        }
      } catch (_) {
        // Der aktive Login funktioniert auch bei gesperrtem Gerätespeicher.
      }
    }
    return AuthSession.fromJson(sessionToken, user);
  }

  Future<AuthSession?> restoreSession() async {
    if (kIsWeb) {
      token = null;
    } else {
      try {
        token = await _secureStorage.read(key: _sessionTokenKey);
      } catch (_) {
        token = null;
      }
      if (token == null || token!.isEmpty) return null;
    }

    final response = await get('auth/me', timeout: const Duration(seconds: 8));

    if (response.statusCode == 401) {
      token = null;
      if (!kIsWeb) {
        try {
          await _secureStorage.delete(key: _sessionTokenKey);
        } catch (_) {
          // Ein ungültiger Token darf den normalen Login nicht blockieren.
        }
      }
      return null;
    }
    if (response.statusCode != 200) throw responseException(response);

    final user = decodeObject(response)['user'];
    if (user is! Map) throw const ApiException('Ungültige Sitzungsantwort.');
    return AuthSession.fromJson(token ?? '', user);
  }

  Future<void> logout() async {
    try {
      await post('auth/logout');
    } finally {
      token = null;
      if (!kIsWeb) {
        try {
          await _secureStorage.delete(key: _sessionTokenKey);
        } catch (_) {
          // Die Server-Sitzung wurde trotzdem beendet.
        }
      }
    }
  }
}
