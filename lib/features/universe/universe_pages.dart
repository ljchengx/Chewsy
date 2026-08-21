part of '../../main.dart';

class UniversePage extends StatefulWidget {
  const UniversePage({
    required this.records,
    required this.recordStore,
    required this.refreshToken,
    required this.onOpenRecord,
    required this.onOpenRestaurant,
    required this.onOpenRandom,
    required this.onOpenReport,
    super.key,
  });

  final List<MealRecord> records;
  final RecordStore recordStore;
  final int refreshToken;
  final ValueChanged<MealRecord> onOpenRecord;
  final ValueChanged<String> onOpenRestaurant;
  final VoidCallback onOpenRandom;
  final VoidCallback onOpenReport;

  @override
  State<UniversePage> createState() => _UniversePageState();
}

class _UniversePageState extends State<UniversePage> {
  String _filter = '全部';
  String _query = '';
  List<MealRecord> _records = const [];
  List<RestaurantSearchResult> _restaurants = const [];
  Timer? _debounce;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _records = widget.records;
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant UniversePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _records = widget.records;
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == '本月'
        ? _records.where(_isThisMonth).toList()
        : _records;
    final visibleRestaurantIds = filtered
        .map((record) => record.restaurantId)
        .whereType<String>()
        .toSet();
    final visibleRestaurants = _restaurants
        .where((restaurant) => visibleRestaurantIds.contains(restaurant.id))
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandHeader(
            title: '我的吃饭宇宙',
            trailing: TapeMarker(text: '随手记录', color: kPaperWhite),
          ),
          const SizedBox(height: 22),
          TextField(
            onChanged: _onQueryChanged,
            decoration: const InputDecoration(
              hintText: '搜我的店、菜和理由',
              prefixIcon: Icon(Icons.search_rounded, size: 32),
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in const ['全部', '种草', '观望', '踩雷', '本月'])
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: FilterPill(
                      label: filter,
                      selected: _filter == filter,
                      color: filter == '踩雷' ? kPink : kOrange,
                      onTap: () {
                        setState(() => _filter = filter);
                        unawaited(_reload());
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SectionTitle('吃饭回放'),
              const Spacer(),
              GestureDetector(
                onTap: widget.onOpenRandom,
                child: const Text(
                  '今晚吃啥？  ›',
                  style: TextStyle(color: kPurple, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            const EmptyPaper(text: '还没有找到这一口，换个词试试。')
          else
            for (final record in filtered)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TimelineRecordCard(
                  record: record,
                  onTap: () => widget.onOpenRecord(record),
                ),
              ),
          if (visibleRestaurants.isNotEmpty) ...[
            const SizedBox(height: 4),
            const SectionTitle('相关店铺'),
            const SizedBox(height: 12),
            for (final restaurant in visibleRestaurants.take(3)) ...[
              RestaurantSearchCard(
                result: restaurant,
                onTap: () => widget.onOpenRestaurant(restaurant.id),
              ),
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 6),
          FilledPrimaryButton(
            label: '生成本月战报',
            icon: Icons.auto_awesome_rounded,
            onTap: widget.onOpenReport,
          ),
        ],
      ),
    );
  }

  bool _isThisMonth(MealRecord record) {
    final date = record.eatenAt.toLocal();
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  void _onQueryChanged(String value) {
    _query = value;
    _requestId++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    final request = ++_requestId;
    final verdict = switch (_filter) {
      '种草' => Verdict.keep,
      '踩雷' => Verdict.skip,
      '观望' => Verdict.neutral,
      _ => null,
    };
    final results = await Future.wait([
      widget.recordStore.loadRecords(
        query: RecordQuery(search: _query, verdict: verdict, limit: 1000),
      ),
      widget.recordStore.searchRestaurants(_query, limit: 8),
    ]);
    if (!mounted || request != _requestId) return;
    setState(() {
      _records = results[0] as List<MealRecord>;
      _restaurants = results[1] as List<RestaurantSearchResult>;
    });
  }
}
