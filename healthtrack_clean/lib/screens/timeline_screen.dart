// lib/screens/timeline_screen.dart — Complete Health Timeline
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});
  @override State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  @override void initState() { super.initState(); _tabs = TabController(length: 3, vsync: this); }
  @override void dispose()   { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Health Timeline', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        bottom: TabBar(controller: _tabs,
          labelColor: AppColors.navy, unselectedLabelColor: isDark ? AppColors.textMutedDark : AppColors.textMuted,
          indicatorColor: AppColors.sage,
          tabs: const [Tab(text: '📋 Timeline'), Tab(text: '📅 Calendar'), Tab(text: '📊 Summary')]),
      ),
      body: TabBarView(controller: _tabs, children: const [
        _TimelineTab(), _CalendarTab(), _SummaryTab(),
      ]),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// TIMELINE TAB
// ════════════════════════════════════════════════════════════════
class _TimelineTab extends StatefulWidget {
  const _TimelineTab();
  @override State<_TimelineTab> createState() => _TimelineTabState();
}
class _TimelineTabState extends State<_TimelineTab> {
  final _api        = ApiService();
  final _searchCtrl = TextEditingController();
  List<dynamic> _events = [];
  bool _loading  = true, _loadingMore = false;
  String _filter = 'all';
  String _sort   = 'newest';
  int    _page   = 1;
  bool   _hasMore= true;
  int?   _memberId;
  final _scrollCtrl = ScrollController();

  static const _categories = [
    ('all',          '📋', 'All'),
    ('vitals',       '❤️', 'Vitals'),
    ('medicines',    '💊', 'Medicines'),
    ('lab',          '🧪', 'Lab Tests'),
    ('appointments', '📅', 'Appointments'),
    ('documents',    '🗂️','Documents'),
    ('exercise',     '🏃', 'Exercise'),
    ('meals',        '🍽️','Meals'),
    ('water',        '💧', 'Water'),
    ('sleep',        '😴', 'Sleep'),
    ('score',        '📊', 'Score'),
    ('family',       '👨‍👩‍👧','Family'),
  ];

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200 && !_loadingMore && _hasMore) {
        _load();
      }
    });
  }
  @override void dispose() { _searchCtrl.dispose(); _scrollCtrl.dispose(); super.dispose(); }

  Future<void> _load({bool reset = false}) async {
    if (reset) { setState(() { _page = 1; _events = []; _hasMore = true; _loading = true; }); }
    else { setState(() => _loadingMore = true); }

    final params = <String,dynamic>{'page': _page, 'sort': _sort};
    if (_filter != 'all') params['category'] = _filter;
    if (_searchCtrl.text.trim().isNotEmpty) params['search'] = _searchCtrl.text.trim();
    if (_memberId != null) params['member_id'] = _memberId;

    final r = await _api.get('/timeline/', query: params);
    if (r.success) {
      final newEvents = r.data['events'] as List? ?? [];
      setState(() {
        if (reset) _events = newEvents; else _events.addAll(newEvents);
        _hasMore = _page < (r.data['pages'] as int? ?? 1);
        _page++;
      });
    }
    setState(() { _loading = false; _loadingMore = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Column(children: [
      // Search + sort row
      Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 0), child: Row(children: [
        Expanded(child: TextField(controller: _searchCtrl,
          decoration: InputDecoration(hintText: 'Search timeline...', prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () { _searchCtrl.clear(); _load(reset: true); setState(() {}); }) : null),
          onSubmitted: (_) => _load(reset: true), onChanged: (_) { if (_searchCtrl.text.isEmpty) _load(reset: true); setState(() {}); })),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          icon: Icon(Icons.swap_vert_rounded, color: tm),
          onSelected: (v) { setState(() => _sort = v); _load(reset: true); },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'newest', child: Text('🔽 Newest First')),
            PopupMenuItem(value: 'oldest', child: Text('🔼 Oldest First')),
          ]),
      ])),

      // Category filter chips
      SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        children: _categories.map((c) {
          final sel = c.$1 == _filter;
          return Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
            onTap: () { setState(() => _filter = c.$1); _load(reset: true); },
            child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(color: sel ? AppColors.navy : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100), borderRadius: BorderRadius.circular(100)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(c.$2, style: const TextStyle(fontSize: 13)), const SizedBox(width: 5),
                Text(c.$3, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sel ? Colors.white : tm)),
              ]))));
        }).toList())),

      // Events
      Expanded(child: _loading ? const LoadingView() : _events.isEmpty
          ? const EmptyState(emoji: '📋', title: 'No timeline events', subtitle: 'Your health activity will appear here automatically as you log data')
          : RefreshIndicator(onRefresh: () => _load(reset: true),
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 80),
                itemCount: _events.length + (_loadingMore ? 1 : 0) + 1,
                itemBuilder: (_, i) {
                  if (i == _events.length) return _loadingMore ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(strokeWidth: 2))) : const SizedBox.shrink();
                  if (i > _events.length) return const SizedBox.shrink();
                  final e = _events[i];
                  final isFirst = i == 0;
                  final showDate = isFirst || _events[i-1]['event_date'] != e['event_date'];
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (showDate) _DateHeader(date: e['event_date'] ?? '', isDark: isDark),
                    _EventCard(event: e, isDark: isDark, isLast: i == _events.length - 1),
                  ]);
                }))),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════
