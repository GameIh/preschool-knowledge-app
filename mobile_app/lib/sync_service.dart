import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_database.dart';
import 'models.dart';

class SyncService {
  SyncService(this._database);

  final AppDatabase _database;

  Future<RemoteApplyResult> synchronize(String baseUrl) async {
    final sessionId = await _database.startSyncSession();
    try {
      final uri = _contentUri(baseUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
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

  Uri _contentUri(String baseUrl) {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      throw SyncException('Укажите адрес сервера обновлений');
    }
    return Uri.parse('$normalized/api/content');
  }
}

class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}
