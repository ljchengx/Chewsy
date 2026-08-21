import 'dart:convert';

enum Verdict { keep, skip, neutral }

extension VerdictDetails on Verdict {
  String get label {
    switch (this) {
      case Verdict.keep:
        return '种草';
      case Verdict.skip:
        return '踩雷';
      case Verdict.neutral:
        return '观望';
    }
  }

  String get phrase {
    switch (this) {
      case Verdict.keep:
        return '值得再去';
      case Verdict.skip:
        return '下次避开';
      case Verdict.neutral:
        return '再看看';
    }
  }

  String get storageValue {
    switch (this) {
      case Verdict.keep:
        return 'keep';
      case Verdict.skip:
        return 'avoid';
      case Verdict.neutral:
        return 'neutral';
    }
  }

  static Verdict fromStorage(String value) {
    switch (value) {
      case 'keep':
        return Verdict.keep;
      case 'avoid':
      case 'skip':
        return Verdict.skip;
      case 'neutral':
      default:
        return Verdict.neutral;
    }
  }

  int get sortRank {
    switch (this) {
      case Verdict.keep:
        return 0;
      case Verdict.neutral:
        return 1;
      case Verdict.skip:
        return 2;
    }
  }
}

class MealRecord {
  const MealRecord({
    required this.restaurant,
    required this.dishes,
    required this.verdict,
    required this.reasons,
    required this.photo,
    required this.eatenAt,
    this.note = '',
    this.id = '',
    this.restaurantId,
    this.createdAt,
    this.updatedAt,
    this.revision = 1,
    this.deletedAt,
    this.contentHash,
    this.mediaHash,
    this.time,
  });

  final String id;
  final String restaurant;
  final String? restaurantId;
  final List<String> dishes;
  final Verdict verdict;
  final List<String> reasons;
  final String photo;
  final String note;
  final DateTime eatenAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int revision;
  final DateTime? deletedAt;
  final String? contentHash;
  final String? mediaHash;
  final String? time;

  bool get isDeleted => deletedAt != null;

  String get displayDishes => dishes.isEmpty ? '店铺整体体验' : dishes.join('、');

  RecordDraft toDraft() => RecordDraft(
    restaurant: restaurant,
    dishes: dishes,
    verdict: verdict,
    reasons: reasons.toSet(),
    note: note,
    photoPath: photo.isEmpty ? null : photo,
    eatenAt: eatenAt,
  );

  MealRecord copyWith({
    String? id,
    String? restaurant,
    String? restaurantId,
    List<String>? dishes,
    Verdict? verdict,
    List<String>? reasons,
    String? photo,
    String? note,
    DateTime? eatenAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? revision,
    DateTime? deletedAt,
    String? contentHash,
    String? mediaHash,
    String? time,
  }) {
    return MealRecord(
      id: id ?? this.id,
      restaurant: restaurant ?? this.restaurant,
      restaurantId: restaurantId ?? this.restaurantId,
      dishes: dishes ?? this.dishes,
      verdict: verdict ?? this.verdict,
      reasons: reasons ?? this.reasons,
      photo: photo ?? this.photo,
      note: note ?? this.note,
      eatenAt: eatenAt ?? this.eatenAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
      deletedAt: deletedAt ?? this.deletedAt,
      contentHash: contentHash ?? this.contentHash,
      mediaHash: mediaHash ?? this.mediaHash,
      time: time ?? this.time,
    );
  }
}

class RecordDraft {
  const RecordDraft({
    required this.verdict,
    required this.eatenAt,
    this.restaurant = '',
    this.dishes = const <String>[],
    this.note = '',
    this.reasons = const <String>{},
    this.photoPath,
    this.updatedAt,
  });

  final Verdict verdict;
  final DateTime eatenAt;
  final String restaurant;
  final List<String> dishes;
  final String note;
  final Set<String> reasons;
  final String? photoPath;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
    'verdict': verdict.storageValue,
    'restaurant': restaurant,
    'dishes': dishes,
    'note': note,
    'reasons': reasons.toList()..sort(),
    'photoPath': photoPath,
    'eatenAt': eatenAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };

  factory RecordDraft.fromJson(Map<String, dynamic> json) {
    final dishes = (json['dishes'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .toList();
    return RecordDraft(
      verdict: VerdictDetails.fromStorage(
        json['verdict'] as String? ?? 'neutral',
      ),
      eatenAt:
          DateTime.tryParse(json['eatenAt'] as String? ?? '') ?? DateTime.now(),
      restaurant: json['restaurant'] as String? ?? '',
      dishes: dishes,
      note: json['note'] as String? ?? '',
      reasons: ((json['reasons'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<String>()
          .toSet(),
      photoPath: json['photoPath'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  String encode() => jsonEncode(toJson());

  factory RecordDraft.decode(String value) =>
      RecordDraft.fromJson(jsonDecode(value) as Map<String, dynamic>);

  RecordDraft copyWith({
    Verdict? verdict,
    DateTime? eatenAt,
    String? restaurant,
    List<String>? dishes,
    String? note,
    Set<String>? reasons,
    String? photoPath,
    DateTime? updatedAt,
  }) {
    return RecordDraft(
      verdict: verdict ?? this.verdict,
      eatenAt: eatenAt ?? this.eatenAt,
      restaurant: restaurant ?? this.restaurant,
      dishes: dishes ?? this.dishes,
      note: note ?? this.note,
      reasons: reasons ?? this.reasons,
      photoPath: photoPath ?? this.photoPath,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class RecordQuery {
  const RecordQuery({
    this.search = '',
    this.verdict,
    this.includeDeleted = false,
    this.limit,
  });

  final String search;
  final Verdict? verdict;
  final bool includeDeleted;
  final int? limit;
}

class RestaurantSearchResult {
  const RestaurantSearchResult({
    required this.id,
    required this.name,
    required this.visitCount,
    required this.latestEatenAt,
    required this.latestVerdict,
    required this.recentDishes,
    required this.matchedDishes,
  });

  final String id;
  final String name;
  final int visitCount;
  final DateTime? latestEatenAt;
  final Verdict? latestVerdict;
  final List<String> recentDishes;
  final List<String> matchedDishes;
}

class RestaurantHistory {
  const RestaurantHistory({
    required this.restaurantId,
    required this.restaurant,
    required this.visits,
  });

  final String restaurantId;
  final String restaurant;
  final List<MealRecord> visits;
}

class RecordCounts {
  const RecordCounts({required this.records, required this.images});

  final int records;
  final int images;
}

class StoredMedia {
  const StoredMedia({
    required this.relativePath,
    required this.thumbnailPath,
    required this.sha256,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.byteSize,
  });

  final String relativePath;
  final String thumbnailPath;
  final String sha256;
  final String mimeType;
  final int? width;
  final int? height;
  final int byteSize;
}

class BackupArtifact {
  const BackupArtifact({
    required this.filePath,
    required this.backupId,
    required this.byteSize,
  });

  final String filePath;
  final String backupId;
  final int byteSize;
}

class BackupProgress {
  const BackupProgress({required this.stage, required this.fraction});

  final String stage;
  final double fraction;
}

class ImportCounts {
  const ImportCounts({
    this.added = 0,
    this.existing = 0,
    this.updated = 0,
    this.skipped = 0,
    this.deleted = 0,
    this.conflicts = 0,
  });

  final int added;
  final int existing;
  final int updated;
  final int skipped;
  final int deleted;
  final int conflicts;
}
