part of '../../main.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.records,
    required this.recordStore,
    required this.onRecord,
    required this.onOpenReport,
    required this.onOpenUniverse,
    required this.onOpenRestaurant,
    super.key,
  });

  final List<MealRecord> records;
  final RecordStore recordStore;
  final ValueChanged<Verdict> onRecord;
  final VoidCallback onOpenReport;
  final VoidCallback onOpenUniverse;
  final ValueChanged<String> onOpenRestaurant;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  List<RestaurantSearchResult> _results = const [];
  int _searchRequest = 0;
  bool _searching = false;
  String? _searchError;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSearch = _searchController.text.trim().isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandHeader(),
          const SizedBox(height: 8),
          const TapeMarker(
            text: '▣  我的记录',
            color: kPaperWhite,
            textColor: kMuted,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: _scheduleSearch,
            decoration: InputDecoration(
              hintText: '搜店名或菜名，找上次的坑',
              prefixIcon: const Icon(Icons.search_rounded, size: 30),
              suffixIcon: hasSearch
                  ? IconButton(
                      tooltip: '清除搜索',
                      onPressed: () {
                        _searchController.clear();
                        _scheduleSearch('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
            ),
          ),
          if (hasSearch) ...[
            const SizedBox(height: 18),
            const SectionTitle('找到这些店'),
            const SizedBox(height: 12),
            if (_searching)
              const Center(child: CircularProgressIndicator(color: kOrange))
            else if (_searchError != null)
              EmptyPaper(text: _searchError!)
            else if (_results.isEmpty)
              const EmptyPaper(text: '还没有记过这家店，换个词试试。')
            else
              for (final result in _results) ...[
                RestaurantSearchCard(
                  result: result,
                  onTap: () => widget.onOpenRestaurant(result.id),
                ),
                const SizedBox(height: 12),
              ],
          ] else ...[
            const SizedBox(height: 18),
            if (widget.records.isEmpty)
              const EmptyPaper(text: '还没有吃饭记录，先记下第一家店。')
            else ...[
              GestureDetector(
                onTap: widget.onOpenReport,
                child: HeroFoodCard(record: widget.records.first),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                Expanded(
                  child: VerdictTile(
                    verdict: Verdict.keep,
                    onTap: () => widget.onRecord(Verdict.keep),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: VerdictTile(
                    verdict: Verdict.skip,
                    onTap: () => widget.onRecord(Verdict.skip),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: VerdictTile(
                    verdict: Verdict.neutral,
                    onTap: () => widget.onRecord(Verdict.neutral),
                  ),
                ),
              ],
            ),
            if (widget.records.isNotEmpty) ...[
              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const SectionTitle('吃饭回放'),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onOpenUniverse,
                    child: const Text(
                      '回忆一下  ›',
                      style: TextStyle(
                        color: kPurple,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 142,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: math.min(widget.records.length, 4),
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (_, index) =>
                      MiniMealCard(record: widget.records[index]),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _scheduleSearch(String value) {
    final request = ++_searchRequest;
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _results = const [];
          _searchError = null;
          _searching = false;
        });
      }
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 240), () {
      unawaited(_search(query, request));
    });
  }

  Future<void> _search(String query, int request) async {
    try {
      final results = await widget.recordStore.searchRestaurants(query);
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _results = results;
        _searching = false;
        _searchError = null;
      });
    } on Object catch (_) {
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _results = const [];
        _searching = false;
        _searchError = '搜索出了点问题，请再试一次。';
      });
    }
  }
}

class RestaurantSearchCard extends StatelessWidget {
  const RestaurantSearchCard({
    required this.result,
    required this.onTap,
    super.key,
  });

