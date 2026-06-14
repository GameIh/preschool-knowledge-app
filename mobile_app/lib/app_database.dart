import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _database;
  String? _activeOwnerId;

  void setActiveOwnerId(String? ownerId) {
    _activeOwnerId = ownerId;
  }

  String get _ownerId {
    final value = _activeOwnerId;
    if (value == null || value.isEmpty) {
      throw StateError('Пользователь не авторизован');
    }
    return value;
  }

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final db = await _open();
    _database = db;
    return db;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      p.join(dbPath, 'preschool_knowledge.db'),
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "alter table children add column owner_id TEXT not null default 'legacy'",
          );
          await db.execute(
            "alter table activity_logs add column owner_id TEXT not null default 'legacy'",
          );
          await db.execute(
            'create index if not exists idx_children_owner on children(owner_id)',
          );
          await db.execute(
            'create index if not exists idx_logs_owner on activity_logs(owner_id)',
          );
        }
      },
      onOpen: (db) async {
        await _seedIfNeeded(db);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    final statements = <String>[
      '''
      create table activities
      (
          id           INTEGER primary key autoincrement,
          remote_id    TEXT unique,
          version      INTEGER default 1 not null,
          source       TEXT default 'builtin' not null,
          updated_at   TEXT default (datetime('now')) not null,
          is_deleted   INTEGER default 0 not null,
          title        TEXT not null,
          short_desc   TEXT,
          instruction  TEXT not null,
          duration_min INTEGER default 5 not null,
          difficulty   INTEGER default 1 not null,
          materials    TEXT,
          safety_notes TEXT,
          check (difficulty BETWEEN 1 AND 5),
          check (is_deleted IN (0, 1)),
          check (source IN ('builtin', 'remote'))
      )
      ''',
      '''
      create table age_groups
      (
          id         INTEGER primary key autoincrement,
          name       TEXT not null,
          min_months INTEGER not null,
          max_months INTEGER not null,
          check (max_months >= min_months),
          check (min_months >= 0)
      )
      ''',
      '''
      create table activity_age_groups
      (
          activity_id  INTEGER not null references activities on delete cascade,
          age_group_id INTEGER not null references age_groups,
          primary key (activity_id, age_group_id)
      )
      ''',
      '''
      create table children
      (
          id         INTEGER primary key autoincrement,
          owner_id   TEXT not null,
          name       TEXT not null,
          birth_date TEXT,
          age_months INTEGER,
          notes      TEXT
      )
      ''',
      '''
      create table activity_logs
      (
          id          INTEGER primary key autoincrement,
          owner_id    TEXT not null,
          child_id    INTEGER not null references children on delete cascade,
          activity_id INTEGER not null references activities,
          date_time   TEXT default (datetime('now')) not null,
          status      TEXT not null,
          rating      INTEGER,
          comment     TEXT,
          check (rating IS NULL OR rating BETWEEN 1 AND 5),
          check (status IN ('done', 'skipped'))
      )
      ''',
      '''
      create table domains
      (
          id          INTEGER primary key autoincrement,
          name        TEXT not null unique,
          description TEXT
      )
      ''',
      '''
      create table activity_domains
      (
          activity_id INTEGER not null references activities on delete cascade,
          domain_id   INTEGER not null references domains,
          weight      INTEGER default 100 not null,
          primary key (activity_id, domain_id),
          check (weight BETWEEN 1 AND 100)
      )
      ''',
      '''
      create table media
      (
          id         INTEGER primary key autoincrement,
          remote_id  TEXT unique,
          version    INTEGER default 1 not null,
          updated_at TEXT default (datetime('now')) not null,
          is_deleted INTEGER default 0 not null,
          type       TEXT not null,
          local_path TEXT,
          remote_url TEXT,
          checksum   TEXT,
          check (type IN ('image', 'audio', 'video'))
      )
      ''',
      '''
      create table activity_media
      (
          activity_id INTEGER not null references activities on delete cascade,
          media_id    INTEGER not null references media on delete cascade,
          sort_order  INTEGER default 0 not null,
          caption     TEXT,
          primary key (activity_id, media_id)
      )
      ''',
      '''
      create table sync_sessions
      (
          id            INTEGER primary key autoincrement,
          started_at    TEXT default (datetime('now')) not null,
          finished_at   TEXT,
          status        TEXT default 'success' not null,
          source        TEXT default 'api' not null,
          error_message TEXT
      )
      ''',
      '''
      create table sync_state
      (
          id              INTEGER primary key,
          last_sync_at    TEXT,
          content_version TEXT,
          etag            TEXT,
          check (id = 1)
      )
      ''',
      '''
      create table tags
      (
          id   INTEGER primary key autoincrement,
          name TEXT not null unique
      )
      ''',
      '''
      create table activity_tags
      (
          activity_id INTEGER not null references activities on delete cascade,
          tag_id      INTEGER not null references tags,
          primary key (activity_id, tag_id)
      )
      ''',
      'insert into sync_state (id) values (1)',
      'create index idx_children_owner on children(owner_id)',
      'create index idx_logs_owner on activity_logs(owner_id)',
    ];

    final batch = db.batch();
    for (final statement in statements) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  Future<void> _seedIfNeeded(Database db) async {
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('select count(*) from activities'),
        ) ??
        0;
    if (count > 0) {
      return;
    }

    await db.transaction((txn) async {
      final domains = <String, int>{};
      for (final entry in _seedDomains.entries) {
        domains[entry.key] = await _ensureDomain(
          txn,
          entry.key,
          description: entry.value,
        );
      }

      final ageGroups = <String, int>{};
      for (final group in _seedAgeGroups) {
        ageGroups[group.name] = await _ensureAgeGroup(
          txn,
          group.name,
          group.minMonths,
          group.maxMonths,
        );
      }

      await txn.insert('children', {
        'owner_id': 'demo',
        'name': 'Миша',
        'age_months': 54,
        'notes': 'любит игры с карточками; цели: речь + внимание',
      });

      for (final seed in _seedActivities) {
        final activityId = await txn.insert('activities', {
          'remote_id': seed.remoteId,
          'version': 1,
          'source': 'builtin',
          'updated_at': DateTime.now().toIso8601String(),
          'title': seed.title,
          'short_desc': seed.shortDesc,
          'instruction': seed.instruction,
          'duration_min': seed.durationMin,
          'difficulty': seed.difficulty,
          'materials': seed.materials,
          'safety_notes': seed.safetyNotes,
        });

        for (final domainName in seed.domains) {
          final domainId = domains[domainName]!;
          await txn.insert('activity_domains', {
            'activity_id': activityId,
            'domain_id': domainId,
            'weight': 100,
          });
        }

        for (final groupName in seed.ageGroups) {
          final ageGroupId = ageGroups[groupName]!;
          await txn.insert('activity_age_groups', {
            'activity_id': activityId,
            'age_group_id': ageGroupId,
          });
        }

        for (final tagName in seed.tags) {
          final tagId = await _ensureTag(txn, tagName);
          await txn.insert('activity_tags', {
            'activity_id': activityId,
            'tag_id': tagId,
          });
        }
      }
    });
  }

  Future<List<ChildProfile>> getChildren() async {
    final db = await database;
    final rows = await db.query(
      'children',
      where: 'owner_id = ?',
      whereArgs: [_ownerId],
      orderBy: 'id',
    );
    return rows.map(ChildProfile.fromMap).toList();
  }

  Future<int> createChild({
    required String name,
    int? ageMonths,
    String? notes,
  }) async {
    final db = await database;
    return db.insert('children', {
      'owner_id': _ownerId,
      'name': name.trim(),
      'age_months': ageMonths,
      'notes': notes?.trim(),
    });
  }

  Future<void> updateChildNotes(int childId, String? notes) async {
    final db = await database;
    await db.update(
      'children',
      {'notes': notes?.trim()},
      where: 'id = ? and owner_id = ?',
      whereArgs: [childId, _ownerId],
    );
  }

  Future<List<String>> getDomainNames() async {
    final db = await database;
    final rows = await db.query('domains', orderBy: 'name');
    return rows.map((row) => row['name'] as String).toList();
  }

  Future<List<Activity>> getActivities({
    String? query,
    String? domain,
    int? ageMonths,
    bool shortOnly = false,
    String sort = 'recommended',
    int? limit,
  }) async {
    final db = await database;
    final where = <String>['a.is_deleted = 0'];
    final args = <Object?>[];

    final trimmedQuery = query?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      final like = '%$trimmedQuery%';
      where.add('''
        (
          a.title like ?
          or a.short_desc like ?
          or a.instruction like ?
          or a.materials like ?
          or exists (
            select 1
            from activity_tags at
            join tags t on t.id = at.tag_id
            where at.activity_id = a.id and t.name like ?
          )
          or exists (
            select 1
            from activity_domains ad
            join domains d on d.id = ad.domain_id
            where ad.activity_id = a.id and d.name like ?
          )
        )
      ''');
      args.addAll([like, like, like, like, like, like]);
    }

    if (domain != null && domain.isNotEmpty) {
      where.add('''
        exists (
          select 1
          from activity_domains ad
          join domains d on d.id = ad.domain_id
          where ad.activity_id = a.id and d.name = ?
        )
      ''');
      args.add(domain);
    }

    if (ageMonths != null && ageMonths > 0) {
      where.add('''
        exists (
          select 1
          from activity_age_groups aag
          join age_groups ag on ag.id = aag.age_group_id
          where aag.activity_id = a.id
            and ag.min_months <= ?
            and ag.max_months >= ?
        )
      ''');
      args.addAll([ageMonths, ageMonths]);
    }

    if (shortOnly) {
      where.add('a.duration_min <= 7');
    }

    final orderBy = switch (sort) {
      'title' => 'a.title collate nocase',
      'duration' => 'a.duration_min, a.difficulty, a.title',
      'difficulty' => 'a.difficulty, a.duration_min, a.title',
      _ => 'a.duration_min, a.difficulty, a.title',
    };

    final sql =
        '''
      select distinct a.*
      from activities a
      where ${where.join(' and ')}
      order by $orderBy
      ${limit == null ? '' : 'limit $limit'}
    ''';

    final rows = await db.rawQuery(sql, args);
    final activities = <Activity>[];
    for (final row in rows) {
      activities.add(await _hydrateActivity(db, row));
    }
    return activities;
  }

  Future<List<Activity>> getRecommended(ChildProfile? child) async {
    final ageMonths = child?.ageMonths;
    var activities = await getActivities(
      ageMonths: ageMonths,
      shortOnly: true,
      limit: 3,
    );
    if (activities.length < 3) {
      activities = await getActivities(ageMonths: ageMonths, limit: 3);
    }
    return activities;
  }

  Future<Activity?> getActivity(int id) async {
    final db = await database;
    final rows = await db.query(
      'activities',
      where: 'id = ? and is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _hydrateActivity(db, rows.first);
  }

  Future<int> addActivityLog({
    required int childId,
    required int activityId,
    required String status,
    int? rating,
    String? comment,
  }) async {
    final db = await database;
    final ownedChild =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'select count(*) from children where id = ? and owner_id = ?',
            [childId, _ownerId],
          ),
        ) ??
        0;
    if (ownedChild == 0) {
      throw StateError('Профиль ребёнка не принадлежит текущему пользователю');
    }
    return db.insert('activity_logs', {
      'owner_id': _ownerId,
      'child_id': childId,
      'activity_id': activityId,
      'date_time': DateTime.now().toIso8601String(),
      'status': status,
      'rating': rating,
      'comment': comment?.trim(),
    });
  }

  Future<List<ActivityLog>> getLogs({int? childId, int limit = 30}) async {
    final db = await database;
    final where = childId == null
        ? 'where l.owner_id = ?'
        : 'where l.owner_id = ? and l.child_id = ?';
    final args = childId == null
        ? <Object?>[_ownerId]
        : <Object?>[_ownerId, childId];
    final rows = await db.rawQuery('''
      select l.*, a.title as activity_title, c.name as child_name
      from activity_logs l
      join activities a on a.id = l.activity_id
      join children c on c.id = l.child_id
      $where
      order by l.date_time desc, l.id desc
      limit $limit
      ''', args);
    return rows.map(ActivityLog.fromMap).toList();
  }

  Future<SyncStateInfo> getSyncState() async {
    final db = await database;
    final rows = await db.query('sync_state', where: 'id = 1', limit: 1);
    if (rows.isEmpty) {
      return const SyncStateInfo();
    }
    return SyncStateInfo.fromMap(rows.first);
  }

  Future<List<SyncSession>> getSyncSessions({int limit = 10}) async {
    final db = await database;
    final rows = await db.query(
      'sync_sessions',
      orderBy: 'started_at desc, id desc',
      limit: limit,
    );
    return rows.map(SyncSession.fromMap).toList();
  }

  Future<int> startSyncSession({String source = 'api'}) async {
    final db = await database;
    return db.insert('sync_sessions', {
      'started_at': DateTime.now().toIso8601String(),
      'status': 'running',
      'source': source,
    });
  }

  Future<void> finishSyncSession(
    int id, {
    required String status,
    String? errorMessage,
  }) async {
    final db = await database;
    await db.update(
      'sync_sessions',
      {
        'finished_at': DateTime.now().toIso8601String(),
        'status': status,
        'error_message': errorMessage,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<RemoteApplyResult> applyRemoteContent(
    Map<String, dynamic> payload,
  ) async {
    final db = await database;
    final contentVersion = payload['content_version']?.toString();
    final now = DateTime.now().toIso8601String();
    var inserted = 0;
    var updated = 0;
    var deleted = 0;

    await db.transaction((txn) async {
      final domains = payload['domains'];
      if (domains is List) {
        for (final item in domains) {
          if (item is Map) {
            await _ensureDomain(
              txn,
              item['name'].toString(),
              description: item['description']?.toString(),
            );
          } else if (item != null) {
            await _ensureDomain(txn, item.toString());
          }
        }
      }

      final ageGroups = payload['age_groups'];
      if (ageGroups is List) {
        for (final item in ageGroups.whereType<Map>()) {
          final name = item['name']?.toString();
          final minMonths = _asInt(item['min_months']);
          final maxMonths = _asInt(item['max_months']);
          if (name != null && minMonths != null && maxMonths != null) {
            await _ensureAgeGroup(txn, name, minMonths, maxMonths);
          }
        }
      }

      final activities = payload['activities'];
      if (activities is List) {
        for (final item in activities.whereType<Map>()) {
          final remoteId = item['remote_id']?.toString();
          if (remoteId == null || remoteId.trim().isEmpty) {
            continue;
          }

          final incomingVersion = _asInt(item['version']) ?? 1;
          final isDeleted = _asBoolInt(item['is_deleted']);
          final existing = await txn.query(
            'activities',
            where: 'remote_id = ?',
            whereArgs: [remoteId],
            limit: 1,
          );

          final values = <String, Object?>{
            'remote_id': remoteId,
            'version': incomingVersion,
            'source': 'remote',
            'updated_at': item['updated_at']?.toString() ?? now,
            'is_deleted': isDeleted,
            'title': item['title']?.toString() ?? 'Без названия',
            'short_desc': item['short_desc']?.toString(),
            'instruction': _instructionFromItem(item),
            'duration_min': _asInt(item['duration_min']) ?? 5,
            'difficulty': (_asInt(item['difficulty']) ?? 1).clamp(1, 5),
            'materials': item['materials']?.toString(),
            'safety_notes': item['safety_notes']?.toString(),
          };

          late final int activityId;
          if (existing.isEmpty) {
            activityId = await txn.insert('activities', values);
            inserted += isDeleted == 1 ? 0 : 1;
          } else {
            final oldVersion = existing.first['version'] as int? ?? 1;
            activityId = existing.first['id'] as int;
            if (incomingVersion < oldVersion) {
              continue;
            }
            await txn.update(
              'activities',
              values,
              where: 'id = ?',
              whereArgs: [activityId],
            );
            if (isDeleted == 1) {
              deleted++;
            } else if (incomingVersion > oldVersion) {
              updated++;
            }
          }

          await txn.delete(
            'activity_domains',
            where: 'activity_id = ?',
            whereArgs: [activityId],
          );
          await txn.delete(
            'activity_age_groups',
            where: 'activity_id = ?',
            whereArgs: [activityId],
          );
          await txn.delete(
            'activity_tags',
            where: 'activity_id = ?',
            whereArgs: [activityId],
          );

          if (isDeleted == 1) {
            continue;
          }

          for (final domainName in _stringList(item['domains'])) {
            final domainId = await _ensureDomain(txn, domainName);
            await txn.insert('activity_domains', {
              'activity_id': activityId,
              'domain_id': domainId,
              'weight': 100,
            });
          }

          for (final groupName in _stringList(item['age_groups'])) {
            final ageGroupId = await _findAgeGroupByName(txn, groupName);
            if (ageGroupId != null) {
              await txn.insert('activity_age_groups', {
                'activity_id': activityId,
                'age_group_id': ageGroupId,
              });
            }
          }

          for (final tagName in _stringList(item['tags'])) {
            final tagId = await _ensureTag(txn, tagName);
            await txn.insert('activity_tags', {
              'activity_id': activityId,
              'tag_id': tagId,
            });
          }
        }
      }

      await txn.update('sync_state', {
        'last_sync_at': now,
        'content_version': contentVersion,
        'etag': payload['etag']?.toString(),
      }, where: 'id = 1');
    });

    return RemoteApplyResult(
      inserted: inserted,
      updated: updated,
      deleted: deleted,
      contentVersion: contentVersion,
    );
  }

  Future<Activity> _hydrateActivity(
    DatabaseExecutor executor,
    Map<String, Object?> row,
  ) async {
    final id = row['id'] as int;
    final domains = await _linkedNames(executor, '''
      select d.name
      from domains d
      join activity_domains ad on ad.domain_id = d.id
      where ad.activity_id = ?
      order by d.name
      ''', id);
    final ageGroups = await _linkedNames(executor, '''
      select ag.name
      from age_groups ag
      join activity_age_groups aag on aag.age_group_id = ag.id
      where aag.activity_id = ?
      order by ag.min_months
      ''', id);
    final tags = await _linkedNames(executor, '''
      select t.name
      from tags t
      join activity_tags at on at.tag_id = t.id
      where at.activity_id = ?
      order by t.name
      ''', id);

    return Activity.fromMap(
      row,
      domains: domains,
      ageGroups: ageGroups,
      tags: tags,
    );
  }

  Future<List<String>> _linkedNames(
    DatabaseExecutor executor,
    String sql,
    int activityId,
  ) async {
    final rows = await executor.rawQuery(sql, [activityId]);
    return rows.map((row) => row.values.first as String).toList();
  }

  Future<int> _ensureDomain(
    DatabaseExecutor executor,
    String name, {
    String? description,
  }) async {
    final trimmed = name.trim();
    final rows = await executor.query(
      'domains',
      where: 'name = ?',
      whereArgs: [trimmed],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final id = rows.first['id'] as int;
      if (description != null && description.trim().isNotEmpty) {
        await executor.update(
          'domains',
          {'description': description.trim()},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      return id;
    }
    return executor.insert('domains', {
      'name': trimmed,
      'description': description?.trim(),
    });
  }

  Future<int> _ensureAgeGroup(
    DatabaseExecutor executor,
    String name,
    int minMonths,
    int maxMonths,
  ) async {
    final trimmed = name.trim();
    final rows = await executor.query(
      'age_groups',
      where: 'name = ?',
      whereArgs: [trimmed],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final id = rows.first['id'] as int;
      await executor.update(
        'age_groups',
        {'min_months': minMonths, 'max_months': maxMonths},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    return executor.insert('age_groups', {
      'name': trimmed,
      'min_months': minMonths,
      'max_months': maxMonths,
    });
  }

  Future<int?> _findAgeGroupByName(
    DatabaseExecutor executor,
    String name,
  ) async {
    final rows = await executor.query(
      'age_groups',
      where: 'name = ?',
      whereArgs: [name.trim()],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['id'] as int;
  }

  Future<int> _ensureTag(DatabaseExecutor executor, String name) async {
    final trimmed = name.trim();
    final rows = await executor.query(
      'tags',
      where: 'name = ?',
      whereArgs: [trimmed],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return rows.first['id'] as int;
    }
    return executor.insert('tags', {'name': trimmed});
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static int _asBoolInt(Object? value) {
    if (value is bool) {
      return value ? 1 : 0;
    }
    if (value is num) {
      return value == 0 ? 0 : 1;
    }
    final string = value?.toString().toLowerCase();
    return string == 'true' || string == '1' ? 1 : 0;
  }

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
    }
    final string = value?.toString().trim();
    return string == null || string.isEmpty ? <String>[] : <String>[string];
  }

  static String _instructionFromItem(Map item) {
    final instruction = item['instruction']?.toString();
    if (instruction != null && instruction.trim().isNotEmpty) {
      return instruction.trim();
    }
    final steps = item['steps'];
    if (steps is List && steps.isNotEmpty) {
      return steps
          .asMap()
          .entries
          .map((entry) => '${entry.key + 1}) ${entry.value}')
          .join('\n');
    }
    return 'Откройте задание, подготовьте материалы и выполните шаги вместе с ребёнком.';
  }
}

const _seedDomains = <String, String>{
  'Речь': 'Артикуляция, словарь, связная речь и произношение.',
  'Внимание': 'Концентрация, переключение и зрительное внимание.',
  'Мелкая моторика': 'Пальчиковая гимнастика, координация и точность движений.',
  'Логика': 'Счёт, классификация, сравнение и причинно-следственные связи.',
  'Память': 'Запоминание, повторение и развитие слуховой памяти.',
  'Сенсорика': 'Цвет, форма, размер, фактура и восприятие.',
};

const _seedAgeGroups = <_SeedAgeGroup>[
  _SeedAgeGroup('3-4 года', 36, 47),
  _SeedAgeGroup('4-5 лет', 48, 59),
  _SeedAgeGroup('5-6 лет', 60, 71),
  _SeedAgeGroup('6-7 лет', 72, 83),
];

const _seedActivities = <_SeedActivity>[
  _SeedActivity(
    remoteId: 'builtin-clear-sounds',
    title: 'Чёткие звуки',
    shortDesc: 'Артикуляционная разминка и спокойное произношение слов.',
    instruction:
        '1) Попросите ребёнка улыбнуться и показать зубки на 5 секунд.\n'
        '2) Сделайте упражнение "лошадка": цоканье языком 10 раз.\n'
        '3) Произнесите вместе 5 слов с нужным звуком медленно и чётко.\n'
        '4) Похвалите ребёнка и отметьте выполнение в приложении.',
    durationMin: 7,
    difficulty: 2,
    materials: 'без материалов',
    safetyNotes: 'Не заставляйте повторять звук через силу, делайте паузы.',
    domains: ['Речь'],
    ageGroups: ['4-5 лет', '5-6 лет'],
    tags: ['артикуляция', 'дыхание', 'короткие'],
  ),
  _SeedActivity(
    remoteId: 'builtin-sound-r',
    title: 'Слова на звук Р',
    shortDesc: 'Подбор и повторение слов с заданным звуком.',
    instruction:
        '1) Назовите звук, который будете искать.\n'
        '2) Покажите карточки или предметы и попросите назвать слова.\n'
        '3) Повторите каждое слово медленно, выделяя звук.\n'
        '4) Попросите ребёнка придумать ещё одно слово.',
    durationMin: 7,
    difficulty: 3,
    materials: 'карточки с предметами',
    safetyNotes:
        'Если звук ещё не поставлен, используйте задание как игру на слух.',
    domains: ['Речь'],
    ageGroups: ['5-6 лет', '6-7 лет'],
    tags: ['звук Р', 'карточки'],
  ),
  _SeedActivity(
    remoteId: 'builtin-find-difference',
    title: 'Найди отличие',
    shortDesc: 'Поиск отличий на двух похожих картинках.',
    instruction:
        '1) Положите перед ребёнком две похожие картинки.\n'
        '2) Дайте 30 секунд на спокойное рассматривание.\n'
        '3) Попросите назвать или показать отличия.\n'
        '4) Обсудите, какие признаки помогли найти ответ.',
    durationMin: 5,
    difficulty: 2,
    materials: 'карточки или картинки',
    domains: ['Внимание'],
    ageGroups: ['4-5 лет', '5-6 лет'],
    tags: ['зрительное внимание', 'короткие'],
  ),
  _SeedActivity(
    remoteId: 'builtin-finger-warmup',
    title: 'Пальчиковая разминка',
    shortDesc: 'Короткая гимнастика для развития точности движений.',
    instruction:
        '1) Покажите движение "кулачок-ладошка".\n'
        '2) Повторите его вместе 8-10 раз.\n'
        '3) Соединяйте большой палец по очереди с каждым пальцем.\n'
        '4) Завершите мягким растиранием ладоней.',
    durationMin: 4,
    difficulty: 1,
    materials: 'без материалов',
    domains: ['Мелкая моторика'],
    ageGroups: ['3-4 года', '4-5 лет'],
    tags: ['пальчики', 'короткие'],
  ),
  _SeedActivity(
    remoteId: 'builtin-count-objects',
    title: 'Счёт предметов',
    shortDesc: 'Счёт небольшого набора предметов и сравнение количества.',
    instruction:
        '1) Разложите 5-10 одинаковых предметов.\n'
        '2) Попросите ребёнка пересчитать их слева направо.\n'
        '3) Добавьте или уберите один предмет и задайте вопрос "сколько стало?".\n'
        '4) Сравните две группы: где больше, где меньше.',
    durationMin: 10,
    difficulty: 2,
    materials: 'кубики, монетки или пуговицы',
    domains: ['Логика'],
    ageGroups: ['4-5 лет', '5-6 лет'],
    tags: ['счёт', 'предметы'],
  ),
  _SeedActivity(
    remoteId: 'builtin-remember-toys',
    title: 'Запомни игрушки',
    shortDesc: 'Развитие зрительной памяти через запоминание предметов.',
    instruction:
        '1) Положите на стол 4-6 игрушек.\n'
        '2) Дайте ребёнку рассмотреть их 20 секунд.\n'
        '3) Накройте игрушки салфеткой и попросите назвать, что он запомнил.\n'
        '4) Усложните игру, убрав один предмет.',
    durationMin: 6,
    difficulty: 2,
    materials: '4-6 небольших игрушек',
    domains: ['Память', 'Внимание'],
    ageGroups: ['4-5 лет', '5-6 лет'],
    tags: ['память', 'короткие'],
  ),
  _SeedActivity(
    remoteId: 'builtin-color-pairs',
    title: 'Цветные пары',
    shortDesc: 'Подбор предметов одинакового цвета.',
    instruction:
        '1) Подготовьте предметы 3-4 цветов.\n'
        '2) Покажите образец и попросите найти предмет такого же цвета.\n'
        '3) Назовите цвет вслух.\n'
        '4) Попросите ребёнка собрать пары самостоятельно.',
    durationMin: 5,
    difficulty: 1,
    materials: 'цветные карточки или игрушки',
    domains: ['Сенсорика'],
    ageGroups: ['3-4 года', '4-5 лет'],
    tags: ['цвет', 'пары', 'короткие'],
  ),
  _SeedActivity(
    remoteId: 'builtin-follow-clap',
    title: 'Следи за хлопком',
    shortDesc: 'Переключение внимания по звуковому сигналу.',
    instruction:
        '1) Договоритесь: один хлопок - шаг, два хлопка - остановка.\n'
        '2) Потренируйтесь медленно.\n'
        '3) Меняйте ритм хлопков и следите за реакцией.\n'
        '4) Завершите спокойным повторением правил.',
    durationMin: 5,
    difficulty: 2,
    materials: 'без материалов',
    domains: ['Внимание'],
    ageGroups: ['4-5 лет', '5-6 лет'],
    tags: ['слуховое внимание', 'короткие'],
  ),
  _SeedActivity(
    remoteId: 'builtin-picture-story',
    title: 'История по картинке',
    shortDesc: 'Составление короткого рассказа по сюжетной картинке.',
    instruction:
        '1) Рассмотрите картинку вместе.\n'
        '2) Спросите, кто изображён и что происходит.\n'
        '3) Попросите ребёнка сказать, что было сначала и что будет потом.\n'
        '4) Повторите рассказ целиком в 3-4 предложениях.',
    durationMin: 10,
    difficulty: 3,
    materials: 'сюжетная картинка',
    domains: ['Речь', 'Логика'],
    ageGroups: ['5-6 лет', '6-7 лет'],
    tags: ['рассказ', 'последовательность'],
  ),
  _SeedActivity(
    remoteId: 'builtin-finger-maze',
    title: 'Лабиринт пальчиком',
    shortDesc: 'Проведение пальцем по линии без отрыва.',
    instruction:
        '1) Покажите дорожку или простой лабиринт.\n'
        '2) Попросите вести пальцем от старта до финиша.\n'
        '3) Следите, чтобы ребёнок не торопился.\n'
        '4) Повторите задание другой рукой.',
    durationMin: 6,
    difficulty: 2,
    materials: 'лист с лабиринтом или дорожкой',
    domains: ['Мелкая моторика', 'Внимание'],
    ageGroups: ['4-5 лет', '5-6 лет'],
    tags: ['координация', 'короткие'],
  ),
  _SeedActivity(
    remoteId: 'builtin-odd-one-out',
    title: 'Четвёртый лишний',
    shortDesc: 'Поиск предмета, который не подходит к группе.',
    instruction:
        '1) Назовите четыре предмета, три из которых похожи по признаку.\n'
        '2) Попросите ребёнка найти лишний предмет.\n'
        '3) Обязательно спросите, почему он так решил.\n'
        '4) Предложите придумать свой набор.',
    durationMin: 8,
    difficulty: 3,
    materials: 'карточки или устные примеры',
    domains: ['Логика', 'Речь'],
    ageGroups: ['5-6 лет', '6-7 лет'],
    tags: ['классификация', 'объяснение'],
  ),
  _SeedActivity(
    remoteId: 'builtin-rhythm-claps',
    title: 'Ритмичные хлопки',
    shortDesc: 'Повторение простых ритмов на слух.',
    instruction:
        '1) Хлопните простой ритм из 3-4 звуков.\n'
        '2) Попросите ребёнка повторить.\n'
        '3) Меняйтесь ролями: ребёнок задаёт ритм, взрослый повторяет.\n'
        '4) Постепенно увеличивайте длину ритма.',
    durationMin: 5,
    difficulty: 2,
    materials: 'без материалов',
    domains: ['Память', 'Внимание'],
    ageGroups: ['4-5 лет', '5-6 лет', '6-7 лет'],
    tags: ['слуховая память', 'короткие'],
  ),
];

class _SeedAgeGroup {
  const _SeedAgeGroup(this.name, this.minMonths, this.maxMonths);

  final String name;
  final int minMonths;
  final int maxMonths;
}

class _SeedActivity {
  const _SeedActivity({
    required this.remoteId,
    required this.title,
    required this.shortDesc,
    required this.instruction,
    required this.durationMin,
    required this.difficulty,
    required this.materials,
    required this.domains,
    required this.ageGroups,
    required this.tags,
    this.safetyNotes,
  });

  final String remoteId;
  final String title;
  final String shortDesc;
  final String instruction;
  final int durationMin;
  final int difficulty;
  final String materials;
  final String? safetyNotes;
  final List<String> domains;
  final List<String> ageGroups;
  final List<String> tags;
}
