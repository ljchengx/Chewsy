import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'app/app_runtime.dart';
import 'data/repositories/record_repository.dart';
import 'domain/backup_models.dart';
import 'domain/models.dart';
import 'services/backup_service.dart';

part 'features/record/record_pages.dart';
part 'features/universe/universe_pages.dart';
part 'features/data_center/data_center_pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final runtime = await AppRuntime.bootstrap();
    runApp(
      ProviderScope(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],
        child: const MyApp(),
      ),
    );
  } on Object catch (error) {
    runApp(BootstrapErrorApp(error: error));
  }
}

const kPaper = Color(0xFFFFF8F0);
const kPaperWhite = Color(0xFFFFFCF8);
const kInk = Color(0xFF0B0B0B);
const kOrange = Color(0xFFFF6508);
const kPink = Color(0xFFF2388B);
const kLime = Color(0xFFD8FF16);
const kPurple = Color(0xFF7C4DFF);
const kMuted = Color(0xFF858381);
const kSoftLine = Color(0xFFD8D1C8);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '好吃不',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kPaper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kOrange,
          brightness: Brightness.light,
        ).copyWith(primary: kInk, onPrimary: Colors.white, surface: kPaper),
        fontFamily: 'Arial',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: kInk, fontSize: 16, height: 1.25),
          bodyMedium: TextStyle(color: kInk, fontSize: 14, height: 1.25),
          titleLarge: TextStyle(
            color: kInk,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kPaperWhite,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: kInk, width: 1.4),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: kOrange, width: 2),
          ),
        ),
      ),
      home: const ChewsyShell(),
    );
  }
}

extension VerdictVisuals on Verdict {
  Color get color {
    switch (this) {
      case Verdict.keep:
        return kOrange;
      case Verdict.skip:
        return kPink;
      case Verdict.neutral:
        return kPaperWhite;
    }
  }

  IconData get icon {
    switch (this) {
      case Verdict.keep:
        return Icons.bolt_rounded;
      case Verdict.skip:
        return Icons.close_rounded;
      case Verdict.neutral:
        return Icons.sentiment_neutral_rounded;
    }
  }
}

class BootstrapErrorApp extends StatefulWidget {
  const BootstrapErrorApp({required this.error, super.key});

  final Object error;

  @override
  State<BootstrapErrorApp> createState() => _BootstrapErrorAppState();
}

class _BootstrapErrorAppState extends State<BootstrapErrorApp> {
  late Object _error = widget.error;
  bool _retrying = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: kPaper,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '数据初始化失败，请重试。\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _retrying ? null : _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(_retrying ? '重试中…' : '重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      final runtime = await AppRuntime.bootstrap();
      if (!mounted) return;
      runApp(
        ProviderScope(
          overrides: [appRuntimeProvider.overrideWithValue(runtime)],
          child: const MyApp(),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _retrying = false;
      });
    }
  }
}

class ChewsyShell extends ConsumerStatefulWidget {
  const ChewsyShell({super.key});

  @override
  ConsumerState<ChewsyShell> createState() => _ChewsyShellState();
}

class _ChewsyShellState extends ConsumerState<ChewsyShell> {
  int _tab = 0;
  int _recordStep = 0;
  Verdict? _draftVerdict;
  RecordDraft? _draft;
  List<MealRecord> _records = const [];
  bool _loading = true;
  int _dataVersion = 0;

