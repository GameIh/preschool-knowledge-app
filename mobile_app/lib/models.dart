class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.name,
    this.birthDate,
    this.ageMonths,
    this.notes,
  });

  final int id;
  final String name;
  final String? birthDate;
  final int? ageMonths;
  final String? notes;

  factory ChildProfile.fromMap(Map<String, Object?> map) {
    return ChildProfile(
      id: map['id'] as int,
      name: map['name'] as String,
      birthDate: map['birth_date'] as String?,
      ageMonths: map['age_months'] as int?,
      notes: map['notes'] as String?,
    );
  }

  String get ageLabel {
    final months = ageMonths;
    if (months == null || months <= 0) {
      return 'возраст не указан';
    }

    final years = months ~/ 12;
    final rest = months % 12;
    final yearWord = _plural(years, 'год', 'года', 'лет');
    if (rest == 0) {
      return '$years $yearWord';
    }
    final monthWord = _plural(rest, 'месяц', 'месяца', 'месяцев');
    return '$years $yearWord $rest $monthWord';
  }
}

class Activity {
  const Activity({
    required this.id,
    required this.remoteId,
    required this.version,
    required this.source,
    required this.updatedAt,
    required this.title,
    required this.instruction,
    required this.durationMin,
    required this.difficulty,
    this.shortDesc,
    this.materials,
    this.safetyNotes,
    this.domains = const [],
    this.ageGroups = const [],
    this.tags = const [],
  });

  final int id;
  final String? remoteId;
  final int version;
  final String source;
  final String updatedAt;
  final String title;
  final String? shortDesc;
  final String instruction;
  final int durationMin;
  final int difficulty;
  final String? materials;
  final String? safetyNotes;
  final List<String> domains;
  final List<String> ageGroups;
  final List<String> tags;

  factory Activity.fromMap(
    Map<String, Object?> map, {
    List<String> domains = const [],
    List<String> ageGroups = const [],
    List<String> tags = const [],
  }) {
    return Activity(
      id: map['id'] as int,
      remoteId: map['remote_id'] as String?,
      version: map['version'] as int? ?? 1,
      source: map['source'] as String? ?? 'builtin',
      updatedAt: map['updated_at'] as String? ?? '',
      title: map['title'] as String,
      shortDesc: map['short_desc'] as String?,
      instruction: map['instruction'] as String,
      durationMin: map['duration_min'] as int? ?? 5,
      difficulty: map['difficulty'] as int? ?? 1,
      materials: map['materials'] as String?,
      safetyNotes: map['safety_notes'] as String?,
      domains: domains,
      ageGroups: ageGroups,
      tags: tags,
    );
  }

  String get domainLabel =>
      domains.isEmpty ? 'Без категории' : domains.join(', ');

  String get ageLabel =>
      ageGroups.isEmpty ? 'любой возраст' : ageGroups.join(', ');

  String get materialsLabel {
    final value = materials?.trim();
    return value == null || value.isEmpty ? 'без материалов' : value;
  }
}

class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.childId,
    required this.activityId,
    required this.dateTime,
    required this.status,
    this.rating,
    this.comment,
    this.childName,
    this.activityTitle,
  });

  final int id;
  final int childId;
  final int activityId;
  final String dateTime;
  final String status;
  final int? rating;
  final String? comment;
  final String? childName;
  final String? activityTitle;

  factory ActivityLog.fromMap(Map<String, Object?> map) {
    return ActivityLog(
      id: map['id'] as int,
      childId: map['child_id'] as int,
      activityId: map['activity_id'] as int,
      dateTime: map['date_time'] as String,
      status: map['status'] as String,
      rating: map['rating'] as int?,
      comment: map['comment'] as String?,
      childName: map['child_name'] as String?,
      activityTitle: map['activity_title'] as String?,
    );
  }
}

class SyncStateInfo {
  const SyncStateInfo({this.lastSyncAt, this.contentVersion, this.etag});

  final String? lastSyncAt;
  final String? contentVersion;
  final String? etag;

  factory SyncStateInfo.fromMap(Map<String, Object?> map) {
    return SyncStateInfo(
      lastSyncAt: map['last_sync_at'] as String?,
      contentVersion: map['content_version'] as String?,
      etag: map['etag'] as String?,
    );
  }
}

class SyncSession {
  const SyncSession({
    required this.id,
    required this.startedAt,
    this.finishedAt,
    required this.status,
    required this.source,
    this.errorMessage,
  });

  final int id;
  final String startedAt;
  final String? finishedAt;
  final String status;
  final String source;
  final String? errorMessage;

  factory SyncSession.fromMap(Map<String, Object?> map) {
    return SyncSession(
      id: map['id'] as int,
      startedAt: map['started_at'] as String,
      finishedAt: map['finished_at'] as String?,
      status: map['status'] as String,
      source: map['source'] as String? ?? 'api',
      errorMessage: map['error_message'] as String?,
    );
  }
}

class RemoteApplyResult {
  const RemoteApplyResult({
    required this.inserted,
    required this.updated,
    required this.deleted,
    this.contentVersion,
  });

  final int inserted;
  final int updated;
  final int deleted;
  final String? contentVersion;
}

String _plural(int value, String one, String few, String many) {
  final mod10 = value % 10;
  final mod100 = value % 100;
  if (mod10 == 1 && mod100 != 11) {
    return one;
  }
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return few;
  }
  return many;
}