// CALENDAR TAB
// ════════════════════════════════════════════════════════════════
class _CalendarTab extends StatefulWidget {
  const _CalendarTab();
  @override State<_CalendarTab> createState() => _CalendarTabState();
}
class _CalendarTabState extends State<_CalendarTab> {
  final _api = ApiService();
  DateTime _focusedDay   = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  Map<String,dynamic>? _calData;
  List<dynamic> _dayEvents = [];
  bool _loading = true, _dayLoading = false;

  @override void initState() { super.initState(); _loadMonth(); _loadDay(DateTime.now()); }

  Future<void> _loadMonth() async {
    setState(() => _loading = true);
    final r = await _api.get('/timeline/calendar', query: {'year': _focusedDay.year, 'month': _focusedDay.month});
    if (r.success) setState(() => _calData = r.data);
    setState(() => _loading = false);
  }

  Future<void> _loadDay(DateTime day) async {
    setState(() => _dayLoading = true);
    final r = await _api.get('/timeline/day', query: {'date': day.toIso8601String().substring(0,10)});
    if (r.success) setState(() => _dayEvents = r.data['events'] ?? []);
    setState(() => _dayLoading = false);
  }

  // Build event markers map
  Map<DateTime, List> get _eventMarkers {
    final m = <DateTime, List>{};
    if (_calData == null) return m;
    for (final d in (_calData!['days'] as List? ?? [])) {
      try {
        final dt = DateTime.parse(d['date']);
        m[DateTime(dt.year, dt.month, dt.day)] = List.filled(d['count'] as int? ?? 1, 1);
      } catch (_) {}
    }
    return m;
  }

  List _eventsForDay(DateTime day) => _eventMarkers[DateTime(day.year, day.month, day.day)] ?? [];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp   = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm   = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Column(children: [
      // Calendar
      Container(color: card, child: TableCalendar(
        firstDay:     DateTime(2022),
        lastDay:      DateTime(2030),
        focusedDay:   _focusedDay,
        selectedDayPredicate: (d) => _selectedDay != null && isSameDay(d, _selectedDay!),
        eventLoader:  _eventsForDay,
        calendarStyle: CalendarStyle(
          todayDecoration:     BoxDecoration(color: AppColors.sage.withOpacity(0.4), shape: BoxShape.circle),
          selectedDecoration:  const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
          markerDecoration:    const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
          markersMaxCount: 3,
          defaultTextStyle:    TextStyle(color: tp),
          weekendTextStyle:    TextStyle(color: AppColors.danger.withOpacity(0.7)),
          outsideDaysVisible:  false,
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: false, titleCentered: true,
          titleTextStyle: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp),
          leftChevronIcon:  Icon(Icons.chevron_left_rounded,  color: tm),
          rightChevronIcon: Icon(Icons.chevron_right_rounded, color: tm),
        ),
        onDaySelected: (sel, focus) {
          setState(() { _selectedDay = sel; _focusedDay = focus; });
          _loadDay(sel);
        },
        onPageChanged: (focus) {
          setState(() => _focusedDay = focus);
          _loadMonth();
        },
        calendarBuilders: CalendarBuilders(
          markerBuilder: (ctx, date, events) {
            if (events.isEmpty) return null;
            return Positioned(bottom: 1, child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.sage, shape: BoxShape.circle)),
              if (events.length > 1) ...[const SizedBox(width: 1), Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle))],
            ]));
          },
        ),
      )),
      Container(height: 1, color: brd),

      // Selected day events
      if (_selectedDay != null) Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Row(children: [
          Text(_formatDate(_selectedDay!), style: TextStyle(fontFamily: 'Fraunces', fontSize: 15, fontWeight: FontWeight.bold, color: tp)),
          const Spacer(),
          if (!_dayLoading) Text('${_dayEvents.length} events', style: TextStyle(fontSize: 12, color: tm, fontWeight: FontWeight.w600)),
        ])),

      Expanded(child: _dayLoading ? const LoadingView()
          : _dayEvents.isEmpty
              ? Center(child: Text('No health activities on this day.', style: TextStyle(color: tm, fontSize: 13)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 80),
                  itemCount: _dayEvents.length,
                  itemBuilder: (_, i) => _EventCard(event: _dayEvents[i], isDark: isDark, compact: true, isLast: i == _dayEvents.length - 1))),
    ]);
  }

  String _formatDate(DateTime d) {
    final months = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final days   = ['','Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[d.weekday]}, ${d.day} ${months[d.month]} ${d.year}';
  }
}

