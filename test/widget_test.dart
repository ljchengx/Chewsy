import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chewsy/main.dart';
import 'package:chewsy/app/app_runtime.dart';
import 'package:chewsy/domain/models.dart';

void main() {
  testWidgets('首页可以进入判词记录流程', (WidgetTester tester) async {
    final runtime = await AppRuntime.forTesting();
    addTearDown(runtime.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('好吃不'), findsOneWidget);
    expect(find.text('还没有吃饭记录'), findsOneWidget);
    expect(find.text('先选一个判词，记下第一家店。'), findsOneWidget);

    await tester.tap(find.text('记一口'));
    await tester.pumpAndSettle();

    expect(find.text('这家店，怎么判？'), findsOneWidget);
  });

  testWidgets('记录详情可以进入编辑页并保存原记录', (WidgetTester tester) async {
    final runtime = await AppRuntime.forTesting();
    addTearDown(runtime.dispose);
    final created = await runtime.records.publishDraft(
      RecordDraft(
        verdict: Verdict.keep,
        eatenAt: DateTime(2026, 8, 20, 19),
        restaurant: '编辑测试店',
        dishes: const ['测试菜'],
      ),
    );
    final record = (await runtime.records.loadRecords()).single;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],
        child: MaterialApp(
          home: MealDetailPage(
            record: record,
            recordStore: runtime.records,
            onChanged: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(find.text('编辑记录'), findsOneWidget);
    expect(find.text('编辑测试店'), findsOneWidget);
    expect(find.text('测试菜'), findsOneWidget);

    await tester.tap(find.text('踩雷'));
    await tester.pump();
    await tester.ensureVisible(find.text('保存修改'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    final updated = (await runtime.records.loadRecords()).single;
    expect(updated.id, created.id);
    expect(updated.revision, 2);
    expect(updated.verdict, Verdict.skip);
    expect(find.text('这次到店，记下什么？'), findsOneWidget);
  });

  testWidgets('记录详情确认永久删除后移除记录', (WidgetTester tester) async {
    final runtime = await AppRuntime.forTesting();
    addTearDown(runtime.dispose);
    final created = await runtime.records.publishDraft(
      RecordDraft(
        verdict: Verdict.skip,
        eatenAt: DateTime(2026, 8, 20, 20),
        restaurant: '删除测试店',
      ),
    );
    final record = (await runtime.records.loadRecords()).single;

    await tester.pumpWidget(
      MaterialApp(
        home: MealDetailPage(
          record: record,
          recordStore: runtime.records,
          onChanged: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('永久删除'));
    await tester.pumpAndSettle();

    expect(find.text('永久删除这次记录？'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(await runtime.records.loadRecords(), isEmpty);
    expect(created.id, isNotEmpty);
  });
}
