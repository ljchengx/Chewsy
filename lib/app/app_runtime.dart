import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';

import '../data/database/app_database.dart';
import '../data/repositories/record_repository.dart';
import '../domain/demo_records.dart';
import '../services/backup_service.dart';
import '../services/media_store.dart';

class AppRuntime {
  AppRuntime({
    required this.database,
    required this.mediaStore,
    required this.records,
    required this.backup,
  });

  final AppDatabase database;
  final MediaStore mediaStore;
  final DriftRecordRepository records;
  final BackupService backup;

  static Future<AppRuntime> bootstrap() async {
    final mediaStore = MediaStore();
    await mediaStore.initialize();
    final database = AppDatabase();
    final records = DriftRecordRepository(
      database: database,
      mediaStore: mediaStore,
    );
    await records.recoverImportJobs();
    await mediaStore.deleteTemporaryWorkspaces();
    if (kDebugMode) {
      await records.seedDebugRecords(demoRecords);
    }
    final backup = LocalBackupService(
      repository: records,
      mediaStore: mediaStore,
    );
    return AppRuntime(
      database: database,
      mediaStore: mediaStore,
      records: records,
      backup: backup,
    );
  }

  static Future<AppRuntime> forTesting() async {
    final mediaStore = MediaStore.forTesting();
    final database = AppDatabase(executor: NativeDatabase.memory());
    final records = DriftRecordRepository(
      database: database,
      mediaStore: mediaStore,
    );
    final backup = LocalBackupService(
      repository: records,
      mediaStore: mediaStore,
    );
    return AppRuntime(
      database: database,
      mediaStore: mediaStore,
      records: records,
      backup: backup,
    );
  }

  Future<void> dispose() => database.close();
}

final appRuntimeProvider = Provider<AppRuntime>((ref) {
  throw StateError('AppRuntime has not been provided.');
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return ref.read(appRuntimeProvider).backup;
});
