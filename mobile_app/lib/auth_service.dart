import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'auth_models.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const _serverUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://194.34.239.165:8081',
  );
  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final http.Client _client = http.Client();

  String? _accessToken;
  String? _refreshToken;
  AuthUser? _currentUser;
  Future<bool>? _refreshOperation;

  AuthUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null && _refreshToken != null;

  Future<bool> initialize() async {
    _accessToken = await _storage.read(key: _accessTokenKey);
    _refreshToken = await _storage.read(key: _refreshTokenKey);
    if (_refreshToken == null) {
      return false;
    }
    return refreshSession();
  }

  Future<AuthUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final tokens = await _postTokens('/api/auth/register', {
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'device_name': 'Flutter Android',
    });
    await _saveTokens(tokens);
    return tokens.user;
  }

  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    final tokens = await _postTokens('/api/auth/login', {
      'email': email.trim(),
      'password': password,
      'device_name': 'Flutter Android',
    });
    await _saveTokens(tokens);
    return tokens.user;
  }

  Future<bool> refreshSession() {
    final existing = _refreshOperation;
    if (existing != null) {
      return existing;
    }

    final operation = _refreshSessionInternal();
    _refreshOperation = operation;
    return operation.whenComplete(() => _refreshOperation = null);
  }

  Future<bool> _refreshSessionInternal() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) {
      return false;
    }

    try {
      final tokens = await _postTokens('/api/auth/refresh', {
        'refresh_token': refreshToken,
      });
      await _saveTokens(tokens);
      return true;
    } on AuthException {
      await clearLocalSession();
      return false;
    } on TimeoutException {
      return false;
    } on http.ClientException {
      return false;
    }
  }

  Future<void> logout() async {
    final refreshToken = _refreshToken;
    if (refreshToken != null) {
      try {
        await _client
            .post(
              _uri('/api/auth/logout'),
              headers: _jsonHeaders,
              body: jsonEncode({'refresh_token': refreshToken}),
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // Local logout must still work when the server is unavailable.
      }
    }
    await clearLocalSession();
  }

  Future<void> clearLocalSession() async {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<http.Response> authorizedGet(String path) async {
    var response = await _client
        .get(_uri(path), headers: _authorizedHeaders)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 401) {
      return response;
    }

    final refreshed = await refreshSession();
    if (!refreshed) {
      throw const AuthException('Сессия завершена. Войдите снова.');
    }
    response = await _client
        .get(_uri(path), headers: _authorizedHeaders)
        .timeout(const Duration(seconds: 15));
    return response;
  }

  Future<AuthTokens> _postTokens(String path, Map<String, dynamic> body) async {
    final response = await _client
        .post(_uri(path), headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    final decoded = _decodeObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(_errorMessage(decoded, response.statusCode));
    }
    return AuthTokens.fromJson(decoded);
  }

  Future<void> _saveTokens(AuthTokens tokens) async {
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
    _currentUser = tokens.user;
    await _storage.write(key: _accessTokenKey, value: tokens.accessToken);
    await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
  }

  Uri _uri(String path) => Uri.parse('$_serverUrl$path');

  Map<String, String> get _jsonHeaders => const {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Map<String, String> get _authorizedHeaders => {
    ..._jsonHeaders,
    if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
  };

  static Map<String, dynamic> _decodeObject(http.Response response) {
    if (response.bodyBytes.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const AuthException(
        'Не удалось выполнить запрос. Попробуйте позже.',
      );
    }
    return decoded;
  }

  static String _errorMessage(Map<String, dynamic> body, int statusCode) {
    final detail = body['detail'];
    if (detail is String && detail.isNotEmpty) {
      return detail;
    }
    return 'Не удалось выполнить запрос. Попробуйте позже.';
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