  DriftRecordRepository get _recordStore =>
      ref.read(appRuntimeProvider).records;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await _recordStore.loadRecords(
      query: const RecordQuery(limit: 1000),
    );
    final draft = await _recordStore.loadDraft();
    if (!mounted) return;
    setState(() {
      _records = records;
      _draft = draft;
      _draftVerdict = draft?.verdict;
      _loading = false;
      _dataVersion++;
    });
  }

  void _selectTab(int index) {
    setState(() {
      _tab = index;
      if (index != 1) {
        _recordStep = 0;
        _draftVerdict = null;
      }
    });
  }

  void _startRecord([Verdict? verdict]) {
    unawaited(_beginRecord(verdict: verdict));
  }

  Future<void> _beginRecord({Verdict? verdict, String? restaurant}) async {
    final storedDraft = _draft ?? await _recordStore.loadDraft();
    if (!mounted) return;
    if (storedDraft != null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: kPaperWhite,
          title: const Text(
            '上次的记录还没写完',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: const Text('继续上次记录，还是重新开始？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('先不记'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'restart'),
              child: const Text('重新开始'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kOrange,
                foregroundColor: kInk,
              ),
              onPressed: () => Navigator.pop(context, 'continue'),
              child: const Text('继续上次记录'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null || choice == 'cancel') return;
      if (choice == 'continue') {
        setState(() {
          _tab = 1;
          _recordStep = 1;
          _draft = storedDraft;
          _draftVerdict = storedDraft.verdict;
        });
        return;
      }
      await _recordStore.clearDraft();
    }

    final fresh = RecordDraft(
      verdict: verdict ?? Verdict.neutral,
      eatenAt: DateTime.now(),
      restaurant: restaurant ?? '',
    );
    setState(() {
      _tab = 1;
      _recordStep = verdict == null ? 0 : 1;
      _draftVerdict = verdict;
      _draft = verdict == null && restaurant == null ? null : fresh;
    });
    if (verdict != null || restaurant != null) {
      unawaited(_recordStore.saveDraft(fresh));
    }
  }

  void _chooseVerdict(Verdict verdict) {
    setState(() {
      _draftVerdict = verdict;
      _recordStep = 1;
      _draft =
          (_draft ?? RecordDraft(verdict: verdict, eatenAt: DateTime.now()))
              .copyWith(verdict: verdict);
    });
    unawaited(_recordStore.saveDraft(_draft!));
  }

  void _saveDraft(RecordDraft draft) {
    setState(() {
      _draft = draft;
      _draftVerdict = draft.verdict;
    });
    unawaited(_recordStore.saveDraft(draft));
  }

  Future<void> _publishRecord(RecordDraft draft) async {
    await _recordStore.saveDraft(draft);
    await _recordStore.publishDraft(draft);
    await _loadRecords();
    if (!mounted) return;
    setState(() {
      _tab = 0;
      _recordStep = 0;
      _draftVerdict = null;
      _draft = null;
    });
    _showMessage('这次到店已经记下了。');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: kInk,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final pageWidth = math.min(constraints.maxWidth, 540.0);
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: pageWidth,
              height: constraints.maxHeight,
              child: SafeArea(child: _buildTab()),
            ),
          );
        },
      ),
      bottomNavigationBar: _tab == 1
          ? null
          : SizedBox(
              height: 112,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final pageWidth = math.min(constraints.maxWidth, 540.0);
                  return Center(
                    child: SizedBox(
                      width: pageWidth,
                      child: SafeArea(
                        top: false,
                        child: MainNavigation(
                          selectedIndex: _tab,
                          onSelected: _selectTab,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kOrange));
    }
    switch (_tab) {
      case 1:
        return _recordStep == 0
            ? RecordVerdictPage(
                onBack: () => _selectTab(0),
                onChoose: _chooseVerdict,
              )
            : RecordDetailsPage(
                verdict: _draftVerdict ?? Verdict.neutral,
                initialDraft: _draft,
                onBack: () => setState(() => _recordStep = 0),
                onDraftChanged: _saveDraft,
                onPublish: _publishRecord,
                suggestRestaurants: _recordStore.suggestRestaurantNames,
                stagePhoto: _recordStore.stageDraftPhoto,
              );
      case 2:
        return UniversePage(
          records: _records,
          refreshToken: _dataVersion,
          recordStore: _recordStore,
          onOpenRecord: (record) => _open(
            MealDetailPage(
              record: record,
              recordStore: _recordStore,
              onChanged: (_) => _loadRecords(),
            ),
          ),
          onOpenRestaurant: (restaurantId) => _open(
            RestaurantDetailPage(
              restaurantId: restaurantId,
              recordStore: _recordStore,
              onRecord: (restaurant) =>
                  unawaited(_beginRecord(restaurant: restaurant)),
              onRecordChanged: _loadRecords,
            ),
          ),
          onOpenRandom: () => _open(BlindPickPage(records: _records)),
          onOpenReport: _records.isEmpty
              ? () => _showMessage('先记下一口，再生成战报。')
              : () => _open(BattleReportPage(record: _records.first)),
        );
      case 3:
        return DataCenterPage(
          recordStore: _recordStore,
          refreshToken: _dataVersion,
          onBackup: () => _open(
            BackupCreatePage(backupService: ref.read(backupServiceProvider)),
          ),
          onImport: () => _open(
            ImportPreviewPage(
              backupService: ref.read(backupServiceProvider),
              onConfirmed: _handleImportResult,
            ),
          ),
        );
      case 0:
      default:
        return HomePage(
          records: _records,
          recordStore: _recordStore,
          onRecord: _startRecord,
          onOpenReport: _records.isEmpty
              ? () => _showMessage('先记下一口，再生成战报。')
              : () => _open(BattleReportPage(record: _records.first)),
          onOpenUniverse: () => _selectTab(2),
          onOpenRestaurant: (restaurantId) => _open(
            RestaurantDetailPage(
              restaurantId: restaurantId,
              recordStore: _recordStore,
              onRecord: (restaurant) =>
                  unawaited(_beginRecord(restaurant: restaurant)),
              onRecordChanged: _loadRecords,
            ),
          ),
        );
    }
  }

  Future<void> _handleImportResult(ImportResult result) async {
    await _loadRecords();
    if (!mounted) return;
    _showMessage(
      result.alreadyImported
          ? '这份备份已经导入过了。'
          : '备份已导入，新增 ${result.counts.added} 条战报。',
    );
  }
}

