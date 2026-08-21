import 'models.dart';

class BackupRequest {
  const BackupRequest();
}

class ImportRequest {
  const ImportRequest({required this.filePath});

  final String filePath;
}

class SnapshotMedia {
  const SnapshotMedia({required this.metadata, required this.bytes});

  final Map<String, dynamic> metadata;
  final List<int> bytes;
}

class BackupSnapshot {
  const BackupSnapshot({
    required this.restaurants,
    required this.records,
    required this.items,
    required this.tags,
    required this.recordTags,
    required this.revisions,
    required this.media,
  });

  final List<Map<String, dynamic>> restaurants;
  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> tags;
  final List<Map<String, dynamic>> recordTags;
  final List<Map<String, dynamic>> revisions;
  final List<SnapshotMedia> media;
}

enum ConflictResolution { keepLocal, useBackup, duplicate }

class ConflictItem {
  const ConflictItem({
    required this.recordId,
    required this.local,
    required this.remote,
  });

  final MealRecord local;
  final MealRecord remote;
  final String recordId;
}

class BackupInspection {
  const BackupInspection({
    required this.backupId,
    required this.snapshot,
    required this.counts,
    required this.conflicts,
    this.stagingPath,
    this.alreadyImported = false,
  });

  final String backupId;
  final BackupSnapshot snapshot;
  final ImportCounts counts;
  final List<ConflictItem> conflicts;
  final String? stagingPath;
  final bool alreadyImported;
}

class ImportPlan {
  const ImportPlan({
    required this.inspection,
    this.resolutions = const <String, ConflictResolution>{},
  });

  final BackupInspection inspection;
  final Map<String, ConflictResolution> resolutions;

  bool get isReady => inspection.conflicts.every(resolutions.containsKey);

  ImportPlan resolve(String recordId, ConflictResolution resolution) {
    return ImportPlan(
      inspection: inspection,
      resolutions: {...resolutions, recordId: resolution},
    );
  }
}

class ImportResult {
  const ImportResult({required this.counts, this.alreadyImported = false});

  final ImportCounts counts;
  final bool alreadyImported;
}
