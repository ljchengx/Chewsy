import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/backup_models.dart';
import '../../domain/models.dart' as domain;
import '../../services/media_store.dart';
import '../database/app_database.dart' as db;

abstract class RecordStore {
  Future<List<domain.MealRecord>> loadRecords({domain.RecordQuery query});

  Stream<List<domain.MealRecord>> watchRecords({domain.RecordQuery query});

  Future<domain.RecordCounts> loadCounts();

  Future<domain.RecordDraft?> loadDraft();

  Future<void> saveDraft(domain.RecordDraft draft);

  Future<void> clearDraft();

  Future<String> stageDraftPhoto(String sourcePath);

  Future<domain.MealRecord> publishDraft(domain.RecordDraft draft);

  Future<domain.MealRecord> updateRecord({
    required String recordId,
    required domain.RecordDraft draft,
  });

  Future<void> deleteRecord(String recordId);

  Future<List<domain.RestaurantSearchResult>> searchRestaurants(
    String query, {
    int limit = 20,
  });

  Future<domain.RestaurantHistory> loadRestaurantHistory(String restaurantId);

  Future<List<String>> suggestRestaurantNames(String query, {int limit = 8});

  Future<void> seedDebugRecords(List<domain.MealRecord> records);

  Future<BackupSnapshot> createBackupSnapshot();

  Future<BackupInspection> inspectBackupSnapshot({
    required String backupId,
    required BackupSnapshot snapshot,
    String? stagingPath,
  });

  Future<ImportResult> commitImport(ImportPlan plan);

  Future<void> recoverImportJobs();
}

class DriftRecordRepository implements RecordStore {
  DriftRecordRepository({required this.database, required this.mediaStore});

  final db.AppDatabase database;
  final MediaStore mediaStore;
  final Uuid _uuid = const Uuid();
  Future<void> _draftTail = Future<void>.value();
  int _draftGeneration = 0;

  @override
  Future<List<domain.MealRecord>> loadRecords({
    domain.RecordQuery query = const domain.RecordQuery(),
  }) async {
    final rows = await database.select(database.mealRecords).get();
    final restaurants = {
      for (final row in await database.select(database.restaurants).get())
        row.id: row,
    };
    final itemsByRecord = <String, List<db.MealItem>>{};
    for (final item in await database.select(database.mealItems).get()) {
      (itemsByRecord[item.recordId] ??= <db.MealItem>[]).add(item);
    }
    final tags = {
      for (final tag in await database.select(database.tags).get()) tag.id: tag,
    };
    final reasonsByRecord = <String, List<String>>{};
    for (final relation in await database.select(database.recordTags).get()) {
      final name = tags[relation.tagId]?.name;
      if (name != null && name.trim().isNotEmpty) {
        (reasonsByRecord[relation.recordId] ??= <String>[]).add(name);
      }
    }
    final mediaByRecord = <String, db.MediaAsset>{};
    for (final media in await (database.select(
      database.mediaAssets,
    )..where((row) => row.state.equals('ready'))).get()) {
      mediaByRecord.putIfAbsent(media.recordId, () => media);
    }

    final normalizedSearch = query.search.trim().toLowerCase();
    final result = <domain.MealRecord>[];
    for (final row in rows) {
      if (!query.includeDeleted && row.deletedAt != null) continue;
      if (query.verdict != null && row.verdict != query.verdict!.storageValue) {
        continue;
      }
      final restaurant = restaurants[row.restaurantId];
      final dishes = (itemsByRecord[row.id] ?? const <db.MealItem>[])
          .map((item) => item.name.trim())
          .where((name) => name.isNotEmpty)
          .toList();
      final reasons = [...(reasonsByRecord[row.id] ?? const <String>[])];
      final media = mediaByRecord[row.id];
      final record = domain.MealRecord(
        id: row.id,
        restaurant: restaurant?.name ?? '未命名店铺',
        restaurantId: row.restaurantId,
        dishes: dishes,
        verdict: domain.VerdictDetails.fromStorage(row.verdict),
        reasons: reasons,
        photo: media == null ? '' : mediaStore.absolutePath(media.relativePath),
        time: _formatTime(row.eatenAt),
        note: row.note,
        eatenAt: row.eatenAt,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        revision: row.revision,
        deletedAt: row.deletedAt,
        contentHash: row.contentHash,
        mediaHash: media?.sha256,
      );
      final searchable = <String>[
        restaurant?.name ?? '',
        restaurant?.alias ?? '',
        ...dishes,
        ...reasons,
        row.note,
      ];
      if (normalizedSearch.isNotEmpty &&
          !searchable.any(
            (value) => value.toLowerCase().contains(normalizedSearch),
          )) {
        continue;
      }
      result.add(record);
    }
    result.sort((a, b) {
      final left = a.eatenAt;
      final right = b.eatenAt;
      return right.compareTo(left);
    });
    if (query.limit != null && result.length > query.limit!) {
      return result.take(query.limit!).toList();
    }
    return result;
  }

  @override
  Stream<List<domain.MealRecord>> watchRecords({
    domain.RecordQuery query = const domain.RecordQuery(),
  }) {
    return database
        .select(database.mealRecords)
        .watch()
        .asyncMap((_) => loadRecords(query: query));
  }

  @override
  Future<List<domain.RestaurantSearchResult>> searchRestaurants(
    String query, {
    int limit = 20,
  }) async {
    final normalized = query.trim().toLowerCase();
    final allRecords = await loadRecords(
      query: const domain.RecordQuery(limit: 10000),
    );
    final matchingRecords = await loadRecords(
      query: domain.RecordQuery(search: query, limit: 10000),
    );
    final allByRestaurant = <String, List<domain.MealRecord>>{};
    for (final record in allRecords) {
      final id = record.restaurantId ?? record.restaurant;
      (allByRestaurant[id] ??= <domain.MealRecord>[]).add(record);
    }
    final matchingByRestaurant = <String, List<domain.MealRecord>>{};
    for (final record in matchingRecords) {
      final id = record.restaurantId ?? record.restaurant;
      (matchingByRestaurant[id] ??= <domain.MealRecord>[]).add(record);
    }
    final restaurants = {
      for (final row in await database.select(database.restaurants).get())
        row.id: row,
    };
    final results = matchingByRestaurant.keys.map((restaurantId) {
      final visits = [
        ...(allByRestaurant[restaurantId] ?? const <domain.MealRecord>[]),
      ]..sort((a, b) => b.eatenAt.compareTo(a.eatenAt));
      final matchedDishes = <String>{};
      if (normalized.isNotEmpty) {
        for (final visit
            in matchingByRestaurant[restaurantId] ??
                const <domain.MealRecord>[]) {
          for (final dish in visit.dishes) {
            if (dish.toLowerCase().contains(normalized)) {
              matchedDishes.add(dish);
            }
          }
        }
      }
      final restaurant = restaurants[restaurantId];
      return domain.RestaurantSearchResult(
        id: restaurantId,
        name: restaurant?.name ?? visits.first.restaurant,
        visitCount: visits.length,
        latestEatenAt: visits.first.eatenAt,
        latestVerdict: visits.first.verdict,
        recentDishes: visits
            .expand((visit) => visit.dishes)
            .where((dish) => dish.isNotEmpty)
            .toSet()
            .take(5)
            .toList(),
        matchedDishes: matchedDishes.toList(),
      );
    }).toList();
    results.sort(
      (a, b) => (b.latestEatenAt ?? DateTime(0)).compareTo(
        a.latestEatenAt ?? DateTime(0),
      ),
    );
    return results.take(limit).toList();
  }

