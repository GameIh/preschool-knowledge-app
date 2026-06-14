import 'dart:async';
import 'dart:convert';

import 'app_database.dart';
import 'auth_service.dart';
import 'models.dart';

class SyncService {
  SyncService(this._database, this._authService);

  final AppDatabase _database;
  final AuthService _authService;

  Future<RemoteApplyResult> synchronize() async {
    final sessionId = await _database.startSyncSession();
    try {
      final response = await _authService.authorizedGet('/api/content');
      if (response.statusCode != 200) {
        throw SyncException('Сервер вернул код ${response.statusCode}');
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw SyncException('Сервер вернул неверный формат данных');
      }

      final result = await _database.applyRemoteContent(decoded);
      await _database.finishSyncSession(sessionId, status: 'success');
      return result;
    } catch (error) {
      await _database.finishSyncSession(
        sessionId,
        status: 'error',
        errorMessage: error.toString(),
      );
      rethrow;
    }
  }
}

class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}