  final RestaurantSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: PaperPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront_outlined, size: 27),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    result.name,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${result.visitCount} 次',
                  style: const TextStyle(
                    color: kMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: kMuted),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (result.latestVerdict != null)
                  MarkerLabel(
                    text: result.latestVerdict!.label,
                    color: result.latestVerdict!.color,
                  ),
                const SizedBox(width: 9),
                Text(
                  _formatDate(result.latestEatenAt),
                  style: const TextStyle(color: kMuted, fontSize: 14),
                ),
              ],
            ),
            if (result.recentDishes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                result.recentDishes.join('、'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
            if (result.matchedDishes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '命中菜名：${result.matchedDishes.join('、')}',
                style: const TextStyle(
                  color: kPurple,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RecordVerdictPage extends StatelessWidget {
  const RecordVerdictPage({
    required this.onBack,
    required this.onChoose,
    super.key,
  });

  final VoidCallback onBack;
  final ValueChanged<Verdict> onChoose;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: '好吃不',
            onBack: onBack,
            trailing: const DraftSavedPill(),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '这家店，怎么判？',
                      style: TextStyle(
                        fontSize: 35,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    SizedBox(height: 12),
                    UnderlinedCaption('先选判词，再写这家店的体验。'),
                  ],
                ),
              ),
              const StepPaper(current: 1, total: 2),
            ],
          ),
          const SizedBox(height: 25),
          VerdictChoiceCard(
            verdict: Verdict.keep,
            caption: '种草',
            rotation: -0.025,
            onTap: () => onChoose(Verdict.keep),
          ),
          Transform.translate(
            offset: const Offset(0, -12),
            child: VerdictChoiceCard(
              verdict: Verdict.neutral,
              caption: '观望',
              rotation: 0.02,
              onTap: () => onChoose(Verdict.neutral),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -24),
            child: VerdictChoiceCard(
              verdict: Verdict.skip,
              caption: '踩雷',
              rotation: -0.018,
              onTap: () => onChoose(Verdict.skip),
            ),
          ),
          const SizedBox(height: 2),
          const Center(
            child: Text(
              '先定下这次体验，再慢慢补细节',
              style: TextStyle(
                color: kOrange,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RecordDetailsPage extends StatelessWidget {
  const RecordDetailsPage({
    required this.verdict,
    required this.initialDraft,
    required this.onBack,
    required this.onDraftChanged,
    required this.onPublish,
    this.suggestRestaurants,
    this.stagePhoto,
    this.title = '好吃不',
    this.publishLabel = '发布这次记录',
    this.showDraftPill = true,
    this.closeAfterPublish = false,
    this.allowVerdictChange = false,
    super.key,
  });

  final Verdict verdict;
  final RecordDraft? initialDraft;
  final VoidCallback onBack;
  final ValueChanged<RecordDraft> onDraftChanged;
  final FutureOr<void> Function(RecordDraft) onPublish;
  final Future<List<String>> Function(String query)? suggestRestaurants;
  final Future<String> Function(String sourcePath)? stagePhoto;
  final String title;
  final String publishLabel;
  final bool showDraftPill;
  final bool closeAfterPublish;
  final bool allowVerdictChange;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPaper,
      body: SafeArea(
        child: _DetailsForm(
          verdict: verdict,
          initialDraft: initialDraft,
          onBack: onBack,
          onDraftChanged: onDraftChanged,
          onPublish: onPublish,
          suggestRestaurants: suggestRestaurants,
          stagePhoto: stagePhoto,
          title: title,
          publishLabel: publishLabel,
          showDraftPill: showDraftPill,
          closeAfterPublish: closeAfterPublish,
          allowVerdictChange: allowVerdictChange,
        ),
      ),
    );
  }
}

class _DetailsForm extends StatefulWidget {
  const _DetailsForm({
    required this.verdict,
    required this.initialDraft,
    required this.onBack,
    required this.onDraftChanged,
    required this.onPublish,
    required this.suggestRestaurants,
    this.stagePhoto,
    required this.title,
    required this.publishLabel,
    required this.showDraftPill,
    required this.closeAfterPublish,
    this.allowVerdictChange = false,
  });

  final Verdict verdict;
  final RecordDraft? initialDraft;
  final VoidCallback onBack;
  final ValueChanged<RecordDraft> onDraftChanged;
  final FutureOr<void> Function(RecordDraft) onPublish;
  final Future<List<String>> Function(String query)? suggestRestaurants;
  final Future<String> Function(String sourcePath)? stagePhoto;
  final String title;
  final String publishLabel;
  final bool showDraftPill;
  final bool closeAfterPublish;
  final bool allowVerdictChange;

  @override
  State<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends State<_DetailsForm> {
  late final TextEditingController _restaurantController;
  late final TextEditingController _noteController;
  late final TextEditingController _customReasonController;
  late final List<TextEditingController> _dishControllers;
  late Set<String> _reasons;
  late String? _photoPath;
  late DateTime _eatenAt;
  late Verdict _verdict;
  List<String> _suggestions = const [];
  int _suggestionRequest = 0;
  bool _publishing = false;

  List<String> get _presetReasons {
    switch (_verdict) {
      case Verdict.keep:
        return const ['味道好', '锅气足', '分量足', '性价比高', '环境舒服'];
      case Verdict.neutral:
        return const ['一般', '没记住', '体验不稳定', '下次再看'];
      case Verdict.skip:
        return const ['太咸', '太油', '不新鲜', '分量少', '太贵', '服务差'];
    }
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _restaurantController = TextEditingController(
      text: draft?.restaurant ?? '',
    );
    _noteController = TextEditingController(text: draft?.note ?? '');
    _customReasonController = TextEditingController();
    final dishes = draft?.dishes ?? const <String>[];
    _dishControllers = [
      for (final dish in dishes.isEmpty ? const [''] : dishes)
        TextEditingController(text: dish),
    ];
    _reasons = {...(draft?.reasons ?? const <String>{})};
    _photoPath = draft?.photoPath;
    _eatenAt = draft?.eatenAt ?? DateTime.now();
    _verdict = draft?.verdict ?? widget.verdict;
    unawaited(_restoreLostPhoto());
  }

  @override
  void dispose() {
    _restaurantController.dispose();
    _noteController.dispose();
    _customReasonController.dispose();
    for (final controller in _dishControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final verdictLabel = _verdict.label;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: widget.title,
            onBack: widget.onBack,
            trailing: widget.showDraftPill ? const DraftSavedPill() : null,
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.title == '好吃不' ? '这家店，怎么判？' : '修改这次到店记录',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
              ),
              const StepPaper(current: 2, total: 2),
            ],
          ),
          const SizedBox(height: 12),
          MarkerLabel(text: verdictLabel, color: _verdict.color),
          if (widget.allowVerdictChange) ...[
            const SizedBox(height: 14),
            SegmentedButton<Verdict>(
              segments: const [
                ButtonSegment(value: Verdict.keep, label: Text('种草')),
                ButtonSegment(value: Verdict.neutral, label: Text('观望')),
                ButtonSegment(value: Verdict.skip, label: Text('踩雷')),
              ],
              selected: {_verdict},
              onSelectionChanged: (selected) {
                if (selected.isEmpty) return;
                setState(() => _verdict = selected.first);
                _emitDraft();
              },
            ),
          ],
          const SizedBox(height: 18),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.white, width: 8),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 14,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: _buildDraftImage(),
                ),
              ),
              Positioned(
                right: 8,
                bottom: -13,
                child: PaperActionLabel(
                  icon: Icons.camera_alt_outlined,
                  label: _photoPath == null ? '建议拍一张' : '更换图片',
                  onTap: _pickPhoto,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _FormRow(
            icon: Icons.storefront_outlined,
            child: TextField(
              controller: _restaurantController,
              onChanged: (value) {
                _emitDraft();
                unawaited(_loadSuggestions(value));
              },
              decoration: const InputDecoration(hintText: '店名或家庭自制 *'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            PaperPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final suggestion in _suggestions)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.history_rounded, size: 20),
                      title: Text(suggestion),
                      onTap: () {
                        _restaurantController.text = suggestion;
                        _restaurantController.selection =
                            TextSelection.collapsed(offset: suggestion.length);
                        setState(() => _suggestions = const []);
                        _emitDraft();
                      },
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Icon(Icons.room_service_outlined, size: 27),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < _dishControllers.length;
                      index++
                    )
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _dishControllers[index],
                                onChanged: (_) => _emitDraft(),
                                decoration: InputDecoration(
                                  hintText: index == 0 ? '菜名（可以不填）' : '再加一道菜',
                                ),
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (_dishControllers.length > 1)
                              IconButton(
                                tooltip: '删除这道菜',
                                onPressed: () => _removeDish(index),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _addDish,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('添加一道菜'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '为什么$verdictLabel？',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final reason in _presetReasons)
                ReasonChip(
                  label: reason,
                  selected: _reasons.contains(reason),
                  color: _reasonColor(reason),
                  onTap: () {
                    setState(() {
                      if (_reasons.contains(reason)) {
                        _reasons.remove(reason);
                      } else {
                        _reasons.add(reason);
                      }
                    });
                    _emitDraft();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customReasonController,
                  decoration: const InputDecoration(hintText: '添加自定义理由'),
                  onSubmitted: (_) => _addCustomReason(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: '添加理由',
                onPressed: _addCustomReason,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          if (_reasons
              .where((reason) => !_presetReasons.contains(reason))
              .isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final reason in _reasons.where(
                  (reason) => !_presetReasons.contains(reason),
                ))
                  InputChip(
                    label: Text(reason),
                    onDeleted: () {
                      setState(() => _reasons.remove(reason));
                      _emitDraft();
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          TextField(
            controller: _noteController,
            onChanged: (_) => _emitDraft(),
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '写一句这次用餐的短评（可以不填）',
              prefixIcon: Icon(Icons.edit_note_rounded),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _pickDateTime,
            borderRadius: BorderRadius.circular(16),
            child: PaperPanel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  const Icon(Icons.schedule_outlined, size: 25),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '用餐时间  ${_formatDate(_eatenAt)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const Icon(Icons.edit_outlined, size: 19, color: kMuted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledPrimaryButton(
            label: _publishing ? '保存中…' : widget.publishLabel,
            icon: Icons.check_rounded,
            onTap: _publishing ? null : _publish,
          ),
        ],
      ),
    );
  }

  Color _reasonColor(String reason) {
    final index = _presetReasons.indexOf(reason);
    if (index % 3 == 0) return kOrange;
    if (index % 3 == 1) return kPink;
    return kPaperWhite;
  }

  RecordDraft _currentDraft() {
    return RecordDraft(
      verdict: _verdict,
      eatenAt: _eatenAt,
      restaurant: _restaurantController.text,
      dishes: _dishControllers.map((controller) => controller.text).toList(),
      note: _noteController.text,
      reasons: {..._reasons},
      photoPath: _photoPath,
    );
  }

  void _emitDraft() => widget.onDraftChanged(_currentDraft());

  Future<void> _publish() async {
    final draft = _currentDraft();
    if (draft.restaurant.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先填店名，这样下次才能找到这家店。')));
      return;
    }
    setState(() => _publishing = true);
    try {
      await widget.onPublish(draft);
      if (widget.closeAfterPublish && mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _publishing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    }
  }

  void _addDish() {
    setState(() => _dishControllers.add(TextEditingController()));
    _emitDraft();
  }

  void _removeDish(int index) {
    final controller = _dishControllers.removeAt(index);
    controller.dispose();
    if (_dishControllers.isEmpty) {
      _dishControllers.add(TextEditingController());
    }
    setState(() {});
    _emitDraft();
  }

  void _addCustomReason() {
    final reason = _customReasonController.text.trim();
    if (reason.isEmpty) return;
    setState(() {
      _reasons.add(reason);
      _customReasonController.clear();
    });
    _emitDraft();
  }

  Future<void> _loadSuggestions(String value) async {
    final callback = widget.suggestRestaurants;
    if (callback == null || value.trim().isEmpty) {
      if (mounted) setState(() => _suggestions = const []);
      return;
    }
    final request = ++_suggestionRequest;
    final suggestions = await callback(value);
    if (!mounted || request != _suggestionRequest) return;
    setState(() => _suggestions = suggestions);
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _eatenAt.isAfter(now) ? now : _eatenAt,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_eatenAt),
    );
    if (pickedTime == null || !mounted) return;
    var value = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (value.isAfter(now)) value = now;
    setState(() => _eatenAt = value);
    _emitDraft();
  }

  Future<void> _pickPhoto() async {
    try {
      final source = await showModalBottomSheet<Object?>(
        context: context,
        backgroundColor: kPaperWhite,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('拍一张'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              if (_photoPath != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('移除图片'),
                  onTap: () => Navigator.pop(context, 'remove'),
                ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (source == 'remove') {
        setState(() => _photoPath = null);
        _emitDraft();
        return;
      }
      if (source is! ImageSource) {
        return;
      }
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null || !mounted) return;
      final stagedPath = widget.stagePhoto == null
          ? picked.path
          : await widget.stagePhoto!(picked.path);
      if (!mounted) return;
      setState(() => _photoPath = stagedPath);
      _emitDraft();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开图片：$error')));
    }
  }

  Future<void> _restoreLostPhoto() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final response = await ImagePicker().retrieveLostData();
      if (response.exception != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('图片恢复失败：${response.exception}')));
        return;
      }
      final files = response.files;
      if (!mounted || files == null || files.isEmpty || _photoPath != null) {
        return;
      }
      final path = widget.stagePhoto == null
          ? files.first.path
          : await widget.stagePhoto!(files.first.path);
      if (!mounted) return;
      setState(() => _photoPath = path);
      _emitDraft();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('图片恢复失败：$error')));
    }
  }

  Widget _buildDraftImage() {
    final path = _photoPath;
    if (path == null || path.isEmpty) {
      return const ColoredBox(
        color: kSoftLine,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_camera_outlined, size: 52, color: kMuted),
              SizedBox(height: 8),
              Text('建议拍一张，也可以跳过', style: TextStyle(color: kMuted)),
            ],
          ),
        ),
      );
    }
    if (path.startsWith('assets/')) return Image.asset(path, fit: BoxFit.cover);
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, error, stackTrace) => const ColoredBox(
        color: kSoftLine,
        child: Center(child: Icon(Icons.broken_image_outlined, color: kMuted)),
      ),
    );
  }
}

String _formatDate(DateTime? value) {
  if (value == null) return '未记录时间';
  final local = value.toLocal();
  final now = DateTime.now();
  final date =
      '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return local.year == now.year &&
          local.month == now.month &&
          local.day == now.day
      ? '今天 $time'
      : '$date $time';
}
