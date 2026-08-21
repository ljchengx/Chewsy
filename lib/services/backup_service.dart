import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../data/repositories/record_repository.dart';
import '../domain/backup_models.dart';
import '../domain/models.dart';
import 'media_store.dart';

typedef BackupProgressCallback = void Function(BackupProgress progress);

abstract class BackupService {
  Future<BackupArtifact> create(
    BackupRequest request,
    BackupProgressCallback onProgress,
  );

  Future<BackupInspection> inspect(
    ImportRequest request,
    BackupProgressCallback onProgress,
  );

  Future<ImportResult> commit(
    ImportPlan plan,
    BackupProgressCallback onProgress,
  );

  Future<void> deleteArtifact(BackupArtifact artifact);
}

class LocalBackupService implements BackupService {
  LocalBackupService({required this.repository, required this.mediaStore});

  static const int schemaVersion = 1;
  static const int maxBackupBytes = 1024 * 1024 * 1024;
  static const int maxPayloadBytes = 4 * 1024 * 1024 * 1024;
  static const int maxMediaBytes = 30 * 1024 * 1024;
  static const int maxEntries = 60000;
  static const int maxCompressionRatio = 20;

  final DriftRecordRepository repository;
  final MediaStore mediaStore;
  final Uuid _uuid = const Uuid();

  @override
  Future<BackupArtifact> create(
    BackupRequest request,
    BackupProgressCallback onProgress,
  ) async {
    onProgress(const BackupProgress(stage: '整理记录', fraction: 0.04));
    final snapshot = await repository.createBackupSnapshot();
    final backupId = _uuid.v4();
    final createdAt = DateTime.now().toUtc();

    onProgress(const BackupProgress(stage: '打包图片', fraction: 0.22));
    final payload = await _buildPayload(
      backupId: backupId,
      createdAt: createdAt,
      snapshot: snapshot,
    );
    if (payload.length > maxBackupBytes) {
      throw StateError('备份文件超过 1 GiB 限制');
    }

    onProgress(const BackupProgress(stage: '计算校验', fraction: 0.42));
    onProgress(const BackupProgress(stage: '准备分享', fraction: 0.82));

    final timestamp = _fileTimestamp(createdAt);
    final tempDirectory = Directory(p.join(mediaStore.root.path, 'tmp'));
    await tempDirectory.create(recursive: true);
    final file = File(
      p.join(tempDirectory.path, 'haochibu-backup-$timestamp.haochibu'),
    );
    await file.writeAsBytes(payload, flush: true);
    onProgress(const BackupProgress(stage: '等待保存', fraction: 0.94));
    return BackupArtifact(
      filePath: file.path,
      backupId: backupId,
      byteSize: payload.length,
    );
  }

