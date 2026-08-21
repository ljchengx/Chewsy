part of '../../main.dart';

class DataCenterPage extends StatefulWidget {
  const DataCenterPage({
    required this.recordStore,
    required this.refreshToken,
    required this.onBackup,
    required this.onImport,
    super.key,
  });

  final RecordStore recordStore;
  final int refreshToken;
  final VoidCallback onBackup;
  final VoidCallback onImport;

  @override
  State<DataCenterPage> createState() => _DataCenterPageState();
}

class _DataCenterPageState extends State<DataCenterPage> {
  late Future<RecordCounts> _countsFuture;

  @override
  void initState() {
    super.initState();
    _countsFuture = widget.recordStore.loadCounts();
  }

  @override
  void didUpdateWidget(covariant DataCenterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _countsFuture = widget.recordStore.loadCounts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandHeader(
            title: '数据中心',
            trailing: TapeMarker(text: '随手管理', color: kPaperWhite),
          ),
          const SizedBox(height: 22),
          PaperPanel(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(Icons.collections_bookmark_outlined, size: 58),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '记录和图片都在这里',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '想换设备时，导出一份备份',
                        style: TextStyle(color: kMuted, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<RecordCounts>(
            future: _countsFuture,
            builder: (context, snapshot) {
              final counts = snapshot.data;
              return PaperPanel(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    StatLine(
                      number: counts?.records.toString() ?? '…',
                      label: '条战报',
                      color: kOrange,
                    ),
                    const Divider(height: 26, color: kSoftLine),
                    StatLine(
                      number: counts?.images.toString() ?? '…',
                      label: '张图片',
                      color: kPink,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          FilledPrimaryButton(
            label: '导出备份',
            icon: Icons.file_upload_outlined,
            onTap: widget.onBackup,
          ),
          const SizedBox(height: 12),
          PinkOutlineButton(
            label: '导入备份',
            icon: Icons.file_download_outlined,
            onTap: widget.onImport,
          ),
          const SizedBox(height: 18),
          const NoteStrip(
            icon: Icons.photo_library_outlined,
            text: '备份会带上你的战报、图片和标签',
            color: kOrange,
          ),
        ],
      ),
    );
  }
}

class BackupCreatePage extends StatefulWidget {
  const BackupCreatePage({required this.backupService, super.key});

  final BackupService backupService;

  @override
  State<BackupCreatePage> createState() => _BackupCreatePageState();
}

class _BackupCreatePageState extends State<BackupCreatePage> {
  bool _busy = false;
  BackupProgress _progress = const BackupProgress(stage: '准备中', fraction: 0);

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(title: '导出备份', onBack: () => Navigator.pop(context)),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: const [
                  BackupIllustration(),
                  SizedBox(height: 12),
                  Text(
                    '把记录带走',
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '记录和图片会打包成一份文件',
                    style: TextStyle(color: kMuted, fontSize: 16),
                  ),
                ],
              ),
            ),
            const NoteStrip(
              icon: Icons.archive_outlined,
              text: '导出的文件可以用来换设备或留个备份',
              color: kOrange,
            ),
            const SizedBox(height: 20),
            if (_busy) ...[
              LinearProgressIndicator(
                value: _progress.fraction,
                color: kOrange,
                backgroundColor: Color(0x22FF6508),
              ),
              const SizedBox(height: 12),
              Center(child: Text(_progress.stage)),
              const SizedBox(height: 12),
            ],
            FilledPrimaryButton(
              label: _busy ? '导出中…' : '导出备份',
              icon: Icons.file_upload_outlined,
              onTap: _busy ? null : _startBackup,
            ),
            const SizedBox(height: 14),
            const Center(
              child: Text(
                '导出完成后交给系统保存',
                style: TextStyle(color: kMuted, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startBackup() async {
    setState(() {
      _busy = true;
      _progress = const BackupProgress(stage: '整理记录', fraction: 0);
    });
    BackupArtifact? artifact;
    try {
      artifact = await widget.backupService.create(const BackupRequest(), (
        progress,
      ) {
        if (mounted) setState(() => _progress = progress);
      });
      if (!mounted) return;
      setState(
        () => _progress = const BackupProgress(stage: '已完成', fraction: 1),
      );
      await Share.shareXFiles(
        [XFile(artifact.filePath)],
        subject: '好吃不备份',
        text: '好吃不备份文件',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) =>
            const SimpleNoticeDialog(title: '备份已导出', message: '文件已交给系统保存。'),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('备份失败：$error')));
    } finally {
      if (artifact != null) await widget.backupService.deleteArtifact(artifact);
      if (mounted) setState(() => _busy = false);
    }
  }
}

class ImportPreviewPage extends StatefulWidget {
  const ImportPreviewPage({
    required this.backupService,
    required this.onConfirmed,
    super.key,
  });

  final BackupService backupService;
  final Future<void> Function(ImportResult result) onConfirmed;

  @override
  State<ImportPreviewPage> createState() => _ImportPreviewPageState();
}

class _ImportPreviewPageState extends State<ImportPreviewPage> {
  BackupInspection? _inspection;
  ImportPlan? _plan;
  String? _filePath;
  String? _fileName;
  bool _busy = false;
  BackupProgress _progress = const BackupProgress(stage: '准备中', fraction: 0);

  @override
  Widget build(BuildContext context) {
    final inspection = _inspection;
    return DetailScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        child: inspection == null
            ? _buildPicker(context)
            : _buildPreview(context, inspection),
      ),
    );
  }