  @override
  Future<domain.RestaurantHistory> loadRestaurantHistory(
    String restaurantId,
  ) async {
    final restaurant = await (database.select(
      database.restaurants,
    )..where((row) => row.id.equals(restaurantId))).getSingleOrNull();
    final visits = await loadRecords(
      query: const domain.RecordQuery(limit: 10000),
    );
    final history =
        visits.where((record) => record.restaurantId == restaurantId).toList()
          ..sort((a, b) => b.eatenAt.compareTo(a.eatenAt));
    return domain.RestaurantHistory(
      restaurantId: restaurantId,
      restaurant:
          restaurant?.name ??
          (history.isEmpty ? '未命名店铺' : history.first.restaurant),
      visits: history,
    );
  }

  @override
  Future<List<String>> suggestRestaurantNames(
    String query, {
    int limit = 8,
  }) async {
    final normalized = query.trim().toLowerCase();
    final rows = await database.select(database.restaurants).get();
    final activeRecords = await (database.select(
      database.mealRecords,
    )..where((row) => row.deletedAt.isNull())).get();
    final activeRestaurantIds = activeRecords
        .map((row) => row.restaurantId)
        .toSet();
    final names = rows
        .where(
          (row) =>
              activeRestaurantIds.contains(row.id) &&
              (normalized.isEmpty ||
                  row.name.toLowerCase().contains(normalized) ||
                  (row.alias ?? '').toLowerCase().contains(normalized)),
        )
        .map((row) => row.name)
        .toSet()
        .toList();
    return names.take(limit).toList();
  }

  @override
  Future<domain.RecordCounts> loadCounts() async {
    final records = await (database.select(
      database.mealRecords,
    )..where((row) => row.deletedAt.isNull())).get();
    final media = await (database.select(
      database.mediaAssets,
    )..where((row) => row.state.equals('ready'))).get();
    return domain.RecordCounts(records: records.length, images: media.length);
  }

  @override
  Future<domain.RecordDraft?> loadDraft() async {
    final row = await (database.select(
      database.drafts,
    )..where((item) => item.id.equals('active'))).getSingleOrNull();
    if (row == null) return null;
    try {
      return domain.RecordDraft.decode(row.payloadJson);
    } on Object {
      await clearDraft();
      return null;
    }
  }

  @override
  Future<void> saveDraft(domain.RecordDraft draft) async {
    final generation = _draftGeneration;
    final operation = _draftTail.then((_) async {
      if (generation != _draftGeneration) return;
      final now = DateTime.now().toUtc();
      await database
          .into(database.drafts)
          .insertOnConflictUpdate(
            db.DraftsCompanion.insert(
              id: 'active',
              payloadJson: draft.copyWith(updatedAt: now).encode(),
              updatedAt: now,
            ),
          );
    });
    _draftTail = operation.then<void>((_) {}, onError: (error, stackTrace) {});
    await operation;
  }

  @override
  Future<void> clearDraft() async {
    _draftGeneration++;
    final operation = _draftTail.then((_) async {
      await (database.delete(
        database.drafts,
      )..where((row) => row.id.equals('active'))).go();
      try {
        await mediaStore.deleteDraftFiles();
      } on Object {
        // 草稿清理失败不应影响记录已经提交的结果。
      }
    });
    _draftTail = operation.then<void>((_) {}, onError: (error, stackTrace) {});
    await operation;
  }

  @override
  Future<String> stageDraftPhoto(String sourcePath) {
    return mediaStore.stageDraftFile(sourcePath);
  }