// ════════════════════════════════════════════════════════════════
// SUMMARY TAB
// ════════════════════════════════════════════════════════════════
class _SummaryTab extends StatefulWidget {
  const _SummaryTab();
  @override State<_SummaryTab> createState() => _SummaryTabState();
}
class _SummaryTabState extends State<_SummaryTab> {
  final _api = ApiService();
  Map<String,dynamic>? _summary; bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.get('/timeline/summary');
    if (r.success) setState(() => _summary = r.data);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp   = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm   = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    if (_loading) return const LoadingView();
    if (_summary == null) return EmptyState(emoji: '📊', title: 'No summary', subtitle: '', action: ElevatedButton(onPressed: _load, child: const Text('Retry')));

    final todayCount  = _summary!['today_count'] ?? 0;
    final weekCount   = _summary!['week_count'] ?? 0;
    final weekByCat   = _summary!['week_by_category'] as Map? ?? {};
    final cats        = _summary!['categories'] as Map? ?? {};

    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(14), children: [
      // Key stats
      Row(children: [
        _SumStat('📋', '$todayCount', "Today's activities",   AppColors.navy,  isDark),
        const SizedBox(width: 10),
        _SumStat('📅', '$weekCount',  'This week\'s events',  AppColors.sage,  isDark),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _SumStat('🔴', '${_summary!['missed_medicines'] ?? 0}', 'Missed medicines',    AppColors.danger,  isDark),
        const SizedBox(width: 10),
        _SumStat('🔵', '${_summary!['completed_appts'] ?? 0}',  'Completed appts',    AppColors.info,    isDark),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _SumStat('🧪', '${_summary!['new_lab_results'] ?? 0}',       'New lab results', AppColors.warning, isDark),
        const SizedBox(width: 10),
        _SumStat('🗂️','${_summary!['documents_uploaded'] ?? 0}',    'Documents',       AppColors.document,isDark),
      ]),
      const SizedBox(height: 16),

      // This week breakdown by category
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: brd)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("📊 This Week's Breakdown", style: TextStyle(fontFamily: 'Fraunces', fontSize: 15, fontWeight: FontWeight.bold, color: tp)),
          const SizedBox(height: 14),
          ...weekByCat.entries.where((e) => (e.value as int? ?? 0) > 0).map((e) {
            final cfg   = cats[e.key] as Map?;
            final icon  = cfg?['icon'] as String? ?? '📋';
            final label = cfg?['label'] as String? ?? e.key;
            final color = _parseColor(cfg?['color'] as String?);
            final count = e.value as int? ?? 0;
            final pct   = weekCount > 0 ? count / weekCount : 0.0;
            return Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(icon, style: const TextStyle(fontSize: 16)), const SizedBox(width: 8),
                Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tp))),
                Text('$count', style: TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w700, color: color)),
              ]),
              const SizedBox(height: 4),
              TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: pct.toDouble()), duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic,
                builder: (_, v, __) => ClipRRect(borderRadius: BorderRadius.circular(100), child: LinearProgressIndicator(value: v, minHeight: 5, color: color, backgroundColor: color.withOpacity(0.1)))),
            ]));
          }),
        ])),
      const SizedBox(height: 14),

      // Total all time
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.navy, AppColors.violet]), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Text('📋', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Total Health Events', style: TextStyle(fontFamily: 'Fraunces', fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            Text('All time health activity recorded', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
          ])),
          Text('${_summary!['total_all_time'] ?? 0}', style: const TextStyle(fontFamily: 'monospace', fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.mint)),
        ])),
      const SizedBox(height: 80),
    ]));
  }
}

