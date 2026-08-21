import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chewsy/app/app_runtime.dart';
import 'package:chewsy/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('一条记录可以保存多道菜和多个理由，并按店铺搜索聚合', () async {
    final runtime = await AppRuntime.forTesting();
    addTearDown(runtime.dispose);
    final firstTime = DateTime(2026, 8, 19, 18, 30);

    final first = await runtime.records.publishDraft(
      RecordDraft(
        verdict: Verdict.keep,
        eatenAt: firstTime,
        restaurant: '测试店',
        dishes: const ['烤鱼', '凉菜'],
        reasons: const {'味道好', '分量足'},
      ),
    );
    await runtime.records.publishDraft(
      RecordDraft(
        verdict: Verdict.neutral,
        eatenAt: DateTime(2026, 8, 20, 12),
        restaurant: '测试店',
        dishes: const ['米饭'],
        reasons: const {'一般'},
      ),
    );

    final records = await runtime.records.loadRecords();
    expect(records, hasLength(2));
    expect(records.last.id, first.id);
    expect(records.last.dishes, ['烤鱼', '凉菜']);
    expect(records.last.reasons, containsAll(<String>['味道好', '分量足']));

    final results = await runtime.records.searchRestaurants('烤鱼');
    expect(results, hasLength(1));
    expect(results.single.name, '测试店');
    expect(results.single.visitCount, 2);
    expect(results.single.latestVerdict, Verdict.neutral);
    expect(results.single.latestEatenAt, DateTime(2026, 8, 20, 12));
    expect(results.single.recentDishes, containsAll(<String>['米饭', '烤鱼']));
    expect(results.single.matchedDishes, ['烤鱼']);

    final history = await runtime.records.loadRestaurantHistory(
      records.first.restaurantId!,
    );
    expect(history.visits, hasLength(2));
    expect(history.visits.first.eatenAt, DateTime(2026, 8, 20, 12));
  });

  test('编辑保留记录 UUID，增加修订号；删除会移除记录', () async {
    final runtime = await AppRuntime.forTesting();
    addTearDown(runtime.dispose);
    final created = await runtime.records.publishDraft(
      RecordDraft(
        verdict: Verdict.skip,
        eatenAt: DateTime(2026, 8, 20),
        restaurant: '要修改的店',
        dishes: const ['旧菜'],
      ),
    );

    final updated = await runtime.records.updateRecord(
      recordId: created.id,
      draft: RecordDraft(
        verdict: Verdict.keep,
        eatenAt: DateTime(2026, 8, 21),
        restaurant: '改过的店',
        dishes: const ['新菜一', '新菜二'],
        reasons: const {'性价比高', '自定义'},
      ),
    );
    expect(updated.id, created.id);
    expect(updated.revision, 2);
    expect(updated.restaurant, '改过的店');
    expect(updated.dishes, ['新菜一', '新菜二']);
    expect(updated.reasons, containsAll(<String>['性价比高', '自定义']));

    await runtime.records.deleteRecord(created.id);
    expect(await runtime.records.loadRecords(), isEmpty);
  });

  test('店名为空时不能发布，菜名和图片为空可以发布', () async {
    final runtime = await AppRuntime.forTesting();
    addTearDown(runtime.dispose);
    expect(
      () => runtime.records.publishDraft(
        RecordDraft(verdict: Verdict.neutral, eatenAt: DateTime(2026, 8, 20)),
      ),
      throwsArgumentError,
    );

    await runtime.records.publishDraft(
      RecordDraft(
        verdict: Verdict.neutral,
        eatenAt: DateTime(2026, 8, 20),
        restaurant: '只记店铺',
      ),
    );
    final record = (await runtime.records.loadRecords()).single;
    expect(record.dishes, isEmpty);
    expect(record.photo, isEmpty);
  });

  test('Debug 示例只在首次播种，删除后不会再次出现', () async {
    final runtime = await AppRuntime.forTesting();
    addTearDown(runtime.dispose);
    final sample = MealRecord(
      restaurant: '一次性示例店',
      dishes: const ['示例菜'],
      verdict: Verdict.keep,
      reasons: const ['味道好'],
      photo: '',
      eatenAt: DateTime(2026, 8, 20),
    );

    await runtime.records.seedDebugRecords([sample]);
    final seeded = (await runtime.records.loadRecords()).single;
    await runtime.records.deleteRecord(seeded.id);
    await runtime.records.seedDebugRecords([sample]);

    expect(await runtime.records.loadRecords(), isEmpty);
  });

  test('草稿清除不会被之前排队的保存重新写回', () async {
    final runtime = await AppRuntime.forTesting();
    addTearDown(runtime.dispose);

    final save = runtime.records.saveDraft(
      RecordDraft(
        verdict: Verdict.keep,
        eatenAt: DateTime(2026, 8, 20),
        restaurant: '不会残留的草稿',
      ),
    );
    final clear = runtime.records.clearDraft();
    await Future.wait([save, clear]);

    expect(await runtime.records.loadDraft(), isNull);
  });

  test('Debug 播种不会覆盖未完成草稿', () async {
    final runtime = await AppRuntime.forTesting();
    addTearDown(runtime.dispose);
    final draft = RecordDraft(
      verdict: Verdict.neutral,
      eatenAt: DateTime(2026, 8, 20),
      restaurant: '还没写完的店',
    );
    await runtime.records.saveDraft(draft);

    await runtime.records.seedDebugRecords([
      MealRecord(
        restaurant: '示例店',
        dishes: const [],
        verdict: Verdict.keep,
        reasons: const [],
        photo: '',
        eatenAt: DateTime(2026, 8, 20),
      ),
    ]);

    expect((await runtime.records.loadDraft())?.restaurant, '还没写完的店');
    expect(await runtime.records.loadRecords(), isEmpty);
  });

  test('历史日期不会被显示为今天，删除记录后店名建议也会清理', () async {
    final runtime = await AppRuntime.forTesting();
    addTearDown(runtime.dispose);
    final created = await runtime.records.publishDraft(
      RecordDraft(
        verdict: Verdict.neutral,
        eatenAt: DateTime(2000, 1, 2, 12),
        restaurant: '只存在一条记录的店',
      ),
    );
    final record = (await runtime.records.loadRecords()).single;
    expect(record.time, contains('2000.01.02'));

    await runtime.records.deleteRecord(created.id);
    expect(await runtime.records.suggestRestaurantNames('只存在一条'), isEmpty);
  });

  test('草稿图片先写入私有暂存目录，清除草稿时一并删除', () async {
    final runtime = await AppRuntime.forTesting();
    addTearDown(runtime.dispose);
    final source = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}chewsy-draft-test.jpg',
    );
    await source.writeAsBytes([1, 2, 3, 4], flush: true);
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });

    final staged = await runtime.records.stageDraftPhoto(source.path);
    expect(staged, contains('draft-'));
    await runtime.records.saveDraft(
      RecordDraft(
        verdict: Verdict.keep,
        eatenAt: DateTime(2026, 8, 20),
        restaurant: '有暂存图片的店',
        photoPath: staged,
      ),
    );
    expect((await runtime.records.loadDraft())?.photoPath, staged);

    await runtime.records.clearDraft();
    expect(await File(staged).exists(), isFalse);
  });
}