  Widget _buildPicker(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(title: '导入备份', onBack: () => Navigator.pop(context)),
        const SizedBox(height: 20),
        PaperPanel(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: const [
              BackupFileIllustration(),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '选择备份文件',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 10),
                    TapeMarker(text: '把记录带回来', color: kPaperWhite),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        OutlineAction(
          label: _fileName ?? '选择备份文件',
          icon: Icons.folder_open_rounded,
          onTap: _chooseFile,
        ),
        const SizedBox(height: 20),
        if (_busy) ...[
          LinearProgressIndicator(
            value: _progress.fraction,
            color: kOrange,
            backgroundColor: const Color(0x22FF6508),
          ),
          const SizedBox(height: 10),
          Center(child: Text(_progress.stage)),
          const SizedBox(height: 12),
        ],
        FilledPrimaryButton(
          label: _busy ? '检查中…' : '检查备份',
          icon: Icons.fact_check_outlined,
          onTap: _busy ? null : _inspect,
        ),
        const SizedBox(height: 14),
        const NoteStrip(
          icon: Icons.archive_outlined,
          text: '导入前会先统计新增和重复内容',
          color: kOrange,
        ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context, BackupInspection inspection) {
    final counts = inspection.counts;
    final plan = _plan!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(title: '导入备份', onBack: () => Navigator.pop(context)),
        const SizedBox(height: 20),
        PaperPanel(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: const [
              BackupFileIllustration(),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '备份已准备好',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 10),
                    TapeMarker(text: '导入前先看看', color: kPaperWhite),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ImportStatRow(
          icon: Icons.bolt_rounded,
          label: '新增',
          value: '${counts.added}',
          suffix: '条战报',
          color: kOrange,
        ),
        const SizedBox(height: 12),
        ImportStatRow(
          icon: Icons.sentiment_satisfied_alt_rounded,
          label: '已存在',
          value: '${counts.existing}',
          suffix: '条',
          color: kPaperWhite,
        ),
        const SizedBox(height: 12),
        ImportStatRow(
          icon: Icons.sync_rounded,
          label: '将更新',
          value: '${counts.updated}',
          suffix: '条',
          color: kLime,
        ),
        const SizedBox(height: 12),
        ImportStatRow(
          icon: Icons.close_rounded,
          label: '发现冲突',
          value: '${counts.conflicts}',
          suffix: '个冲突',
          color: kPink,
        ),
        if (counts.deleted > 0 || counts.skipped > 0) ...[
          const SizedBox(height: 12),
          ImportStatRow(
            icon: Icons.remove_done_rounded,
            label: '保留现有',
            value: '${counts.skipped + counts.deleted}',
            suffix: '条',
            color: kPaperWhite,
          ),
        ],
        const SizedBox(height: 20),
        NoteStrip(
          icon: inspection.alreadyImported
              ? Icons.check_circle_outline_rounded
              : Icons.info_outline_rounded,
          text: inspection.alreadyImported
              ? '这份备份已经导入过，不会产生重复记录'
              : plan.isReady
              ? '默认合并，不会覆盖现有记录'
              : '请先处理全部冲突，再确认导入',
          color: inspection.alreadyImported || plan.isReady ? kLime : kPink,
        ),
        const SizedBox(height: 20),
        OutlineAction(
          label: counts.conflicts == 0 ? '没有待处理冲突' : '查看冲突',
          icon: Icons.compare_arrows_rounded,
          onTap: counts.conflicts == 0 ? null : _showConflicts,
        ),
        const SizedBox(height: 12),
        if (_busy) ...[
          LinearProgressIndicator(
            value: _progress.fraction,
            color: kOrange,
            backgroundColor: const Color(0x22FF6508),
          ),
          const SizedBox(height: 10),
          Center(child: Text(_progress.stage)),
          const SizedBox(height: 12),
        ],
        FilledPrimaryButton(
          label: _busy ? '导入中…' : '确认导入',
          icon: Icons.file_download_done_rounded,
          onTap: _busy || !plan.isReady ? null : _commit,
        ),
        const SizedBox(height: 14),
        const Center(
          child: Text(
            '导入中断也不会破坏原有数据',
            style: TextStyle(color: kMuted, fontSize: 15),
          ),
        ),
      ],
    );
  }

  Future<void> _chooseFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: '好吃不备份', extensions: ['haochibu']),
      ],
    );
    if (file == null || !mounted) return;
    setState(() {
      _filePath = file.path;
      _fileName = file.name;
      _inspection = null;
      _plan = null;
    });
  }

  Future<void> _inspect() async {
    final path = _filePath;
    if (path == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择 .haochibu 文件')));
      return;
    }
    setState(() {
      _busy = true;
      _progress = const BackupProgress(stage: '检查文件', fraction: 0);
    });
    try {
      final inspection = await widget.backupService.inspect(
        ImportRequest(filePath: path),
        (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _inspection = inspection;
        _plan = ImportPlan(inspection: inspection);
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('备份检查失败：$error')));
    }
  }

  Future<void> _showConflicts() async {
    final inspection = _inspection;
    final plan = _plan;
    if (inspection == null || plan == null || inspection.conflicts.isEmpty) {
      return;
    }
    final resolutions = {...plan.resolutions};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: kPaperWhite,
              title: const Text(
                '处理记录冲突',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              content: SizedBox(
                width: 420,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final conflict in inspection.conflicts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${conflict.local.restaurant} · ${conflict.local.displayDishes}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '现有：${conflict.local.note.isEmpty ? '无短评' : conflict.local.note}',
                            ),
                            Text(
                              '文件：${conflict.remote.note.isEmpty ? '无短评' : conflict.remote.note}',
                            ),
                            DropdownButton<ConflictResolution>(
                              isExpanded: true,
                              value: resolutions[conflict.recordId],
                              hint: const Text('选择保留方式'),
                              items: const [
                                DropdownMenuItem(
                                  value: ConflictResolution.keepLocal,
                                  child: Text('保留现有'),
                                ),
                                DropdownMenuItem(
                                  value: ConflictResolution.useBackup,
                                  child: Text('保留备份'),
                                ),
                                DropdownMenuItem(
                                  value: ConflictResolution.duplicate,
                                  child: Text('复制为新记录'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(
                                  () => resolutions[conflict.recordId] = value,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: resolutions.length == inspection.conflicts.length
                      ? () {
                          setState(() {
                            _plan = ImportPlan(
                              inspection: inspection,
                              resolutions: resolutions,
                            );
                          });
                          Navigator.pop(dialogContext);
                        }
                      : null,
                  child: const Text('保存选择'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _commit() async {
    final plan = _plan;
    if (plan == null || !plan.isReady) return;
    setState(() {
      _busy = true;
      _progress = const BackupProgress(stage: '合并记录', fraction: 0);
    });
    try {
      final result = await widget.backupService.commit(plan, (progress) {
        if (mounted) setState(() => _progress = progress);
      });
      await widget.onConfirmed(result);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
    }
  }
}
