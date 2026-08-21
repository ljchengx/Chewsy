import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chewsy/app/app_runtime.dart';
import 'package:chewsy/domain/backup_models.dart';
import 'package:chewsy/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('普通备份可以预检、导入并防止重复导入', () async {
    final source = await AppRuntime.forTesting();
    final target = await AppRuntime.forTesting();
    addTearDown(source.dispose);
    addTearDown(target.dispose);

    await source.records.publishDraft(
      RecordDraft(
        verdict: Verdict.keep,
        eatenAt: DateTime(2026, 8, 20, 19, 0),
        restaurant: '测试店',
        dishes: ['测试菜'],
        note: '备份测试',
        reasons: {'够锅气'},
        photoPath: 'assets/images/hero_food.jpg',
      ),
    );

    final artifact = await source.backup.create(const BackupRequest(), (_) {});
    addTearDown(() => source.backup.deleteArtifact(artifact));

    final inspection = await target.backup.inspect(
      ImportRequest(filePath: artifact.filePath),
      (_) {},
    );
    expect(inspection.counts.added, 1);
    expect(inspection.conflicts, isEmpty);

    final result = await target.backup.commit(
      ImportPlan(inspection: inspection),
      (_) {},
    );
    expect(result.counts.added, 1);
    expect((await target.records.loadRecords()).length, 1);

    final repeated = await target.backup.inspect(
      ImportRequest(filePath: artifact.filePath),
      (_) {},
    );
    expect(repeated.alreadyImported, isTrue);
    final repeatedResult = await target.backup.commit(
      ImportPlan(inspection: repeated),
      (_) {},
    );
    expect(repeatedResult.alreadyImported, isTrue);
  });

  test('普通备份无需口令即可导入', () async {
    final source = await AppRuntime.forTesting();
    final target = await AppRuntime.forTesting();
    addTearDown(source.dispose);
    addTearDown(target.dispose);

    await source.records.publishDraft(
      RecordDraft(
        verdict: Verdict.keep,
        eatenAt: DateTime(2026, 8, 20, 19, 0),
        restaurant: '轻量备份店',
        dishes: ['轻量备份菜'],
      ),
    );

    final artifact = await source.backup.create(const BackupRequest(), (_) {});
    addTearDown(() => source.backup.deleteArtifact(artifact));

    final inspection = await target.backup.inspect(
      ImportRequest(filePath: artifact.filePath),
      (_) {},
    );
    expect(inspection.counts.added, 1);

    await target.backup.commit(ImportPlan(inspection: inspection), (_) {});
    expect((await target.records.loadRecords()).length, 1);
  });

  test('损坏的备份不会改变现有记录', () async {
    final runtime = await AppRuntime.forTesting();
    addTearDown(runtime.dispose);
    await runtime.records.publishDraft(
      RecordDraft(
        verdict: Verdict.neutral,
        eatenAt: DateTime(2026, 8, 20, 19, 0),
        restaurant: '本机店',
        dishes: ['本机菜'],
      ),
    );
    final artifact = await runtime.backup.create(const BackupRequest(), (_) {});
    addTearDown(() => runtime.backup.deleteArtifact(artifact));

    final bytes = await File(artifact.filePath).readAsBytes();
    bytes[bytes.length ~/ 2] ^= 0x01;
    final tampered = File('${artifact.filePath}.tampered');
    await tampered.writeAsBytes(bytes, flush: true);
    addTearDown(() async {
      if (await tampered.exists()) await tampered.delete();
    });

    expect(
      () => runtime.backup.inspect(
        ImportRequest(filePath: tampered.path),
        (_) {},
      ),
      throwsA(isA<FormatException>()),
    );
    expect((await runtime.records.loadRecords()).length, 1);
  });

  test('备份文件篡改会被拒绝', () async {
    final runtime = await AppRuntime.forTesting();
    addTearDown(runtime.dispose);
    final artifact = await runtime.backup.create(const BackupRequest(), (_) {});
    final bytes = await File(artifact.filePath).readAsBytes();
    bytes[bytes.length ~/ 2] ^= 0x01;
    final tampered = File('${artifact.filePath}.tampered');
    await tampered.writeAsBytes(bytes, flush: true);
    addTearDown(() async {
      await runtime.backup.deleteArtifact(artifact);
      if (await tampered.exists()) await tampered.delete();
    });

    expect(
      () => runtime.backup.inspect(
        ImportRequest(filePath: tampered.path),
        (_) {},
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
