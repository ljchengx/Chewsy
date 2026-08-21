import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';

class MediaStore {
  MediaStore({Directory? root}) : _root = root;

  Directory? _root;

  factory MediaStore.forTesting() {
    return MediaStore(
      root: Directory.systemTemp.createTempSync('chewsy-media-'),
    );
  }

  Directory get root {
    final value = _root;
    if (value == null) {
      throw StateError('MediaStore has not been initialized.');
    }
    return value;
  }

  Future<void> initialize() async {
    final documents = await getApplicationDocumentsDirectory();
    _root = Directory(p.join(documents.path, 'haochibu'));
    for (final child in [
      'media/original',
      'media/thumb',
      'generated',
      'tmp',
      'tmp/imports',
    ]) {
      await Directory(p.join(root.path, child)).create(recursive: true);
    }
  }

  Future<StoredMedia> importAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return _storeBytes(
      Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
      sourceName: assetPath,
    );
  }

  Future<StoredMedia> importFile(String sourcePath) async {
    return _storeBytes(
      await File(sourcePath).readAsBytes(),
      sourceName: sourcePath,
    );
  }

  Future<StoredMedia> importBytes(
    List<int> bytes, {
    required String sourceName,
  }) async {
    return _storeBytes(Uint8List.fromList(bytes), sourceName: sourceName);
  }

  Future<String> stageDraftFile(String sourcePath) async {
    if (sourcePath.startsWith('assets/')) return sourcePath;
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('图片文件不存在', sourcePath);
    }
    final extension = _extensionFor(sourcePath);
    final relative = p.posix.join(
      'tmp',
      'drafts',
      'draft-${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    final destination = _safeFile(relative);
    await destination.parent.create(recursive: true);
    await _writeAtomic(destination, await source.readAsBytes());
    return destination.path;
  }

  Future<void> deleteStagedFile(String path) async {
    if (path.startsWith('assets/')) return;
    final file = File(path);
    if (!_isInsideRoot(file) || !_isInsideDrafts(file)) return;
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteDraftFiles() async {
    final directory = Directory(p.join(root.path, 'tmp', 'drafts'));
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  Future<Uint8List> readRelative(String relativePath) async {
    final file = _safeFile(relativePath);
    return Uint8List.fromList(await file.readAsBytes());
  }

  Future<bool> existsRelative(String relativePath) async {
    return _safeFile(relativePath).exists();
  }

  Future<void> deleteRelative(String relativePath) async {
    final file = _safeFile(relativePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> materializeRelative(String relativePath) async {
    final file = _safeFile(relativePath);
    if (!await file.exists()) {
      throw FileSystemException('媒体文件不存在', file.path);
    }
    return file;
  }

  String absolutePath(String relativePath) => _safeFile(relativePath).path;

  Future<void> deleteTemporaryWorkspaces() async {
    final directory = Directory(p.join(root.path, 'tmp'));
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is Directory) {
        if (p.basename(entity.path) != 'drafts') {
          await entity.delete(recursive: true);
        }
      } else if (entity is File) {
        if (p.extension(entity.path).toLowerCase() == '.haochibu') {
          await entity.delete();
        }
      }
    }
  }

  Future<StoredMedia> _storeBytes(
    Uint8List bytes, {
    required String sourceName,
  }) async {
    if (bytes.isEmpty) {
      throw const FormatException('图片内容为空');
    }
    final sha256 = _hex(crypto.sha256.convert(bytes).bytes);
    final extension = _extensionFor(sourceName);
    final shardA = sha256.substring(0, 2);
    final shardB = sha256.substring(2, 4);
    final originalRelative = p.posix.join(
      'media',
      'original',
      shardA,
      shardB,
      '$sha256.$extension',
    );
    final thumbnailRelative = p.posix.join(
      'media',
      'thumb',
      shardA,
      shardB,
      '$sha256.jpg',
    );
    final original = _safeFile(originalRelative);
    final thumbnail = _safeFile(thumbnailRelative);

    await original.parent.create(recursive: true);
    await thumbnail.parent.create(recursive: true);
    if (!await original.exists()) {
      await _writeAtomic(original, bytes);
    }
    if (!await thumbnail.exists()) {
      await _writeAtomic(thumbnail, _makeThumbnail(bytes));
    }

    final decoded = image.decodeImage(bytes);
    return StoredMedia(
      relativePath: originalRelative.replaceAll(r'\', '/'),
      thumbnailPath: thumbnailRelative.replaceAll(r'\', '/'),
      sha256: sha256,
      mimeType: _mimeFor(extension),
      width: decoded?.width,
      height: decoded?.height,
      byteSize: bytes.length,
    );
  }

  File _safeFile(String relativePath) {
    final normalized = p.posix.normalize(relativePath.replaceAll(r'\', '/'));
    if (p.posix.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        normalized.split('/').any((part) => part.contains(':'))) {
      throw const FormatException('非法媒体路径');
    }
    return File(p.join(root.path, normalized));
  }

  bool _isInsideRoot(File file) {
    final rootPath = p.normalize(root.absolute.path).toLowerCase();
    final filePath = p.normalize(file.absolute.path).toLowerCase();
    return filePath == rootPath ||
        filePath.startsWith('$rootPath${p.separator}');
  }

  bool _isInsideDrafts(File file) {
    final draftsPath = p
        .normalize(p.join(root.path, 'tmp', 'drafts'))
        .toLowerCase();
    final filePath = p.normalize(file.absolute.path).toLowerCase();
    return filePath.startsWith('$draftsPath${p.separator}');
  }

  Future<void> _writeAtomic(File destination, List<int> bytes) async {
    final temporary = File(
      '${destination.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.writeAsBytes(bytes, flush: true);
    if (await destination.exists()) {
      await temporary.delete();
      return;
    }
    await temporary.rename(destination.path);
  }

  List<int> _makeThumbnail(Uint8List bytes) {
    try {
      final decoded = image.decodeImage(bytes);
      if (decoded == null) return bytes;
      final resized = image.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? 512 : null,
        height: decoded.height > decoded.width ? 512 : null,
      );
      return image.encodeJpg(resized, quality: 82);
    } catch (_) {
      return bytes;
    }
  }

  String _extensionFor(String sourceName) {
    final extension = p
        .extension(sourceName)
        .replaceFirst('.', '')
        .toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
        return extension == 'jpeg' ? 'jpg' : extension;
      default:
        return 'bin';
    }
  }

  String _mimeFor(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