  @override
  Future<domain.MealRecord> publishDraft(domain.RecordDraft draft) async {
    _validateDraft(draft);
    final now = DateTime.now().toUtc();
    final recordId = _uuid.v4();
    final restaurantId = _uuid.v4();
    final normalizedName = _normalize(draft.restaurant);
    StoredMediaForRecord? media;

    if (draft.photoPath != null && draft.photoPath!.isNotEmpty) {
      media = await _prepareMedia(draft.photoPath!);
    }

    final hash = await _contentHash(
      restaurant: draft.restaurant,
      dishes: draft.dishes,
      verdict: draft.verdict,
      note: draft.note,
      reasons: draft.reasons,
      mediaHash: media?.stored.sha256,
      eatenAt: draft.eatenAt,
    );

    try {
      await database.transaction(() async {
        final existing =
            await (database.select(database.restaurants)
                  ..where((row) => row.normalizedName.equals(normalizedName)))
                .getSingleOrNull();
        final actualRestaurantId = existing?.id ?? restaurantId;
        if (existing == null) {
          await database
              .into(database.restaurants)
              .insert(
                db.RestaurantsCompanion.insert(
                  id: actualRestaurantId,
                  name: draft.restaurant.trim(),
                  normalizedName: normalizedName,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        } else {
          await (database.update(database.restaurants)
                ..where((row) => row.id.equals(existing.id)))
              .write(db.RestaurantsCompanion(updatedAt: Value(now)));
        }

        await database
            .into(database.mealRecords)
            .insert(
              db.MealRecordsCompanion.insert(
                id: recordId,
                restaurantId: actualRestaurantId,
                verdict: draft.verdict.storageValue,
                note: Value(draft.note.trim()),
                eatenAt: draft.eatenAt.toUtc(),
                createdAt: now,
                updatedAt: now,
                contentHash: hash,
              ),
            );
        await _replaceItems(recordId, draft);
        await _replaceTags(recordId, draft.reasons);
        if (media != null) await _insertMedia(recordId, media.stored, now);
        await _insertRevision(
          recordId: recordId,
          revision: 1,
          hash: hash,
          draft: draft,
          mediaHash: media?.stored.sha256,
          changedAt: now,
        );
      });
      await clearDraft();
    } catch (_) {
      if (media != null) await _deleteIfUnreferenced(media.stored);
      rethrow;
    }

    final records = await loadRecords(
      query: const domain.RecordQuery(limit: 20),
    );
    return records.firstWhere((record) => record.id == recordId);
  }

  @override
  Future<domain.MealRecord> updateRecord({
    required String recordId,
    required domain.RecordDraft draft,
  }) async {
    _validateDraft(draft);
    final old = await _loadRecordById(recordId, includeDeleted: true);
    if (old == null) throw StateError('记录不存在');
    final now = DateTime.now().toUtc();
    final normalizedName = _normalize(draft.restaurant);
    final restaurantId = _uuid.v4();
    StoredMediaForRecord? media;
    if (draft.photoPath != null && draft.photoPath!.isNotEmpty) {
      media = await _prepareMedia(draft.photoPath!);
    }
    final hash = await _contentHash(
      restaurant: draft.restaurant,
      dishes: draft.dishes,
      verdict: draft.verdict,
      note: draft.note,
      reasons: draft.reasons,
      mediaHash: media?.stored.sha256,
      eatenAt: draft.eatenAt,
    );
    final oldMedia = await (database.select(
      database.mediaAssets,
    )..where((row) => row.recordId.equals(recordId))).get();
    late String actualRestaurantId;
    try {
      await database.transaction(() async {
        final existing =
            await (database.select(database.restaurants)
                  ..where((row) => row.normalizedName.equals(normalizedName)))
                .getSingleOrNull();
        actualRestaurantId = existing?.id ?? restaurantId;
        if (existing == null) {
          await database
              .into(database.restaurants)
              .insert(
                db.RestaurantsCompanion.insert(
                  id: actualRestaurantId,
                  name: draft.restaurant.trim(),
                  normalizedName: normalizedName,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        } else {
          await (database.update(database.restaurants)
                ..where((row) => row.id.equals(existing.id)))
              .write(db.RestaurantsCompanion(updatedAt: Value(now)));
        }
        await (database.update(
          database.mealRecords,
        )..where((row) => row.id.equals(recordId))).write(
          db.MealRecordsCompanion(
            restaurantId: Value(actualRestaurantId),
            verdict: Value(draft.verdict.storageValue),
            note: Value(draft.note.trim()),
            eatenAt: Value(draft.eatenAt.toUtc()),
            updatedAt: Value(now),
            revision: Value(old.revision + 1),
            contentHash: Value(hash),
          ),
        );
        await (database.delete(
          database.mealItems,
        )..where((row) => row.recordId.equals(recordId))).go();
        await (database.delete(
          database.recordTags,
        )..where((row) => row.recordId.equals(recordId))).go();
        await (database.delete(
          database.mediaAssets,
        )..where((row) => row.recordId.equals(recordId))).go();
        await _replaceItems(recordId, draft);
        await _replaceTags(recordId, draft.reasons);
        if (media != null) await _insertMedia(recordId, media.stored, now);
        await _insertRevision(
          recordId: recordId,
          revision: old.revision + 1,
          hash: hash,
          draft: draft,
          mediaHash: media?.stored.sha256,
          changedAt: now,
        );
      });
    } catch (_) {
      if (media != null) await _deleteIfUnreferenced(media.stored);
      rethrow;
    }
    for (final item in oldMedia) {
      await _deleteIfUnreferenced(
        domain.StoredMedia(
          relativePath: item.relativePath,
          thumbnailPath: item.thumbnailPath,
          sha256: item.sha256,
          mimeType: item.mimeType,
          width: item.width,
          height: item.height,
          byteSize: item.byteSize,
        ),
      );
    }
    if (old.restaurantId != null && old.restaurantId != actualRestaurantId) {
      await _deleteRestaurantIfUnreferenced(old.restaurantId!);
    }
    if (draft.photoPath != null && draft.photoPath!.isNotEmpty) {
      await mediaStore.deleteStagedFile(draft.photoPath!);
    }
    return (await _loadRecordById(recordId))!;
  }

  @override
  Future<void> deleteRecord(String recordId) async {
    final old = await (database.select(
      database.mealRecords,
    )..where((row) => row.id.equals(recordId))).getSingleOrNull();
    final media = await (database.select(
      database.mediaAssets,
    )..where((row) => row.recordId.equals(recordId))).get();
    await database.transaction(() async {
      await (database.delete(
        database.mealItems,
      )..where((row) => row.recordId.equals(recordId))).go();
      await (database.delete(
        database.recordTags,
      )..where((row) => row.recordId.equals(recordId))).go();
      await (database.delete(
        database.mediaAssets,
      )..where((row) => row.recordId.equals(recordId))).go();
      await (database.delete(
        database.recordRevisions,
      )..where((row) => row.recordId.equals(recordId))).go();
      await (database.delete(
        database.mealRecords,
      )..where((row) => row.id.equals(recordId))).go();
    });
    for (final item in media) {
      await _deleteIfUnreferenced(
        domain.StoredMedia(
          relativePath: item.relativePath,
          thumbnailPath: item.thumbnailPath,
          sha256: item.sha256,
          mimeType: item.mimeType,
          width: item.width,
          height: item.height,
          byteSize: item.byteSize,
        ),
      );
    }
    if (old != null) await _deleteRestaurantIfUnreferenced(old.restaurantId);
  }

  @override
  Future<void> seedDebugRecords(List<domain.MealRecord> records) async {
    const seededKey = 'debug_demo_records_seeded';
    final seeded = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(seededKey))).getSingleOrNull();
    if (seeded?.value == 'true') return;

    if (await loadDraft() != null) return;

    final existing = await (database.select(database.mealRecords)).get();
    if (existing.isNotEmpty) {
      await _markDebugRecordsSeeded(seededKey);
      return;
    }
    for (final record in records) {
      await publishDraft(
        domain.RecordDraft(
          verdict: record.verdict,
          eatenAt: record.eatenAt,
          restaurant: record.restaurant,
          dishes: record.dishes,
          note: record.note,
          reasons: record.reasons.toSet(),
          photoPath: record.photo,
        ),
      );
    }
    await _markDebugRecordsSeeded(seededKey);
  }

  Future<void> _markDebugRecordsSeeded(String key) async {
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          db.AppSettingsCompanion.insert(
            key: key,
            value: 'true',
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  @override
  Future<BackupSnapshot> createBackupSnapshot() async {
    final restaurants = await database.select(database.restaurants).get();
    final records = await database.select(database.mealRecords).get();
    final items = await database.select(database.mealItems).get();
    final tags = await database.select(database.tags).get();
    final recordTags = await database.select(database.recordTags).get();
    final revisions = await database.select(database.recordRevisions).get();
    final mediaRows = await (database.select(
      database.mediaAssets,
    )..where((row) => row.state.equals('ready'))).get();

    final media = <SnapshotMedia>[];
    for (final row in mediaRows) {
      final bytes = await mediaStore.readRelative(row.relativePath);
      final actualHash = _hex(crypto.sha256.convert(bytes).bytes);
      if (actualHash != row.sha256) {
        throw StateError('媒体文件校验失败：${row.relativePath}');
      }
      media.add(
        SnapshotMedia(
          metadata: {
            'id': row.id,
            'recordId': row.recordId,
            'relativePath': row.relativePath,
            'thumbnailPath': row.thumbnailPath,
            'sha256': row.sha256,
            'mimeType': row.mimeType,
            'width': row.width,
            'height': row.height,
            'byteSize': row.byteSize,
            'state': row.state,
            'createdAt': row.createdAt.toUtc().toIso8601String(),
          },
          bytes: bytes,
        ),
      );
    }

    return BackupSnapshot(
      restaurants: restaurants
          .map(
            (row) => {
              'id': row.id,
              'name': row.name,
              'normalizedName': row.normalizedName,
              'alias': row.alias,
              'locationNote': row.locationNote,
              'isHomeMade': row.isHomeMade,
              'createdAt': row.createdAt.toUtc().toIso8601String(),
              'updatedAt': row.updatedAt.toUtc().toIso8601String(),
            },
          )
          .toList(),
      records: records
          .map(
            (row) => {
              'id': row.id,
              'restaurantId': row.restaurantId,
              'verdict': row.verdict,
              'scene': row.scene,
              'note': row.note,
              'eatenAt': row.eatenAt.toUtc().toIso8601String(),
              'createdAt': row.createdAt.toUtc().toIso8601String(),
              'updatedAt': row.updatedAt.toUtc().toIso8601String(),
              'revision': row.revision,
              'contentHash': row.contentHash,
              'deletedAt': row.deletedAt?.toUtc().toIso8601String(),
            },
          )
          .toList(),
      items: items
          .map(
            (row) => {
              'id': row.id,
              'recordId': row.recordId,
              'name': row.name,
              'verdict': row.verdict,
              'intensity': row.intensity,
              'reason': row.reason,
            },
          )
          .toList(),
      tags: tags
          .map(
            (row) => {
              'id': row.id,
              'name': row.name,
              'normalizedName': row.normalizedName,
              'category': row.category,
              'isSystem': row.isSystem,
            },
          )
          .toList(),
      recordTags: recordTags
          .map((row) => {'recordId': row.recordId, 'tagId': row.tagId})
          .toList(),
      revisions: revisions
          .map(
            (row) => {
              'id': row.id,
              'recordId': row.recordId,
              'revision': row.revision,
              'contentHash': row.contentHash,
              'snapshotJson': row.snapshotJson,
              'changedAt': row.changedAt.toUtc().toIso8601String(),
            },
          )
          .toList(),
      media: media,
    );
  }

  @override
  Future<BackupInspection> inspectBackupSnapshot({
    required String backupId,
    required BackupSnapshot snapshot,
    String? stagingPath,
  }) async {
    final imported = await (database.select(
      database.importHistory,
    )..where((row) => row.backupId.equals(backupId))).getSingleOrNull();
    if (imported != null) {
      return BackupInspection(
        backupId: backupId,
        snapshot: snapshot,
        stagingPath: stagingPath,
        alreadyImported: true,
        counts: domain.ImportCounts(existing: snapshot.records.length),
        conflicts: const [],
      );
    }

    final localRecords = await loadRecords(
      query: const domain.RecordQuery(includeDeleted: true),
    );
    final localById = {for (final record in localRecords) record.id: record};
    var added = 0;
    var existing = 0;
    var updated = 0;
    var skipped = 0;
    var deleted = 0;
    final conflicts = <ConflictItem>[];

    for (final raw in snapshot.records) {
      final id = _stringValue(raw, 'id');
      final remote = _recordFromSnapshot(raw, snapshot);
      final local = localById[id];
      if (local == null) {
        added++;
        continue;
      }
      final classification = _classifyImport(local: local, remote: remote);
      switch (classification) {
        case _ImportAction.same:
          existing++;
        case _ImportAction.update:
          if (remote.isDeleted) {
            deleted++;
          } else {
            updated++;
          }
        case _ImportAction.keepLocal:
          skipped++;
        case _ImportAction.conflict:
          conflicts.add(
            ConflictItem(recordId: id, local: local, remote: remote),
          );
        case _ImportAction.add:
        case _ImportAction.duplicate:
          added++;
      }
    }
    return BackupInspection(
      backupId: backupId,
      snapshot: snapshot,
      stagingPath: stagingPath,
      counts: domain.ImportCounts(
        added: added,
        existing: existing,
        updated: updated,
        skipped: skipped,
        deleted: deleted,
        conflicts: conflicts.length,
      ),
      conflicts: conflicts,
    );
  }

  @override
  Future<ImportResult> commitImport(ImportPlan plan) async {
    final inspection = plan.inspection;
    if (inspection.alreadyImported) {
      return ImportResult(counts: inspection.counts, alreadyImported: true);
    }
    if (!plan.isReady) {
      throw StateError('仍有导入冲突未处理');
    }

    final localRecords = await loadRecords(
      query: const domain.RecordQuery(includeDeleted: true),
    );
    final localById = {for (final record in localRecords) record.id: record};
    final actions = <_ImportRecordAction>[];
    for (final raw in inspection.snapshot.records) {
      final remote = _recordFromSnapshot(raw, inspection.snapshot);
      final local = localById[remote.id];
      var action = _classifyImport(local: local, remote: remote);
      var targetId = remote.id;
      if (action == _ImportAction.conflict) {
        final resolution = plan.resolutions[remote.id];
        if (resolution == ConflictResolution.keepLocal) {
          action = _ImportAction.keepLocal;
        } else if (resolution == ConflictResolution.useBackup) {
          action = _ImportAction.update;
        } else if (resolution == ConflictResolution.duplicate) {
          action = _ImportAction.duplicate;
          targetId = _uuid.v4();
        }
      }
      actions.add(
        _ImportRecordAction(
          sourceId: remote.id,
          targetId: targetId,
          action: action,
          remote: remote,
        ),
      );
    }

    final changedActions = actions
        .where(
          (item) =>
              item.action == _ImportAction.add ||
              item.action == _ImportAction.update ||
              item.action == _ImportAction.duplicate,
        )
        .toList();
    final touchedIds = changedActions.map((item) => item.targetId).toSet();
    final previous = await _captureRollback(
      changedActions.map((item) => item.targetId).toSet(),
    );
    final jobId = _uuid.v4();
    final rollback = <String, dynamic>{
      'touchedRecordIds': touchedIds.toList(),
      'previous': previous,
      'mediaPaths': <String>[],
      'resultDigest': _digestForImport(inspection.backupId),
      'counts': _countsToJson(inspection.counts),
    };
    final stagingPath = inspection.stagingPath ?? '';
    await database
        .into(database.importJobs)
        .insert(
          db.ImportJobsCompanion.insert(
            id: jobId,
            backupId: inspection.backupId,
            state: 'staging',
            stagingPath: stagingPath,
            rollbackPath: Value(jsonEncode(rollback)),
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );

    final storedMedia = <_ImportedMedia>[];
    try {
      for (final action in changedActions) {
        final sourceMedia = inspection.snapshot.media.where(
          (media) =>
              _stringValue(media.metadata, 'recordId') == action.sourceId,
        );
        for (final media in sourceMedia) {
          final stored = await mediaStore.importBytes(
            media.bytes,
            sourceName: _stringValue(
              media.metadata,
              'relativePath',
              fallback: 'image.jpg',
            ),
          );
          storedMedia.add(
            _ImportedMedia(targetRecordId: action.targetId, stored: stored),
          );
        }
      }
      rollback['mediaPaths'] = storedMedia
          .expand(
            (item) => [item.stored.relativePath, item.stored.thumbnailPath],
          )
          .toSet()
          .toList();
      rollback['mediaChecksums'] = {
        for (final item in storedMedia)
          item.stored.relativePath: item.stored.sha256,
      };
      await _updateImportJob(jobId, state: 'staging', rollback: rollback);

      final now = DateTime.now().toUtc();
      await database.transaction(() async {
        for (final action in changedActions) {
          final rawRecord = inspection.snapshot.records.firstWhere(
            (row) => _stringValue(row, 'id') == action.sourceId,
          );
          await _ensureRestaurant(rawRecord, inspection.snapshot, now);
          await _replaceImportedRecord(
            action: action,
            rawRecord: rawRecord,
            snapshot: inspection.snapshot,
            storedMedia: storedMedia
                .where((item) => item.targetRecordId == action.targetId)
                .toList(),
            now: now,
          );
        }
        await _updateImportJob(jobId, state: 'dbCommitted', rollback: rollback);
      });

      await _updateImportJob(
        jobId,
        state: 'mediaFinalizing',
        rollback: rollback,
      );
      await _verifyImportedMedia(storedMedia);
      await database
          .into(database.importHistory)
          .insertOnConflictUpdate(
            db.ImportHistoryCompanion.insert(
              backupId: inspection.backupId,
              importedAt: DateTime.now().toUtc(),
              resultDigest: rollback['resultDigest'] as String,
            ),
          );
      await _updateImportJob(jobId, state: 'complete', rollback: rollback);
      return ImportResult(counts: inspection.counts);
    } on Object {
      await _rollbackJob(jobId, rollback);
      await _cleanupUnreferencedMedia(storedMedia);
      rethrow;
    }
  }

  @override
  Future<void> recoverImportJobs() async {
    final jobs = await database.select(database.importJobs).get();
    for (final job in jobs) {
      if (job.state == 'complete') continue;
      Map<String, dynamic> rollback;
      try {
        rollback = jsonDecode(job.rollbackPath ?? '{}') as Map<String, dynamic>;
      } on Object {
        await (database.delete(
          database.importJobs,
        )..where((row) => row.id.equals(job.id))).go();
        continue;
      }
      final paths = (rollback['mediaPaths'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList();
      final checksums = <String, String>{
        for (final entry
            in (rollback['mediaChecksums'] as Map<dynamic, dynamic>? ??
                    const {})
                .entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
      if (job.state == 'dbCommitted' || job.state == 'mediaFinalizing') {
        final valid = await _pathsAreValid(paths, checksums: checksums);
        if (valid) {
          await database
              .into(database.importHistory)
              .insertOnConflictUpdate(
                db.ImportHistoryCompanion.insert(
                  backupId: job.backupId,
                  importedAt: DateTime.now().toUtc(),
                  resultDigest: _stringValue(
                    rollback,
                    'resultDigest',
                    fallback: _digestForImport(job.backupId),
                  ),
                ),
              );
          await _updateImportJob(job.id, state: 'complete', rollback: rollback);
        } else {
          await _rollbackJob(job.id, rollback);
          await _cleanupPaths(paths);
        }
      } else {
        await _cleanupPaths(paths);
        await (database.delete(
          database.importJobs,
        )..where((row) => row.id.equals(job.id))).go();
      }
    }
  }

  _ImportAction _classifyImport({
    required domain.MealRecord? local,
    required domain.MealRecord remote,
  }) {
    if (local == null) return _ImportAction.add;
    final sameDeletion = local.deletedAt?.toUtc() == remote.deletedAt?.toUtc();
    if (local.contentHash == remote.contentHash && sameDeletion) {
      return _ImportAction.same;
    }
    final localTime = _recordChangedAt(local);
    final remoteTime = _recordChangedAt(remote);
    if (remoteTime.isAfter(localTime)) return _ImportAction.update;
    if (localTime.isAfter(remoteTime)) return _ImportAction.keepLocal;
    return _ImportAction.conflict;
  }

  DateTime _recordChangedAt(domain.MealRecord record) {
    return (record.updatedAt ?? record.createdAt ?? record.eatenAt).toUtc();
  }

  domain.MealRecord _recordFromSnapshot(
    Map<String, dynamic> raw,
    BackupSnapshot snapshot,
  ) {
    final restaurantId = _stringValue(raw, 'restaurantId');
    final restaurant = snapshot.restaurants
        .cast<Map<String, dynamic>?>()
        .firstWhere((row) => row?['id'] == restaurantId, orElse: () => null);
    final sourceId = _stringValue(raw, 'id');
    final items = snapshot.items
        .where((row) => row['recordId'] == sourceId)
        .toList();
    final tagIds = snapshot.recordTags
        .where((row) => row['recordId'] == sourceId)
        .map((row) => row['tagId'])
        .toSet();
    final reasons = snapshot.tags
        .where((row) => tagIds.contains(row['id']))
        .map((row) => _stringValue(row, 'name'))
        .where((name) => name.isNotEmpty)
        .toList();
    final media = snapshot.media.cast<SnapshotMedia?>().firstWhere(
      (row) => row?.metadata['recordId'] == sourceId,
      orElse: () => null,
    );
    final eatenAt = _dateValue(raw, 'eatenAt');
    return domain.MealRecord(
      id: sourceId,
      restaurantId: restaurantId,
      restaurant: _stringValue(
        restaurant ?? const {},
        'name',
        fallback: '未命名店铺',
      ),
      dishes: items
          .map((item) => _stringValue(item, 'name'))
          .where((name) => name.isNotEmpty)
          .toList(),
      verdict: domain.VerdictDetails.fromStorage(
        _stringValue(raw, 'verdict', fallback: 'neutral'),
      ),
      reasons: reasons,
      photo: media == null
          ? ''
          : mediaStore.absolutePath(
              _stringValue(media.metadata, 'relativePath'),
            ),
      time: _formatTime(
        eatenAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
      note: _stringValue(raw, 'note'),
      eatenAt: eatenAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      createdAt: _dateValue(raw, 'createdAt'),
      updatedAt: _dateValue(raw, 'updatedAt'),
      revision: _intValue(raw, 'revision', fallback: 1),
      deletedAt: _dateValue(raw, 'deletedAt', nullable: true),
      contentHash: _stringValue(raw, 'contentHash'),
      mediaHash: media == null ? null : _stringValue(media.metadata, 'sha256'),
    );
  }

  Future<Map<String, dynamic>> _captureRollback(Set<String> ids) async {
    if (ids.isEmpty) {
      return {
        'records': <Map<String, dynamic>>[],
        'items': <Map<String, dynamic>>[],
        'recordTags': <Map<String, dynamic>>[],
        'media': <Map<String, dynamic>>[],
        'revisions': <Map<String, dynamic>>[],
      };
    }
    final records = await (database.select(
      database.mealRecords,
    )..where((row) => row.id.isIn(ids))).get();
    final items = await (database.select(
      database.mealItems,
    )..where((row) => row.recordId.isIn(ids))).get();
    final recordTags = await (database.select(
      database.recordTags,
    )..where((row) => row.recordId.isIn(ids))).get();
    final media = await (database.select(
      database.mediaAssets,
    )..where((row) => row.recordId.isIn(ids))).get();
    final revisions = await (database.select(
      database.recordRevisions,
    )..where((row) => row.recordId.isIn(ids))).get();
    return {
      'records': records.map(_recordRowToJson).toList(),
      'items': items.map(_itemRowToJson).toList(),
      'recordTags': recordTags.map(_recordTagRowToJson).toList(),
      'media': media.map(_mediaRowToJson).toList(),
      'revisions': revisions.map(_revisionRowToJson).toList(),
    };
  }

  Future<void> _ensureRestaurant(
    Map<String, dynamic> rawRecord,
    BackupSnapshot snapshot,
    DateTime now,
  ) async {
    final id = _stringValue(rawRecord, 'restaurantId');
    if (id.isEmpty) return;
    final raw = snapshot.restaurants.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row?['id'] == id,
      orElse: () => null,
    );
    final name = _stringValue(raw ?? const {}, 'name', fallback: '未命名店铺');
    final normalized = _stringValue(
      raw ?? const {},
      'normalizedName',
      fallback: _normalize(name),
    );
    final existing = await (database.select(
      database.restaurants,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final companion = db.RestaurantsCompanion(
      id: Value(id),
      name: Value(name),
      normalizedName: Value(normalized),
      alias: Value(_nullableString(raw, 'alias')),
      locationNote: Value(_nullableString(raw, 'locationNote')),
      isHomeMade: Value(_boolValue(raw, 'isHomeMade')),
      createdAt: Value(_dateValue(raw ?? const {}, 'createdAt') ?? now),
      updatedAt: Value(now),
    );
    if (existing == null) {
      await database.into(database.restaurants).insert(companion);
    } else {
      await (database.update(database.restaurants)
            ..where((row) => row.id.equals(id)))
          .write(companion.copyWith(createdAt: Value(existing.createdAt)));
    }
  }

  Future<void> _replaceImportedRecord({
    required _ImportRecordAction action,
    required Map<String, dynamic> rawRecord,
    required BackupSnapshot snapshot,
    required List<_ImportedMedia> storedMedia,
    required DateTime now,
  }) async {
    final targetId = action.targetId;
    await (database.delete(
      database.mealItems,
    )..where((row) => row.recordId.equals(targetId))).go();
    await (database.delete(
      database.recordTags,
    )..where((row) => row.recordId.equals(targetId))).go();
    await (database.delete(
      database.mediaAssets,
    )..where((row) => row.recordId.equals(targetId))).go();
    await (database.delete(
      database.recordRevisions,
    )..where((row) => row.recordId.equals(targetId))).go();
    await (database.delete(
      database.mealRecords,
    )..where((row) => row.id.equals(targetId))).go();

    await database
        .into(database.mealRecords)
        .insert(
          db.MealRecordsCompanion.insert(
            id: targetId,
            restaurantId: _stringValue(rawRecord, 'restaurantId'),
            verdict: _stringValue(rawRecord, 'verdict', fallback: 'neutral'),
            scene: Value(_stringValue(rawRecord, 'scene')),
            note: Value(_stringValue(rawRecord, 'note')),
            eatenAt: _dateValue(rawRecord, 'eatenAt') ?? now,
            createdAt: _dateValue(rawRecord, 'createdAt') ?? now,
            updatedAt: _dateValue(rawRecord, 'updatedAt') ?? now,
            revision: Value(_intValue(rawRecord, 'revision', fallback: 1)),
            contentHash: _stringValue(rawRecord, 'contentHash'),
            deletedAt: Value(
              _dateValue(rawRecord, 'deletedAt', nullable: true),
            ),
          ),
        );

    final sourceId = action.sourceId;
    for (final rawItem in snapshot.items.where(
      (row) => _stringValue(row, 'recordId') == sourceId,
    )) {
      await database
          .into(database.mealItems)
          .insert(
            db.MealItemsCompanion.insert(
              id: _uuid.v4(),
              recordId: targetId,
              name: _stringValue(rawItem, 'name', fallback: '未命名菜品'),
              verdict: _stringValue(
                rawItem,
                'verdict',
                fallback: _stringValue(
                  rawRecord,
                  'verdict',
                  fallback: 'neutral',
                ),
              ),
              intensity: Value(_nullableInt(rawItem, 'intensity')),
              reason: Value(_nullableString(rawItem, 'reason')),
            ),
          );
    }

    for (final relation in snapshot.recordTags.where(
      (row) => _stringValue(row, 'recordId') == sourceId,
    )) {
      final tagRaw = snapshot.tags.cast<Map<String, dynamic>?>().firstWhere(
        (row) => row?['id'] == relation['tagId'],
        orElse: () => null,
      );
      if (tagRaw == null) continue;
      final tagId = await _ensureTag(tagRaw);
      await database
          .into(database.recordTags)
          .insertOnConflictUpdate(
            db.RecordTagsCompanion.insert(recordId: targetId, tagId: tagId),
          );
    }

    for (final item in storedMedia) {
      await database
          .into(database.mediaAssets)
          .insert(
            db.MediaAssetsCompanion.insert(
              id: _uuid.v4(),
              recordId: targetId,
              relativePath: item.stored.relativePath,
              thumbnailPath: item.stored.thumbnailPath,
              sha256: item.stored.sha256,
              mimeType: item.stored.mimeType,
              width: Value(item.stored.width),
              height: Value(item.stored.height),
              byteSize: item.stored.byteSize,
              state: const Value('ready'),
              createdAt: now,
            ),
          );
    }

    for (final rawRevision in snapshot.revisions.where(
      (row) => _stringValue(row, 'recordId') == sourceId,
    )) {
      await database
          .into(database.recordRevisions)
          .insertOnConflictUpdate(
            db.RecordRevisionsCompanion.insert(
              id: _uuid.v4(),
              recordId: targetId,
              revision: _intValue(rawRevision, 'revision', fallback: 1),
              contentHash: _stringValue(rawRevision, 'contentHash'),
              snapshotJson: _stringValue(rawRevision, 'snapshotJson'),
              changedAt: _dateValue(rawRevision, 'changedAt') ?? now,
            ),
          );
    }
  }

  Future<String> _ensureTag(Map<String, dynamic> raw) async {
    final normalized = _stringValue(raw, 'normalizedName');
    final sameName = await (database.select(
      database.tags,
    )..where((row) => row.normalizedName.equals(normalized))).getSingleOrNull();
    if (sameName != null) return sameName.id;
    final id = _stringValue(raw, 'id', fallback: _uuid.v4());
    final sameId = await (database.select(
      database.tags,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (sameId != null) return sameId.id;
    await database
        .into(database.tags)
        .insert(
          db.TagsCompanion.insert(
            id: id,
            name: _stringValue(raw, 'name', fallback: normalized),
            normalizedName: normalized,
            category: Value(_stringValue(raw, 'category', fallback: 'reason')),
            isSystem: Value(_boolValue(raw, 'isSystem')),
          ),
        );
    return id;
  }

  Future<void> _verifyImportedMedia(List<_ImportedMedia> media) async {
    for (final item in media) {
      final bytes = await mediaStore.readRelative(item.stored.relativePath);
      final digest = _hex(crypto.sha256.convert(bytes).bytes);
      if (digest != item.stored.sha256) {
        throw StateError('导入媒体校验失败：${item.stored.relativePath}');
      }
      if (!await mediaStore.existsRelative(item.stored.thumbnailPath)) {
        throw StateError('导入缩略图缺失：${item.stored.thumbnailPath}');
      }
    }
  }

  Future<bool> _pathsAreValid(
    List<String> paths, {
    Map<String, String> checksums = const {},
  }) async {
    for (final path in paths) {
      if (!await mediaStore.existsRelative(path)) return false;
      final expected = checksums[path];
      if (expected != null) {
        final bytes = await mediaStore.readRelative(path);
        if (_hex(crypto.sha256.convert(bytes).bytes) != expected) return false;
      }
    }
    return true;
  }

  Future<void> _cleanupUnreferencedMedia(List<_ImportedMedia> media) async {
    await _cleanupPaths(
      media
          .expand(
            (item) => [item.stored.relativePath, item.stored.thumbnailPath],
          )
          .toSet()
          .toList(),
    );
  }

  Future<void> _cleanupPaths(List<String> paths) async {
    for (final path in paths.toSet()) {
      final references =
          await (database.select(database.mediaAssets)..where(
                (row) =>
                    row.relativePath.equals(path) |
                    row.thumbnailPath.equals(path),
              ))
              .get();
      if (references.isEmpty) {
        await mediaStore.deleteRelative(path);
      }
    }
  }

  Future<void> _updateImportJob(
    String jobId, {
    required String state,
    required Map<String, dynamic> rollback,
  }) async {
    await (database.update(
      database.importJobs,
    )..where((row) => row.id.equals(jobId))).write(
      db.ImportJobsCompanion(
        state: Value(state),
        rollbackPath: Value(jsonEncode(rollback)),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> _rollbackJob(String jobId, Map<String, dynamic> rollback) async {
    final previous = rollback['previous'] as Map<String, dynamic>? ?? const {};
    final touched = (rollback['touchedRecordIds'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toSet();
    await database.transaction(() async {
      for (final id in touched) {
        await (database.delete(
          database.mealItems,
        )..where((row) => row.recordId.equals(id))).go();
        await (database.delete(
          database.recordTags,
        )..where((row) => row.recordId.equals(id))).go();
        await (database.delete(
          database.mediaAssets,
        )..where((row) => row.recordId.equals(id))).go();
        await (database.delete(
          database.recordRevisions,
        )..where((row) => row.recordId.equals(id))).go();
        await (database.delete(
          database.mealRecords,
        )..where((row) => row.id.equals(id))).go();
      }
      for (final row
          in (previous['records'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()) {
        await database.into(database.mealRecords).insert(_recordCompanion(row));
      }
      for (final row
          in (previous['items'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()) {
        await database.into(database.mealItems).insert(_itemCompanion(row));
      }
      for (final row
          in (previous['recordTags'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()) {
        await database
            .into(database.recordTags)
            .insert(_recordTagCompanion(row));
      }
      for (final row
          in (previous['media'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()) {
        await database.into(database.mediaAssets).insert(_mediaCompanion(row));
      }
      for (final row
          in (previous['revisions'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()) {
        await database
            .into(database.recordRevisions)
            .insert(_revisionCompanion(row));
      }
      await (database.delete(
        database.importJobs,
      )..where((row) => row.id.equals(jobId))).go();
    });
  }

  Map<String, dynamic> _recordRowToJson(db.MealRecord row) => {
    'id': row.id,
    'restaurantId': row.restaurantId,
    'verdict': row.verdict,
    'scene': row.scene,
    'note': row.note,
    'eatenAt': row.eatenAt.toUtc().toIso8601String(),
    'createdAt': row.createdAt.toUtc().toIso8601String(),
    'updatedAt': row.updatedAt.toUtc().toIso8601String(),
    'revision': row.revision,
    'contentHash': row.contentHash,
    'deletedAt': row.deletedAt?.toUtc().toIso8601String(),
  };

  Map<String, dynamic> _itemRowToJson(db.MealItem row) => {
    'id': row.id,
    'recordId': row.recordId,
    'name': row.name,
    'verdict': row.verdict,
    'intensity': row.intensity,
    'reason': row.reason,
  };

  Map<String, dynamic> _recordTagRowToJson(db.RecordTag row) => {
    'recordId': row.recordId,
    'tagId': row.tagId,
  };

  Map<String, dynamic> _mediaRowToJson(db.MediaAsset row) => {
    'id': row.id,
    'recordId': row.recordId,
    'relativePath': row.relativePath,
    'thumbnailPath': row.thumbnailPath,
    'sha256': row.sha256,
    'mimeType': row.mimeType,
    'width': row.width,
    'height': row.height,
    'byteSize': row.byteSize,
    'state': row.state,
    'createdAt': row.createdAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> _revisionRowToJson(db.RecordRevision row) => {
    'id': row.id,
    'recordId': row.recordId,
    'revision': row.revision,
    'contentHash': row.contentHash,
    'snapshotJson': row.snapshotJson,
    'changedAt': row.changedAt.toUtc().toIso8601String(),
  };

  db.MealRecordsCompanion _recordCompanion(Map<String, dynamic> raw) {
    final now = DateTime.now().toUtc();
    return db.MealRecordsCompanion.insert(
      id: _stringValue(raw, 'id'),
      restaurantId: _stringValue(raw, 'restaurantId'),
      verdict: _stringValue(raw, 'verdict', fallback: 'neutral'),
      scene: Value(_stringValue(raw, 'scene')),
      note: Value(_stringValue(raw, 'note')),
      eatenAt: _dateValue(raw, 'eatenAt') ?? now,
      createdAt: _dateValue(raw, 'createdAt') ?? now,
      updatedAt: _dateValue(raw, 'updatedAt') ?? now,
      revision: Value(_intValue(raw, 'revision', fallback: 1)),
      contentHash: _stringValue(raw, 'contentHash'),
      deletedAt: Value(_dateValue(raw, 'deletedAt', nullable: true)),
    );
  }

  db.MealItemsCompanion _itemCompanion(Map<String, dynamic> raw) {
    return db.MealItemsCompanion.insert(
      id: _stringValue(raw, 'id', fallback: _uuid.v4()),
      recordId: _stringValue(raw, 'recordId'),
      name: _stringValue(raw, 'name', fallback: '未命名菜品'),
      verdict: _stringValue(raw, 'verdict', fallback: 'neutral'),
      intensity: Value(_nullableInt(raw, 'intensity')),
      reason: Value(_nullableString(raw, 'reason')),
    );
  }

  db.RecordTagsCompanion _recordTagCompanion(Map<String, dynamic> raw) {
    return db.RecordTagsCompanion.insert(
      recordId: _stringValue(raw, 'recordId'),
      tagId: _stringValue(raw, 'tagId'),
    );
  }

  db.MediaAssetsCompanion _mediaCompanion(Map<String, dynamic> raw) {
    final now = DateTime.now().toUtc();
    return db.MediaAssetsCompanion.insert(
      id: _stringValue(raw, 'id', fallback: _uuid.v4()),
      recordId: _stringValue(raw, 'recordId'),
      relativePath: _stringValue(raw, 'relativePath'),
      thumbnailPath: _stringValue(raw, 'thumbnailPath'),
      sha256: _stringValue(raw, 'sha256'),
      mimeType: _stringValue(raw, 'mimeType', fallback: 'image/jpeg'),
      width: Value(_nullableInt(raw, 'width')),
      height: Value(_nullableInt(raw, 'height')),
      byteSize: _intValue(raw, 'byteSize'),
      state: Value(_stringValue(raw, 'state', fallback: 'ready')),
      createdAt: _dateValue(raw, 'createdAt') ?? now,
    );
  }

  db.RecordRevisionsCompanion _revisionCompanion(Map<String, dynamic> raw) {
    final now = DateTime.now().toUtc();
    return db.RecordRevisionsCompanion.insert(
      id: _stringValue(raw, 'id', fallback: _uuid.v4()),
      recordId: _stringValue(raw, 'recordId'),
      revision: _intValue(raw, 'revision', fallback: 1),
      contentHash: _stringValue(raw, 'contentHash'),
      snapshotJson: _stringValue(raw, 'snapshotJson'),
      changedAt: _dateValue(raw, 'changedAt') ?? now,
    );
  }

  Map<String, dynamic> _countsToJson(domain.ImportCounts counts) => {
    'added': counts.added,
    'existing': counts.existing,
    'updated': counts.updated,
    'skipped': counts.skipped,
    'deleted': counts.deleted,
    'conflicts': counts.conflicts,
  };

  String _digestForImport(String backupId) => 'haochibu-import:$backupId';

  String _stringValue(
    Map<String, dynamic> map,
    String key, {
    String fallback = '',
  }) {
    final value = map[key];
    return value is String ? value : fallback;
  }

  String? _nullableString(Map<String, dynamic>? map, String key) {
    final value = map?[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  DateTime? _dateValue(
    Map<String, dynamic> map,
    String key, {
    bool nullable = false,
  }) {
    final value = map[key];
    if (value == null && nullable) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }

  int _intValue(Map<String, dynamic> map, String key, {int fallback = 0}) {
    final value = map[key];
    return value is int ? value : fallback;
  }

  int? _nullableInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    return value is int ? value : null;
  }

  bool _boolValue(Map<String, dynamic>? map, String key) {
    final value = map?[key];
    return value is bool && value;
  }

  Future<domain.MealRecord?> _loadRecordById(
    String recordId, {
    bool includeDeleted = false,
  }) async {
    final records = await loadRecords(
      query: domain.RecordQuery(includeDeleted: includeDeleted, limit: 10000),
    );
    for (final record in records) {
      if (record.id == recordId) return record;
    }
    return null;
  }

  void _validateDraft(domain.RecordDraft draft) {
    if (draft.restaurant.trim().isEmpty) {
      throw ArgumentError('店名不能为空');
    }
    if (draft.eatenAt.isAfter(DateTime.now())) {
      throw ArgumentError('用餐时间不能晚于现在');
    }
  }

  Future<void> _replaceItems(String recordId, domain.RecordDraft draft) async {
    for (final dish
        in draft.dishes
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)) {
      await database
          .into(database.mealItems)
          .insert(
            db.MealItemsCompanion.insert(
              id: _uuid.v4(),
              recordId: recordId,
              name: dish,
              verdict: draft.verdict.storageValue,
              reason: Value(
                draft.note.trim().isEmpty ? null : draft.note.trim(),
              ),
            ),
          );
    }
  }

  Future<void> _replaceTags(String recordId, Iterable<String> reasons) async {
    for (final reason
        in reasons
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)) {
      final normalized = _normalize(reason);
      var tag =
          await (database.select(database.tags)
                ..where((row) => row.normalizedName.equals(normalized)))
              .getSingleOrNull();
      if (tag == null) {
        await database
            .into(database.tags)
            .insert(
              db.TagsCompanion.insert(
                id: _uuid.v4(),
                name: reason,
                normalizedName: normalized,
              ),
            );
        tag = await (database.select(
          database.tags,
        )..where((row) => row.normalizedName.equals(normalized))).getSingle();
      }
      await database
          .into(database.recordTags)
          .insertOnConflictUpdate(
            db.RecordTagsCompanion.insert(recordId: recordId, tagId: tag.id),
          );
    }
  }

  Future<void> _insertMedia(
    String recordId,
    domain.StoredMedia media,
    DateTime createdAt,
  ) async {
    await database
        .into(database.mediaAssets)
        .insert(
          db.MediaAssetsCompanion.insert(
            id: _uuid.v4(),
            recordId: recordId,
            relativePath: media.relativePath,
            thumbnailPath: media.thumbnailPath,
            sha256: media.sha256,
            mimeType: media.mimeType,
            width: Value(media.width),
            height: Value(media.height),
            byteSize: media.byteSize,
            createdAt: createdAt,
          ),
        );
  }

  Future<void> _insertRevision({
    required String recordId,
    required int revision,
    required String hash,
    required domain.RecordDraft draft,
    required String? mediaHash,
    required DateTime changedAt,
  }) async {
    await database
        .into(database.recordRevisions)
        .insert(
          db.RecordRevisionsCompanion.insert(
            id: _uuid.v4(),
            recordId: recordId,
            revision: revision,
            contentHash: hash,
            snapshotJson: jsonEncode({
              'restaurant': draft.restaurant.trim(),
              'dishes': draft.dishes
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList(),
              'verdict': draft.verdict.storageValue,
              'note': draft.note.trim(),
              'reasons': draft.reasons.toList()..sort(),
              'eatenAt': draft.eatenAt.toUtc().toIso8601String(),
              'mediaHash': mediaHash,
            }),
            changedAt: changedAt,
          ),
        );
  }

  Future<void> _deleteIfUnreferenced(domain.StoredMedia media) async {
    final references =
        await (database.select(database.mediaAssets)..where(
              (row) =>
                  row.relativePath.equals(media.relativePath) |
                  row.thumbnailPath.equals(media.thumbnailPath),
            ))
            .get();
    if (references.isEmpty) {
      await mediaStore.deleteRelative(media.relativePath);
      await mediaStore.deleteRelative(media.thumbnailPath);
    }
  }

  Future<void> _deleteRestaurantIfUnreferenced(String restaurantId) async {
    final references = await (database.select(
      database.mealRecords,
    )..where((row) => row.restaurantId.equals(restaurantId))).get();
    if (references.isNotEmpty) return;
    await (database.delete(
      database.restaurants,
    )..where((row) => row.id.equals(restaurantId))).go();
  }

  Future<StoredMediaForRecord> _prepareMedia(String path) async {
    final stored = path.startsWith('assets/')
        ? await mediaStore.importAsset(path)
        : await mediaStore.importFile(path);
    return StoredMediaForRecord(stored);
  }

  Future<String> _contentHash({
    required String restaurant,
    required List<String> dishes,
    required domain.Verdict verdict,
    required String note,
    required Set<String> reasons,
    required String? mediaHash,
    required DateTime eatenAt,
  }) async {
    final payload = <String, dynamic>{
      'restaurant': restaurant.trim(),
      'dishes': dishes
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      'verdict': verdict.storageValue,
      'note': note.trim(),
      'reasons': reasons.toList()..sort(),
      'eatenAt': eatenAt.toUtc().toIso8601String(),
      'mediaHash': mediaHash,
    };
    return _hex(crypto.sha256.convert(utf8.encode(jsonEncode(payload))).bytes);
  }

  String _normalize(String value) => value.trim().toLowerCase();

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '今天 $hour:$minute';
    }
    if (local.year == now.year) {
      return '${local.month}月${local.day}日 $hour:$minute';
    }
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')} $hour:$minute';
  }

  String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

enum _ImportAction { add, same, update, keepLocal, conflict, duplicate }

class _ImportRecordAction {
  const _ImportRecordAction({
    required this.sourceId,
    required this.targetId,
    required this.action,
    required this.remote,
  });

  final String sourceId;
  final String targetId;
  final _ImportAction action;
  final domain.MealRecord remote;
}

class _ImportedMedia {
  const _ImportedMedia({required this.targetRecordId, required this.stored});

  final String targetRecordId;
  final domain.StoredMedia stored;
}

class StoredMediaForRecord {
  const StoredMediaForRecord(this.stored);

  final domain.StoredMedia stored;
}