  @override
  Future<BackupInspection> inspect(
    ImportRequest request,
    BackupProgressCallback onProgress,
  ) async {
    final file = File(request.filePath);
    if (!await file.exists()) throw const FormatException('备份文件不存在');
    final length = await file.length();
    if (length <= 0 || length > maxBackupBytes) {
      throw const FormatException('备份文件大小不受支持');
    }

    String? stagingPath;
    try {
      onProgress(const BackupProgress(stage: '检查文件', fraction: 0.08));
      final payload = await file.readAsBytes();
      if (payload.length > maxBackupBytes) {
        throw const FormatException('备份文件超过 1 GiB 限制');
      }
      onProgress(const BackupProgress(stage: '读取内容', fraction: 0.24));
      final backupId = _readPayloadBackupId(payload);

      final stagingDirectory = Directory(
        p.join(mediaStore.root.path, 'tmp', 'imports', backupId),
      );
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }
      await stagingDirectory.create(recursive: true);
      stagingPath = stagingDirectory.path;
      await File(
        p.join(stagingDirectory.path, 'payload.zip'),
      ).writeAsBytes(payload, flush: true);
      onProgress(const BackupProgress(stage: '校验内容', fraction: 0.64));
      final snapshot = await _decodePayload(
        payload,
        expectedBackupId: backupId,
      );
      final inspection = await repository.inspectBackupSnapshot(
        backupId: backupId,
        snapshot: snapshot,
        stagingPath: stagingPath,
      );
      onProgress(const BackupProgress(stage: '预检完成', fraction: 1));
      return inspection;
    } on Object catch (error) {
      if (stagingPath != null) await _deleteStaging(stagingPath);
      if (error is FormatException) rethrow;
      throw const FormatException('备份文件已损坏');
    }
  }

  @override
  Future<ImportResult> commit(
    ImportPlan plan,
    BackupProgressCallback onProgress,
  ) async {
    if (!plan.isReady) throw StateError('请先处理全部冲突');
    onProgress(const BackupProgress(stage: '合并记录', fraction: 0.2));
    try {
      onProgress(const BackupProgress(stage: '写入图片', fraction: 0.56));
      final result = await repository.commitImport(plan);
      onProgress(const BackupProgress(stage: '完成导入', fraction: 1));
      return result;
    } finally {
      final stagingPath = plan.inspection.stagingPath;
      if (stagingPath != null) await _deleteStaging(stagingPath);
    }
  }

  @override
  Future<void> deleteArtifact(BackupArtifact artifact) async {
    final file = File(artifact.filePath);
    if (await file.exists()) await file.delete();
  }

  Future<List<int>> _buildPayload({
    required String backupId,
    required DateTime createdAt,
    required BackupSnapshot snapshot,
  }) async {
    final entries = <String, List<int>>{};
    final manifest = {
      'magic': 'HAOCHIBU_PAYLOAD',
      'schemaVersion': schemaVersion,
      'backupId': backupId,
      'createdAtUtc': createdAt.toIso8601String(),
      'recordCount': snapshot.records.length,
      'mediaCount': snapshot.media.length,
    };
    entries['manifest.json'] = _jsonBytes(manifest);
    entries['restaurants.ndjson'] = _ndjsonBytes(snapshot.restaurants);
    entries['records.ndjson'] = _ndjsonBytes(snapshot.records);
    entries['meal_items.ndjson'] = _ndjsonBytes(snapshot.items);
    entries['tags.ndjson'] = _ndjsonBytes(snapshot.tags);
    entries['record_tags.ndjson'] = _ndjsonBytes(snapshot.recordTags);
    entries['record_revisions.ndjson'] = _ndjsonBytes(snapshot.revisions);

    final mediaIndex = <Map<String, dynamic>>[];
    for (final media in snapshot.media) {
      final metadata = {...media.metadata};
      final hash = _stringValue(metadata, 'sha256');
      if (!_isSha256(hash)) throw const FormatException('媒体哈希格式错误');
      if (media.bytes.length > maxMediaBytes) {
        throw const FormatException('单张媒体超过 30 MiB 限制');
      }
      final actualHash = _sha256Hex(media.bytes);
      if (actualHash != hash) {
        throw const FormatException('媒体内容校验失败');
      }
      final archivePath = 'media/$hash';
      metadata['archivePath'] = archivePath;
      mediaIndex.add(metadata);
      entries.putIfAbsent(archivePath, () => media.bytes);
    }
    entries['media/index.ndjson'] = _ndjsonBytes(mediaIndex);
    final checksumLines = <String>[];
    for (final name in entries.keys.toList()..sort()) {
      checksumLines.add('${_sha256Hex(entries[name]!)}  $name');
    }
    entries['checksums.sha256'] = utf8.encode('${checksumLines.join('\n')}\n');

    final archive = Archive();
    for (final entry in entries.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    return ZipEncoder().encode(archive);
  }

  Map<String, List<int>> _decodeArchive(
    List<int> bytes, {
    required int maxBytes,
  }) {
    if (bytes.length > maxBytes) throw const FormatException('归档文件过大');
    final decoded = ZipDecoder().decodeBytes(bytes);
    final entries = <String, List<int>>{};
    var uncompressed = 0;
    for (final file in decoded.files) {
      _validateArchivePath(file.name);
      final content = _fileContent(file);
      uncompressed += content.length;
      if (uncompressed > maxBytes) {
        throw const FormatException('归档解压后过大');
      }
      if (entries.containsKey(file.name)) {
        throw const FormatException('归档包含重复路径');
      }
      entries[file.name] = content;
    }
    if (bytes.isNotEmpty && uncompressed / bytes.length > maxCompressionRatio) {
      throw const FormatException('归档压缩比异常');
    }
    return entries;
  }

  String _readPayloadBackupId(List<int> bytes) {
    final entries = _decodeArchive(bytes, maxBytes: maxPayloadBytes);
    final manifestBytes = entries['manifest.json'];
    if (manifestBytes == null) {
      throw const FormatException('备份内容不完整');
    }
    final manifest = _jsonObject(manifestBytes);
    final backupId = _stringValue(manifest, 'backupId');
    if (_stringValue(manifest, 'magic') != 'HAOCHIBU_PAYLOAD' ||
        _intValue(manifest, 'schemaVersion') != schemaVersion ||
        !_isUuid(backupId)) {
      throw const FormatException('备份版本不兼容');
    }
    return backupId;
  }

  Future<BackupSnapshot> _decodePayload(
    List<int> bytes, {
    required String expectedBackupId,
  }) async {
    final entries = _decodeArchive(bytes, maxBytes: maxPayloadBytes);
    final required = <String>{
      'manifest.json',
      'restaurants.ndjson',
      'records.ndjson',
      'meal_items.ndjson',
      'tags.ndjson',
      'record_tags.ndjson',
      'record_revisions.ndjson',
      'media/index.ndjson',
      'checksums.sha256',
    };
    if (!entries.keys.toSet().containsAll(required)) {
      throw const FormatException('备份内容不完整');
    }
    final checksums = _readChecksums(entries['checksums.sha256']!);
    final actualChecksumPaths = entries.keys
        .where((name) => name != 'checksums.sha256')
        .toSet();
    final allowedPayloadPaths = <String>{
      ...required,
      ...entries.keys.where(_isSafeMediaArchivePath),
    }..remove('checksums.sha256');
    if (!actualChecksumPaths.every(allowedPayloadPaths.contains)) {
      throw const FormatException('备份包含未知归档路径');
    }
    if (checksums.keys.toSet().length != actualChecksumPaths.length ||
        !checksums.keys.toSet().containsAll(actualChecksumPaths)) {
      throw const FormatException('备份校验清单不完整');
    }
    for (final entry in actualChecksumPaths) {
      if (_sha256Hex(entries[entry]!) != checksums[entry]) {
        throw const FormatException('备份校验失败');
      }
    }

    final manifest = _jsonObject(entries['manifest.json']!);
    if (_stringValue(manifest, 'magic') != 'HAOCHIBU_PAYLOAD' ||
        _intValue(manifest, 'schemaVersion') != schemaVersion ||
        _stringValue(manifest, 'backupId') != expectedBackupId) {
      throw const FormatException('备份版本不兼容');
    }
    final restaurants = _readNdjson(entries['restaurants.ndjson']!);
    final records = _readNdjson(entries['records.ndjson']!);
    final items = _readNdjson(entries['meal_items.ndjson']!);
    final tags = _readNdjson(entries['tags.ndjson']!);
    final recordTags = _readNdjson(entries['record_tags.ndjson']!);
    final revisions = _readNdjson(entries['record_revisions.ndjson']!);
    final mediaMetadata = _readNdjson(entries['media/index.ndjson']!);
    final totalEntries =
        restaurants.length +
        records.length +
        items.length +
        tags.length +
        recordTags.length +
        revisions.length +
        mediaMetadata.length;
    if (records.length > maxEntries || totalEntries > maxEntries) {
      throw const FormatException('备份条目数量超过限制');
    }
    _validateSnapshotRows(
      restaurants: restaurants,
      records: records,
      items: items,
      tags: tags,
      recordTags: recordTags,
      revisions: revisions,
      mediaMetadata: mediaMetadata,
    );

    final media = <SnapshotMedia>[];
    for (final metadata in mediaMetadata) {
      final hash = _stringValue(metadata, 'sha256');
      final archivePath = _stringValue(metadata, 'archivePath');
      final bytesForMedia = entries[archivePath];
      if (bytesForMedia == null) throw const FormatException('媒体文件缺失');
      if (bytesForMedia.length > maxMediaBytes ||
          _sha256Hex(bytesForMedia) != hash) {
        throw const FormatException('媒体校验失败');
      }
      final expectedSize = metadata['byteSize'];
      if (expectedSize is int && expectedSize != bytesForMedia.length) {
        throw const FormatException('媒体尺寸不匹配');
      }
      media.add(SnapshotMedia(metadata: metadata, bytes: bytesForMedia));
    }
    return BackupSnapshot(
      restaurants: restaurants,
      records: records,
      items: items,
      tags: tags,
      recordTags: recordTags,
      revisions: revisions,
      media: media,
    );
  }

  void _validateSnapshotRows({
    required List<Map<String, dynamic>> restaurants,
    required List<Map<String, dynamic>> records,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> tags,
    required List<Map<String, dynamic>> recordTags,
    required List<Map<String, dynamic>> revisions,
    required List<Map<String, dynamic>> mediaMetadata,
  }) {
    final restaurantIds = _uniqueIds(restaurants, 'id');
    final recordIds = _uniqueIds(records, 'id');
    final tagIds = _uniqueIds(tags, 'id');
    for (final row in records) {
      _requireUuid(row, 'id');
      if (!_isUuid(_stringValue(row, 'restaurantId')) ||
          !restaurantIds.contains(_stringValue(row, 'restaurantId'))) {
        throw const FormatException('记录引用了未知店铺');
      }
      if (_dateFrom(row, 'eatenAt') == null ||
          _dateFrom(row, 'createdAt') == null ||
          _dateFrom(row, 'updatedAt') == null ||
          !_isSha256(_stringValue(row, 'contentHash'))) {
        throw const FormatException('记录字段格式错误');
      }
      final deletedAt = row['deletedAt'];
      if (deletedAt != null &&
          (deletedAt is! String || DateTime.tryParse(deletedAt) == null)) {
        throw const FormatException('删除时间格式错误');
      }
    }
    for (final row in items) {
      _requireUuid(row, 'id');
      if (!recordIds.contains(_stringValue(row, 'recordId'))) {
        throw const FormatException('菜品引用了未知记录');
      }
    }
    for (final row in recordTags) {
      if (!recordIds.contains(_stringValue(row, 'recordId')) ||
          !tagIds.contains(_stringValue(row, 'tagId'))) {
        throw const FormatException('标签关联无效');
      }
    }
    for (final row in revisions) {
      _requireUuid(row, 'id');
      if (!recordIds.contains(_stringValue(row, 'recordId')) ||
          !_isSha256(_stringValue(row, 'contentHash')) ||
          _dateFrom(row, 'changedAt') == null) {
        throw const FormatException('修订记录无效');
      }
    }
    for (final row in mediaMetadata) {
      final hash = _stringValue(row, 'sha256');
      if (!recordIds.contains(_stringValue(row, 'recordId')) ||
          !_isSha256(hash) ||
          _stringValue(row, 'archivePath') != 'media/$hash') {
        throw const FormatException('媒体索引无效');
      }
    }
  }

  Set<String> _uniqueIds(List<Map<String, dynamic>> rows, String key) {
    final ids = <String>{};
    for (final row in rows) {
      final id = _stringValue(row, key);
      if (!_isUuid(id) || !ids.add(id)) {
        throw const FormatException('备份包含重复或非法 UUID');
      }
    }
    return ids;
  }

  Map<String, String> _readChecksums(List<int> bytes) {
    final result = <String, String>{};
    for (final line in utf8.decode(bytes).split('\n')) {
      if (line.trim().isEmpty) continue;
      final separator = line.indexOf('  ');
      if (separator <= 0) throw const FormatException('校验清单格式错误');
      final hash = line.substring(0, separator);
      final path = line.substring(separator + 2);
      if (!_isSha256(hash) ||
          !_isSafePayloadPath(path) ||
          result.containsKey(path)) {
        throw const FormatException('校验清单包含非法路径');
      }
      result[path] = hash;
    }
    return result;
  }

  List<Map<String, dynamic>> _readNdjson(List<int> bytes) {
    final rows = <Map<String, dynamic>>[];
    for (final line in utf8.decode(bytes).split('\n')) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map) throw const FormatException('NDJSON 行格式错误');
      rows.add(Map<String, dynamic>.from(decoded));
      if (rows.length > maxEntries) {
        throw const FormatException('NDJSON 条目过多');
      }
    }
    return rows;
  }

  Map<String, dynamic> _jsonObject(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('JSON 对象格式错误');
    return Map<String, dynamic>.from(decoded);
  }

  List<int> _jsonBytes(Object value) => utf8.encode(jsonEncode(value));

  List<int> _ndjsonBytes(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const <int>[];
    return utf8.encode('${rows.map(jsonEncode).join('\n')}\n');
  }

  void _validateArchivePath(String name) {
    if (!_isSafePayloadPath(name)) throw const FormatException('归档路径非法');
  }

  bool _isSafePayloadPath(String path) {
    if (path.isEmpty || path.startsWith('/') || path.startsWith('\\')) {
      return false;
    }
    if (path.contains('\\') || path.contains(':')) return false;
    final parts = path.split('/');
    return !parts.any((part) => part.isEmpty || part == '.' || part == '..');
  }

  bool _isSafeMediaArchivePath(String path) {
    final parts = path.split('/');
    return parts.length == 2 && parts.first == 'media' && _isSha256(parts.last);
  }

  List<int> _fileContent(ArchiveFile file) {
    return List<int>.from(file.content);
  }

  Future<void> _deleteStaging(String path) async {
    final directory = Directory(path);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  String _fileTimestamp(DateTime value) {
    final utc = value.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}-'
        '${utc.hour.toString().padLeft(2, '0')}${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}';
  }

  String _stringValue(
    Map<String, dynamic> map,
    String key, {
    String fallback = '',
  }) {
    final value = map[key];
    return value is String ? value : fallback;
  }

  int _intValue(Map<String, dynamic> map, String key, {int fallback = 0}) {
    final value = map[key];
    return value is int ? value : fallback;
  }

  DateTime? _dateFrom(Map<String, dynamic> map, String key) {
    final value = map[key];
    return value is String ? DateTime.tryParse(value)?.toUtc() : null;
  }

  void _requireUuid(Map<String, dynamic> row, String key) {
    if (!_isUuid(_stringValue(row, key))) {
      throw const FormatException('备份包含非法 UUID');
    }
  }

  bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  String _sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();
}