class BlindPickPage extends StatefulWidget {
  const BlindPickPage({required this.records, super.key});

  final List<MealRecord> records;

  @override
  State<BlindPickPage> createState() => _BlindPickPageState();
}

class _BlindPickPageState extends State<BlindPickPage> {
  MealRecord? _selected;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    final options = _keepRecords;
    _selected = options.isEmpty ? null : options.first;
  }

  List<MealRecord> get _keepRecords =>
      widget.records.where((record) => record.verdict == Verdict.keep).toList();

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          children: [
            PageHeader(title: '今晚吃啥？', onBack: () => Navigator.pop(context)),
            const SizedBox(height: 12),
            const TapeMarker(text: '从我的种草里抽', color: kPaperWhite),
            const SizedBox(height: 22),
            Text(
              '今晚就吃它了',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 37,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            if (_selected == null)
              const EmptyPaper(text: '还没有种草记录，先记下一家店。')
            else ...[
              RandomPickCard(record: _selected!),
              const SizedBox(height: 18),
              OutlineAction(
                label: '再抽一口',
                icon: Icons.refresh_rounded,
                onTap: _redraw,
              ),
              const SizedBox(height: 16),
              FilledPrimaryButton(
                label: '就吃这家',
                icon: Icons.restaurant_rounded,
                color: kLime,
                onTap: () => Navigator.pop(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _redraw() {
    final options = _keepRecords;
    if (options.length < 2) return;
    MealRecord next = _selected!;
    while (next == _selected) {
      next = options[_random.nextInt(options.length)];
    }
    setState(() => _selected = next);
  }
}

class BattleReportPage extends StatelessWidget {
  const BattleReportPage({required this.record, super.key});

  final MealRecord record;

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          children: [
            PageHeader(title: '食物战报', onBack: () => Navigator.pop(context)),
            const SizedBox(height: 18),
            ReportCard(record: record),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlineAction(
                    label: '保存图片',
                    icon: Icons.download_rounded,
                    onTap: () => _showMessage(context, '战报图片已准备好保存。'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledPrimaryButton(
                    label: '交给朋友',
                    icon: Icons.send_rounded,
                    onTap: () => _confirmShare(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '分享前请确认内容，离开应用后由目标应用处理。',
              style: TextStyle(color: kMuted, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _confirmShare(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kPaperWhite,
        title: const Text(
          '确认交给朋友？',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text('这张图片离开应用后，目标平台的隐私规则由你决定。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('先不发'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kOrange,
              foregroundColor: kInk,
            ),
            onPressed: () {
              Navigator.pop(context);
              _showMessage(context, '已交给系统分享面板。');
            },
            child: const Text('确认交接'),
          ),
        ],
      ),
    );
  }
}

class RestaurantDetailPage extends StatefulWidget {
  const RestaurantDetailPage({
    required this.restaurantId,
    required this.recordStore,
    required this.onRecord,
    required this.onRecordChanged,
    super.key,
  });

  final String restaurantId;
  final RecordStore recordStore;
  final ValueChanged<String> onRecord;
  final Future<void> Function() onRecordChanged;

  @override
  State<RestaurantDetailPage> createState() => _RestaurantDetailPageState();
}

class _RestaurantDetailPageState extends State<RestaurantDetailPage> {
  late Future<RestaurantHistory> _historyFuture;
  late String _activeRestaurantId;

  @override
  void initState() {
    super.initState();
    _activeRestaurantId = widget.restaurantId;
    _historyFuture = widget.recordStore.loadRestaurantHistory(
      _activeRestaurantId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RestaurantHistory>(
      future: _historyFuture,
      builder: (context, snapshot) {
        final history = snapshot.data;
        if (history == null) {
          return const DetailScaffold(
            child: Center(child: CircularProgressIndicator(color: kOrange)),
          );
        }
        return DetailScaffold(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: history.restaurant,
                  onBack: () => Navigator.pop(context),
                  trailing: const Icon(Icons.storefront_outlined, size: 28),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      color: kMuted,
                      size: 28,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      '${history.visits.length} 次到店记录',
                      style: const TextStyle(
                        color: kMuted,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final record in history.visits) ...[
                  TimelineRecordCard(
                    record: record,
                    onTap: () => _openRecord(record),
                  ),
                  const SizedBox(height: 14),
                ],
                if (history.visits.isEmpty)
                  const EmptyPaper(text: '这家店还没有到店记录。'),
                const SizedBox(height: 6),
                FilledPrimaryButton(
                  label: '再记一次这家店',
                  icon: Icons.add_rounded,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onRecord(history.restaurant);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openRecord(MealRecord record) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MealDetailPage(
          record: record,
          recordStore: widget.recordStore,
          onChanged: (updated) async {
            await widget.onRecordChanged();
            if (mounted) {
              _activeRestaurantId =
                  updated?.restaurantId ?? _activeRestaurantId;
              setState(() {
                _historyFuture = widget.recordStore.loadRestaurantHistory(
                  _activeRestaurantId,
                );
              });
            }
          },
        ),
      ),
    );
  }
}

class MealDetailPage extends StatefulWidget {
  const MealDetailPage({
    required this.record,
    required this.recordStore,
    required this.onChanged,
    super.key,
  });

  final MealRecord record;
  final RecordStore recordStore;
  final Future<void> Function(MealRecord? updated) onChanged;

  @override
  State<MealDetailPage> createState() => _MealDetailPageState();
}

class _MealDetailPageState extends State<MealDetailPage> {
  late MealRecord _record;

  @override
  void initState() {
    super.initState();
    _record = widget.record;
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    return DetailScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: record.restaurant,
              onBack: () => Navigator.pop(context),
              trailing: PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (value) {
                  if (value == 'edit') unawaited(_edit(context));
                  if (value == 'delete') unawaited(_delete(context));
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('永久删除')),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '这次到店，记下什么？',
              style: TextStyle(fontSize: 35, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            MarkerLabel(
              text: record.verdict.label,
              color: record.verdict.color,
            ),
            const SizedBox(height: 16),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.white, width: 8),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 12,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: LocalImage(
                      path: record.photo,
                      width: double.infinity,
                      height: 250,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 34),
            DetailField(
              icon: Icons.storefront_outlined,
              text: record.restaurant,
            ),
            const SizedBox(height: 12),
            DetailField(
              icon: Icons.room_service_outlined,
              text: record.displayDishes,
            ),
            const SizedBox(height: 24),
            SectionTitle('为什么${record.verdict.label}？'),
            const SizedBox(height: 12),
            if (record.reasons.isEmpty)
              const Text('没有额外理由', style: TextStyle(color: kMuted))
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final reason in record.reasons)
                    ReasonChip(
                      label: reason,
                      selected: true,
                      color: kOrange,
                      onTap: () {},
                    ),
                ],
              ),
            const SizedBox(height: 24),
            PaperPanel(
              padding: const EdgeInsets.all(18),
              child: Text(
                record.note.isEmpty ? '还没有写短评。' : record.note,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _formatDate(record.eatenAt),
              style: const TextStyle(
                color: kMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final record = _record;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RecordDetailsPage(
          title: '编辑记录',
          publishLabel: '保存修改',
          showDraftPill: false,
          closeAfterPublish: true,
          verdict: record.verdict,
          initialDraft: record.toDraft(),
          onBack: () => Navigator.pop(context),
          onDraftChanged: (_) {},
          allowVerdictChange: true,
          stagePhoto: widget.recordStore.stageDraftPhoto,
          onPublish: (draft) async {
            final updated = await widget.recordStore.updateRecord(
              recordId: record.id,
              draft: draft,
            );
            if (mounted) {
              setState(() => _record = updated);
            }
            await widget.onChanged(updated);
          },
          suggestRestaurants: widget.recordStore.suggestRestaurantNames,
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kPaperWhite,
        title: const Text(
          '永久删除这次记录？',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text('删除后不会进入回收站。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kPink,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.recordStore.deleteRecord(_record.id);
    await widget.onChanged(null);
    if (context.mounted) Navigator.pop(context);
  }
}

class DetailScaffold extends StatelessWidget {
  const DetailScaffold({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final pageWidth = math.min(constraints.maxWidth, 540.0);
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: pageWidth,
              height: constraints.maxHeight,
              child: SafeArea(child: child),
            ),
          );
        },
      ),
    );
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({this.title = '好吃不', this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SpeechLogo(),
        const SizedBox(width: 11),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    required this.onBack,
    this.trailing,
    super.key,
  });

  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
            icon: const Icon(Icons.arrow_back_rounded, size: 34),
            tooltip: '返回',
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
            ),
          ),
          SizedBox(
            width: 120,
            child: Align(
              alignment: Alignment.centerRight,
              child: trailing ?? const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class MainNavigation extends StatelessWidget {
  const MainNavigation({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 11, 8, 9),
      decoration: const BoxDecoration(
        color: kPaperWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          NavItem(
            icon: Icons.home_rounded,
            label: '首页',
            selected: selectedIndex == 0,
            onTap: () => onSelected(0),
          ),
          NavItem(
            icon: Icons.add_rounded,
            label: '记一口',
            selected: selectedIndex == 1,
            darkIcon: true,
            onTap: () => onSelected(1),
          ),
          NavItem(
            icon: Icons.public_rounded,
            label: '吃饭宇宙',
            selected: selectedIndex == 2,
            onTap: () => onSelected(2),
          ),
          NavItem(
            icon: Icons.bar_chart_rounded,
            label: '数据',
            selected: selectedIndex == 3,
            onTap: () => onSelected(3),
          ),
        ],
      ),
    );
  }
}

class NavItem extends StatelessWidget {
  const NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.darkIcon = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool darkIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 38,
              alignment: Alignment.center,
              decoration: selected
                  ? BoxDecoration(
                      color: darkIcon ? kInk : kLime,
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child: Icon(
                icon,
                size: darkIcon ? 32 : 29,
                color: darkIcon && selected ? Colors.white : kInk,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class SpeechLogo extends StatelessWidget {
  const SpeechLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(49, 47), painter: SpeechLogoPainter());
  }
}

class SpeechLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = kInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(7, 35)
      ..cubicTo(1, 25, 4, 12, 13, 7)
      ..cubicTo(23, 1, 38, 4, 42, 13)
      ..cubicTo(47, 24, 39, 38, 26, 41)
      ..cubicTo(18, 43, 11, 41, 7, 35)
      ..lineTo(3, 45)
      ..lineTo(14, 40);
    canvas.drawPath(path, stroke);
    final dot = Paint()..color = kInk;
    canvas.drawCircle(const Offset(17, 25), 2.2, dot);
    canvas.drawCircle(const Offset(25, 25), 2.2, dot);
    canvas.drawArc(
      const Rect.fromLTWH(30, 19, 7, 10),
      0,
      math.pi,
      false,
      stroke,
    );
    final accent = Paint()
      ..color = kLime
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(3, 48), const Offset(1, 46), accent);
    canvas.drawLine(const Offset(9, 49), const Offset(10, 45), accent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DraftSavedPill extends StatelessWidget {
  const DraftSavedPill({super.key});

  @override
  Widget build(BuildContext context) {
    return const TapeMarker(
      text: '▣  草稿已保存',
      color: kPaperWhite,
      textColor: kMuted,
    );
  }
}

class TapeMarker extends StatelessWidget {
  const TapeMarker({
    required this.text,
    required this.color,
    this.textColor = kInk,
    super.key,
  });

  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.012,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: color == kPaperWhite ? kSoftLine : color,
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 4,
              offset: Offset(2, 3),
            ),
          ],
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class StepPaper extends StatelessWidget {
  const StepPaper({required this.current, required this.total, super.key});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.018,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          color: kPaperWhite,
          boxShadow: [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 7,
              offset: Offset(2, 4),
            ),
          ],
        ),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(
              color: kInk,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
            children: [
              TextSpan(
                text: current.toString().padLeft(2, '0'),
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
              TextSpan(text: ' / ${total.toString().padLeft(2, '0')}'),
            ],
          ),
        ),
      ),
    );
  }
}

class UnderlinedCaption extends StatelessWidget {
  const UnderlinedCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: const TextStyle(
            color: kMuted,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 145,
          height: 5,
          child: CustomPaint(painter: UnderlinePainter(color: kLime)),
        ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Text(
          text,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        Positioned(
          left: -2,
          right: -2,
          bottom: -5,
          child: SizedBox(
            height: 7,
            child: CustomPaint(painter: UnderlinePainter(color: kLime)),
          ),
        ),
      ],
    );
  }
}

class UnderlinePainter extends CustomPainter {
  const UnderlinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(1, size.height * .55)
      ..quadraticBezierTo(
        size.width * .35,
        size.height * .1,
        size.width * .68,
        size.height * .5,
      )
      ..quadraticBezierTo(
        size.width * .84,
        size.height * .72,
        size.width,
        size.height * .35,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant UnderlinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class LocalImage extends StatelessWidget {
  const LocalImage({
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: const ColoredBox(color: kSoftLine),
      );
    }
    if (path.startsWith('assets/')) {
      return Image.asset(path, width: width, height: height, fit: fit);
    }
    return Image.file(
      File(path),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, error, stackTrace) =>
          const ColoredBox(color: kSoftLine),
    );
  }
}

class HeroFoodCard extends StatelessWidget {
  const HeroFoodCard({required this.record, super.key});

  final MealRecord record;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.012,
      child: Container(
        height: 310,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 14,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LocalImage(path: record.photo, fit: BoxFit.cover),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: MarkerLabel(
                text: record.verdict.label,
                color: record.verdict.color,
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 11,
                      ),
                      color: const Color(0xF6FFFDF8),
                      child: Text(
                        record.note.isNotEmpty
                            ? record.note
                            : '${record.restaurant} · ${record.displayDishes}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: kPaperWhite,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      _formatDate(record.eatenAt),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MarkerLabel extends StatelessWidget {
  const MarkerLabel({required this.text, required this.color, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textColor = color == kPaperWhite ? kInk : kInk;
    return Transform.rotate(
      angle: -0.015,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: kPaperWhite, width: 4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30000000),
              blurRadius: 4,
              offset: Offset(2, 3),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class VerdictTile extends StatelessWidget {
  const VerdictTile({required this.verdict, required this.onTap, super.key});

  final Verdict verdict;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 102,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: verdict.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: kInk,
            width: verdict == Verdict.neutral ? 1.5 : 0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(verdict.icon, color: kInk, size: 27),
            Text(
              verdict.phrase,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class MiniMealCard extends StatelessWidget {
  const MiniMealCard({required this.record, super.key});

  final MealRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 208,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: kPaperWhite,
        border: Border.all(color: kSoftLine),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LocalImage(
              path: record.photo,
              width: 78,
              height: 78,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.time ?? _formatDate(record.eatenAt),
                  style: const TextStyle(fontSize: 12, color: kMuted),
                ),
                const SizedBox(height: 9),
                Icon(
                  record.verdict.icon,
                  color: record.verdict == Verdict.keep ? kOrange : kPink,
                  size: 27,
                ),
                const SizedBox(height: 4),
                Text(
                  record.displayDishes,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VerdictChoiceCard extends StatelessWidget {
  const VerdictChoiceCard({
    required this.verdict,
    required this.caption,
    required this.rotation,
    required this.onTap,
    super.key,
  });

  final Verdict verdict;
  final String caption;
  final double rotation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 154,
          width: double.infinity,
          decoration: BoxDecoration(
            color: verdict.color,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: verdict == Verdict.neutral ? kInk : kPaperWhite,
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 7,
                offset: Offset(2, 5),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 20,
                top: 18,
                child: Icon(verdict.icon, size: 36, color: kInk),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        caption,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        width: 150,
                        height: 7,
                        child: CustomPaint(
                          painter: UnderlinePainter(color: kInk),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OutlineAction extends StatelessWidget {
  const OutlineAction({
    required this.label,
    required this.onTap,
    this.icon,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 24),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: kInk,
          side: const BorderSide(color: kInk, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class FilledPrimaryButton extends StatelessWidget {
  const FilledPrimaryButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.color = kOrange,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 24),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: kInk,
          disabledBackgroundColor: kSoftLine,
          disabledForegroundColor: kMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class PinkOutlineButton extends StatelessWidget {
  const PinkOutlineButton({
    required this.label,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: kPink),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: kInk,
          side: const BorderSide(color: kPink, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class PaperActionLabel extends StatelessWidget {
  const PaperActionLabel({
    required this.icon,
    required this.label,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: kPaperWhite,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x28000000),
              blurRadius: 7,
              offset: Offset(2, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 31),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );
  }
}

class DetailField extends StatelessWidget {
  const DetailField({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: kPaperWhite,
        border: Border.all(color: kInk, width: 1.2),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Icon(icon, size: 27),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          const Icon(Icons.edit_outlined, color: kMuted),
        ],
      ),
    );
  }
}

class ReasonChip extends StatelessWidget {
  const ReasonChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? color : kPaperWhite,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected && color != kPaperWhite ? color : kInk,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 19,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class FilterPill extends StatelessWidget {
  const FilterPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
        decoration: BoxDecoration(
          color: selected && label != '全部' && label != '本月' ? color : kPaper,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : kSoftLine, width: 1.5),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class PaperPanel extends StatelessWidget {
  const PaperPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: kPaperWhite,
        border: Border.all(color: kSoftLine, width: 1.2),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 4,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class TimelineRecordCard extends StatelessWidget {
  const TimelineRecordCard({
    required this.record,
    required this.onTap,
    super.key,
  });

  final MealRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = record.verdict == Verdict.skip ? kPink : kOrange;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 25,
          child: Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: kLime,
                  shape: BoxShape.circle,
                  border: Border.all(color: kInk, width: 2),
                ),
              ),
              Container(width: 2, height: 194, color: kInk),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: kPaperWhite,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x16000000),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: LocalImage(
                          path: record.photo,
                          width: 116,
                          height: 142,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -2,
                        left: -4,
                        child: Container(width: 50, height: 20, color: accent),
                      ),
                    ],
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.time ?? _formatDate(record.eatenAt),
                          style: const TextStyle(fontSize: 15, color: kMuted),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${record.restaurant} · ${record.displayDishes}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            MarkerLabel(
                              text: record.verdict.label,
                              color: record.verdict.color,
                            ),
                            const SizedBox(width: 9),
                            Flexible(
                              child: Text(
                                record.reasons.isEmpty
                                    ? '未写理由'
                                    : record.reasons.join('、'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class EmptyPaper extends StatelessWidget {
  const EmptyPaper({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return PaperPanel(
      child: Center(
        child: Text(text, style: const TextStyle(color: kMuted, fontSize: 16)),
      ),
    );
  }
}

class NoteStrip extends StatelessWidget {
  const NoteStrip({
    required this.icon,
    required this.text,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: kPaperWhite,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class LockStamp extends StatelessWidget {
  const LockStamp({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: const BoxDecoration(
        color: Color(0xFFF0E5D5),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.lock_rounded, size: 46),
    );
  }
}

class StatLine extends StatelessWidget {
  const StatLine({
    required this.number,
    required this.label,
    required this.color,
    super.key,
  });

  final String number;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          color: const Color(0xFFF2E8D9),
          child: Text(
            number,
            style: TextStyle(
              color: color == kPaperWhite ? kInk : color,
              fontSize: 29,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          label,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        Icon(
          Icons.arrow_forward_rounded,
          color: color == kPaperWhite ? kMuted : color,
        ),
      ],
    );
  }
}

class BackupIllustration extends StatelessWidget {
  const BackupIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 122,
      height: 122,
      decoration: BoxDecoration(
        color: kPaperWhite,
        border: Border.all(color: kSoftLine),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.archive_outlined, size: 75),
          Positioned(
            bottom: 13,
            child: Icon(Icons.arrow_upward_rounded, size: 43, color: kOrange),
          ),
        ],
      ),
    );
  }
}

class BackupFileIllustration extends StatelessWidget {
  const BackupFileIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 84,
      decoration: BoxDecoration(
        color: kPaperWhite,
        border: Border.all(color: kInk, width: 2),
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(Icons.archive_outlined, size: 43),
    );
  }
}

class ImportStatRow extends StatelessWidget {
  const ImportStatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.suffix,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final String suffix;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return PaperPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 52,
            alignment: Alignment.center,
            color: color,
            child: Icon(icon, size: 30),
          ),
          const SizedBox(width: 15),
          Text(
            label,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w900,
              color: color == kPaperWhite ? kInk : color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            suffix,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class SimpleNoticeDialog extends StatelessWidget {
  const SimpleNoticeDialog({
    required this.title,
    required this.message,
    super.key,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kPaperWhite,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      content: Text(message),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: kOrange,
            foregroundColor: kInk,
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

class RandomPickCard extends StatelessWidget {
  const RandomPickCard({required this.record, super.key});

  final MealRecord record;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.015,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: kPaperWhite,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x25000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: LocalImage(
                    path: record.photo,
                    height: 245,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const Positioned(
                  top: 12,
                  left: 12,
                  child: MarkerLabel(text: '⚡ 今晚就它了', color: kOrange),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: kOrange),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    record.restaurant,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                record.displayDishes,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Center(
              child: UnderlinedCaption(
                record.reasons.isEmpty
                    ? '上次记录：${record.verdict.label}'
                    : '上次你说：${record.reasons.join('、')}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportCard extends StatelessWidget {
  const ReportCard({required this.record, super.key});

  final MealRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      decoration: BoxDecoration(
        color: kPaperWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x25000000),
            blurRadius: 12,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkerLabel(text: record.verdict.label, color: record.verdict.color),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: LocalImage(
              path: record.photo,
              height: 270,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 14),
          MarkerLabel(text: record.restaurant, color: kOrange),
          const SizedBox(height: 10),
          Center(
            child: Text(
              record.displayDishes,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            color: const Color(0xFFF5EEE3),
            child: Text(
              record.note.isEmpty ? '这次没有写短评。' : record.note,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDate(record.eatenAt),
                style: const TextStyle(color: kMuted, fontSize: 14),
              ),
              const Text(
                '仅代表我的这次体验',
                style: TextStyle(color: kMuted, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RestaurantColumn extends StatelessWidget {
  const RestaurantColumn({
    required this.title,
    required this.color,
    required this.icon,
    required this.items,
    super.key,
  });

  final String title;
  final Color color;
  final IconData icon;
  final List<RestaurantDish> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kPaperWhite,
        border: Border.all(color: kInk, width: 1.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MarkerLabel(text: title, color: color),
              const Spacer(),
              Icon(icon, size: 29),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in items) ...[
            RestaurantDishCard(dish: item, color: color),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class RestaurantDish {
  const RestaurantDish({
    required this.photo,
    required this.name,
    required this.tag,
  });

  final String photo;
  final String name;
  final String tag;
}

class RestaurantDishCard extends StatelessWidget {
  const RestaurantDishCard({
    required this.dish,
    required this.color,
    super.key,
  });

  final RestaurantDish dish;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: kPaper,
        border: Border.all(color: kSoftLine),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LocalImage(
              path: dish.photo,
              height: 95,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            dish.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          Text(
            dish.tag,
            style: TextStyle(
              color: color == kOrange ? kMuted : color,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