// ════════════════════════════════════════════════════════════════
// EVENT CARD
// ════════════════════════════════════════════════════════════════
class _EventCard extends StatelessWidget {
  final dynamic event; final bool isDark, compact, isLast;
  const _EventCard({required this.event, required this.isDark, this.compact = false, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final api   = ApiService();
    final card  = isDark ? AppColors.cardDark : Colors.white;
    final brd   = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp    = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm    = isDark ? AppColors.textMutedDark : AppColors.textMuted;
    final color = _parseColor(event['category_color'] as String?);
    final icon  = event['icon'] as String? ?? event['category_icon'] as String? ?? '📋';
    final memberName  = event['member_name'] as String?;
    final memberColor = event['member_color'] != null ? _parseColor(event['member_color']) : null;

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Timeline line + dot
      Column(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withOpacity(isDark ? 0.2 : 0.1), shape: BoxShape.circle, border: Border.all(color: color.withOpacity(0.4), width: 1.5)),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 16)))),
        if (!isLast) Container(width: 2, height: compact ? 40 : 60, color: brd),
      ]),
      const SizedBox(width: 10),

      // Card
      Expanded(child: Container(
        margin: EdgeInsets.only(bottom: compact ? 8 : 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14), border: Border.all(color: brd)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(event['title'] ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tp), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (event['time_str'] != null) Text(event['time_str'], style: TextStyle(fontSize: 10, color: tm)),
          ]),
          if ((event['description'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(event['description'], style: TextStyle(fontSize: 11, color: tm, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 6),
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(100)),
              child: Text('${event['category_icon']} ${event['category_label']}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color))),
            if (memberName != null) ...[
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: (memberColor ?? AppColors.violet).withOpacity(0.1), borderRadius: BorderRadius.circular(100)),
                child: Text('👤 $memberName', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: memberColor ?? AppColors.violet))),
            ],
          ]),
        ]),
      )),
    ]);
  }
}

// ── Date header ───────────────────────────────────────────────────
class _DateHeader extends StatelessWidget {
  final String date; final bool isDark;
  const _DateHeader({required this.date, required this.isDark});
  @override
  Widget build(BuildContext context) {
    String label = date;
    try {
      final dt    = DateTime.parse(date);
      final today = DateTime.now();
      final diff  = DateTime(today.year, today.month, today.day).difference(DateTime(dt.year, dt.month, dt.day)).inDays;
      const months = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      if (diff == 0)      label = 'Today — ${dt.day} ${months[dt.month]}';
      else if (diff == 1) label = 'Yesterday — ${dt.day} ${months[dt.month]}';
      else                label = '${dt.day} ${months[dt.month]} ${dt.year}';
    } catch (_) {}
    return Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Row(children: [
      Expanded(child: Container(height: 1, color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isDark ? AppColors.textMutedDark : AppColors.textMuted))),
      Expanded(child: Container(height: 1, color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200)),
    ]));
  }
}

// ── Helper widgets ─────────────────────────────────────────────────
class _SumStat extends StatelessWidget {
  final String emoji, value, label; final Color color; final bool isDark;
  const _SumStat(this.emoji, this.value, this.label, this.color, this.isDark);
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: color.withOpacity(isDark ? 0.15 : 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.2))),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 20)), const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.8), fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
    ])));
}

Color _parseColor(String? hex) {
  if (hex == null) return AppColors.textMuted;
  try { return Color(int.parse(hex.replaceFirst('#',''), radix: 16) | 0xFF000000); }
  catch (_) { return AppColors.textMuted; }
}