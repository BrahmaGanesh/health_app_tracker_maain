// lib/screens/exercise_screen.dart — Exercise Hub + Live Steps + Offline-First
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/step_tracking_service.dart';
import '../services/notification_service.dart';
import '../services/local_db_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart' hide AppBottomNav;

class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({super.key});
  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sync   = SyncService();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Exercise', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [
          // Sync status indicator
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: sync.isOnline ? AppColors.success.withOpacity(0.12) : AppColors.warning.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: sync.isOnline ? AppColors.success.withOpacity(0.3) : AppColors.warning.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: sync.isOnline ? AppColors.success : AppColors.warning,
                  )),
                  const SizedBox(width: 5),
                  Text(sync.isOnline ? 'Online' : 'Offline',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: sync.isOnline ? AppColors.success : AppColors.warning)),
                ]),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.exercise,
          unselectedLabelColor: isDark ? AppColors.textMutedDark : AppColors.textMuted,
          indicatorColor: AppColors.exercise,
          isScrollable: true,
          tabs: const [
            Tab(text: '🏋️ Log'),
            Tab(text: '👟 Steps'),
            Tab(text: '🫁 Breathing'),
            Tab(text: '📚 Library'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _LogTab(),
          _StepsTab(),
          _BreathingTab(),
          _LibraryTab(),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// LOG TAB
// ══════════════════════════════════════════════════════════════════
class _LogTab extends StatefulWidget {
  const _LogTab();
  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  final _api      = ApiService();
  final _sync     = SyncService();
  final _nameCtrl = TextEditingController();
  final _durCtrl  = TextEditingController();
  List<dynamic> _history = [];
  bool _loading = true, _saving = false;
  String _type = 'cardio', _intensity = 'moderate';
  int _todayMins = 0, _totalCal = 0;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _nameCtrl.dispose(); _durCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getExerciseHistory(days: 7);
    if (resp.success) {
      setState(() {
        _history    = resp.data['logs'] ?? [];
        _todayMins  = resp.data['today_mins'] ?? 0;
        _totalCal   = resp.data['total_calories'] ?? 0;
        _loading    = false;
      });
    } else { setState(() => _loading = false); }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final resp = await _api.logExercise(
      exerciseName: _nameCtrl.text.trim(), exerciseType: _type,
      durationMinutes: int.tryParse(_durCtrl.text), intensity: _intensity,
    );
    setState(() => _saving = false);
    if (resp.success) {
      _nameCtrl.clear(); _durCtrl.clear();
      FocusScope.of(context).unfocus();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.cardDark : Colors.white;
    final border = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.exercise,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Stats row
          Row(children: [
            _MiniStat('⏱️', 'Today', '$_todayMins min', const Color(0xFF047857), isDark),
            const SizedBox(width: 12),
            _MiniStat('🔥', 'Calories', '$_totalCal', AppColors.danger, isDark),
            const SizedBox(width: 12),
            _MiniStat('📅', 'Sessions', '${_history.length}', AppColors.violet, isDark),
          ]),
          const SizedBox(height: 16),

          // Form
          _Card(isDark: isDark, cardBg: cardBg, border: border, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _CardTitle('➕ Log Exercise', isDark),
            const SizedBox(height: 14),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Exercise Name', hintText: 'e.g. Morning Walk')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: {'cardio':'🏃 Cardio','strength':'💪 Strength','yoga':'🧘 Yoga','flexibility':'🤸 Stretching','sports':'⚽ Sports','other':'🏋️ Other'}.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) => setState(() => _type = v ?? 'cardio'),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _durCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Duration (min)', hintText: '30'))),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _intensity,
              decoration: const InputDecoration(labelText: 'Intensity'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low — Easy walk')),
                DropdownMenuItem(value: 'moderate', child: Text('Moderate — Brisk')),
                DropdownMenuItem(value: 'high', child: Text('High — Running')),
                DropdownMenuItem(value: 'very_high', child: Text('Very High — HIIT')),
              ],
              onChanged: (v) => setState(() => _intensity = v ?? 'moderate'),
            ),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.exercise, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('🏋️ Log Exercise', style: TextStyle(fontWeight: FontWeight.bold)),
            )),
          ])),
          const SizedBox(height: 16),

          // Recent
          if (!_loading && _history.isNotEmpty)
            _Card(isDark: isDark, cardBg: cardBg, border: border, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _CardTitle('📋 Recent Sessions', isDark),
              const SizedBox(height: 10),
              ..._history.take(10).map((l) => ListTile(
                contentPadding: EdgeInsets.zero, dense: true,
                leading: Text({'cardio':'🏃','strength':'💪','yoga':'🧘','flexibility':'🤸','sports':'⚽','other':'🏋️'}[l['exercise_type']] ?? '🏋️', style: const TextStyle(fontSize: 22)),
                title: Text(l['exercise_name'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
                subtitle: Text('${l['duration_minutes'] ?? 0} min · ${l['log_date'] ?? ''}', style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
                trailing: Text('🔥 ${l['calories_burned'] ?? 0}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.exercise)),
              )),
            ])),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// STEPS TAB — Live tracking + calories + km + daily graph + reset
// ══════════════════════════════════════════════════════════════════
class _StepsTab extends StatefulWidget {
  const _StepsTab();
  @override
  State<_StepsTab> createState() => _StepsTabState();
}

class _StepsTabState extends State<_StepsTab> {
  final _manualCtrl = TextEditingController();
  final _api = ApiService();
  bool _savingManual = false;

  @override
  void dispose() { _manualCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final cardBg    = isDark ? AppColors.cardDark : Colors.white;
    final border    = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final stepSvc   = context.watch<StepTrackingService>();

    final steps    = stepSvc.todaySteps;
    final goal     = stepSvc.dailyGoal;
    final dist     = stepSvc.distanceKm;
    final cal      = stepSvc.calories;
    final pct      = stepSvc.progressPct;
    final tracking = stepSvc.isTracking;
    final week     = stepSvc.weekHistory;

    return RefreshIndicator(
      onRefresh: () => stepSvc.syncNow(),
      color: AppColors.info,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── LIVE COUNTER CARD ───────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: tracking
                    ? [const Color(0xFF1D4ED8), const Color(0xFF2563EB)]
                    : [const Color(0xFF334155), const Color(0xFF475569)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: (tracking ? AppColors.info : Colors.grey).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            padding: const EdgeInsets.all(22),
            child: Column(children: [

              // Status badge
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(100)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (tracking) ...[
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      const Text('LIVE TRACKING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4ADE80), letterSpacing: 1.2)),
                    ] else
                      const Text('TRACKING PAUSED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white60, letterSpacing: 1)),
                  ]),
                ),
              ]),
              const SizedBox(height: 20),

              // Big step counter
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('$steps', style: const TextStyle(fontFamily: 'monospace', fontSize: 60, fontWeight: FontWeight.w700, color: Colors.white, height: 1)),
              ]),
              const Text('steps today', style: TextStyle(fontSize: 13, color: Colors.white60, fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),

              // Progress bar
              Column(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: LinearProgressIndicator(
                    value: pct, minHeight: 10,
                    backgroundColor: Colors.white.withOpacity(0.15),
                    color: stepSvc.goalAchieved ? const Color(0xFF4ADE80) : Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${(pct * 100).toInt()}% of goal', style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600)),
                  Text('$goal steps', style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600)),
                ]),
              ]),
              const SizedBox(height: 20),

              // Stats row
              Row(children: [
                _LiveStat('📍', '${dist}km', 'Distance'),
                _Divider(),
                _LiveStat('🔥', '$cal', 'Calories'),
                _Divider(),
                _LiveStat('🎯', stepSvc.goalAchieved ? '✅' : '${goal - steps}', stepSvc.goalAchieved ? 'Goal Done!' : 'Remaining'),
              ]),
              const SizedBox(height: 20),

              // Control buttons
              Row(children: [
                Expanded(child: ElevatedButton(
                  onPressed: tracking ? () => stepSvc.stopTracking() : () => stepSvc.startTracking(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tracking ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                    foregroundColor: tracking ? const Color(0xFFFCA5A5) : const Color(0xFF4ADE80),
                    elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: tracking ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(tracking ? '⏹ Stop' : '▶ Start', style: const TextStyle(fontWeight: FontWeight.bold)),
                )),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => stepSvc.syncNow(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.15), foregroundColor: Colors.white,
                    elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('☁️ Sync', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ]),

              if (stepSvc.goalAchieved) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFF4ADE80).withOpacity(0.15), borderRadius: BorderRadius.circular(100)),
                  child: const Text('🏆 Daily goal achieved! Amazing work!', style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 20),

          // ── WEEKLY GRAPH ────────────────────────────────────
          if (week.isNotEmpty)
            _Card(isDark: isDark, cardBg: cardBg, border: border, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: _CardTitle('📊 7-Day Steps', isDark)),
                Text('Goal: $goal/day', style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: BarChart(BarChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(color: isDark ? Colors.white10 : Colors.grey.shade100, strokeWidth: 1)),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36,
                        getTitlesWidget: (v, _) => Text('${(v / 1000).toStringAsFixed(0)}k',
                            style: TextStyle(fontSize: 9, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)))),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= week.length) return const SizedBox.shrink();
                          final isToday = week[i].date == DateTime.now().toIso8601String().substring(0, 10);
                          return Padding(padding: const EdgeInsets.only(top: 4), child: Text(week[i].dayLabel,
                              style: TextStyle(fontSize: 10, fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                                  color: isToday ? AppColors.info : (isDark ? AppColors.textMutedDark : AppColors.textMuted))));
                        })),
                  ),
                  barGroups: week.asMap().entries.map((e) {
                    final i = e.key; final d = e.value;
                    final isToday = d.date == DateTime.now().toIso8601String().substring(0, 10);
                    return BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: d.steps.toDouble(),
                        color: d.achieved ? const Color(0xFF22C55E) : (isToday ? AppColors.info : AppColors.info.withOpacity(0.5)),
                        width: 22,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        rodStackItems: [],
                      ),
                    ]);
                  }).toList(),
                  maxY: (goal * 1.3).toDouble(),
                  extraLinesData: ExtraLinesData(horizontalLines: [
                    HorizontalLine(y: goal.toDouble(), color: Colors.amber.withOpacity(0.5),
                        strokeWidth: 1.5, dashArray: [6, 4],
                        label: HorizontalLineLabel(show: false)),
                  ]),
                )),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _LegendDot(const Color(0xFF22C55E), 'Goal achieved'),
                const SizedBox(width: 16),
                _LegendDot(AppColors.info, 'Steps'),
                const SizedBox(width: 16),
                _LegendDot(Colors.amber, 'Goal line'),
              ]),
            ])),
          const SizedBox(height: 16),

          // ── PERMISSION NOTICE ───────────────────────────────
          if (stepSvc.status == 'no_permission')
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.warning.withOpacity(0.3))),
              child: Row(children: [
                const Text('⚠️', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Permission needed', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text('Tap Allow to count steps with your phone sensor', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ])),
                ElevatedButton(
                  onPressed: () async {
                    await stepSvc.requestPermission();
                    if (stepSvc.hasPermission) await stepSvc.startTracking();
                  },
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                  child: const Text('Allow', style: TextStyle(fontSize: 12)),
                ),
              ]),
            )
          else if (stepSvc.status == 'unavailable')
            _Card(isDark: isDark, cardBg: cardBg, border: border, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _CardTitle('✏️ Manual Entry', isDark),
              const SizedBox(height: 10),
              const Text('Pedometer not available. Enter steps manually:', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: _manualCtrl, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Step count', hintText: '8000'))),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _savingManual ? null : () async {
                    final v = int.tryParse(_manualCtrl.text);
                    if (v == null) return;
                    setState(() => _savingManual = true);
                    await stepSvc.setManualSteps(v);
                    _manualCtrl.clear();
                    setState(() => _savingManual = false);
                  },
                  child: const Text('Save'),
                ),
              ]),
            ])),

          // ── OFFLINE NOTE ─────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(isDark ? 0.1 : 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withOpacity(0.2)),
            ),
            child: Row(children: [
              const Text('💾', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Steps are saved offline first and synced automatically when internet is available. Data resets at midnight each day.',
                style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted, height: 1.5),
              )),
            ]),
          ),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// BREATHING TAB
// ══════════════════════════════════════════════════════════════════
class _BreathingTab extends StatefulWidget {
  const _BreathingTab();
  @override
  State<_BreathingTab> createState() => _BreathingTabState();
}

class _BreathingTabState extends State<_BreathingTab> {
  final _api = ApiService();
  List<dynamic> _exercises = [];
  bool _loading = true;
  Map<String, dynamic>? _active;
  int _phaseIdx = 0, _round = 0, _countdown = 0;
  Timer? _timer;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _load() async {
    final resp = await _api.getBreathingConfig();
    if (resp.success) setState(() => _exercises = resp.data['exercises'] ?? []);
    setState(() => _loading = false);
  }

  void _start(Map<String, dynamic> ex) {
    setState(() { _active = ex; _phaseIdx = 0; _round = 0; _countdown = ex['phases'][0]['duration']; });
    _runPhase();
  }

  void _runPhase() {
    _timer?.cancel();
    final phases = _active!['phases'] as List;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          _phaseIdx++;
          if (_phaseIdx >= phases.length) {
            _phaseIdx = 0; _round++;
            if (_round >= (_active!['recommended_rounds'] ?? 4)) {
              t.cancel();
              NotificationService().playSound('gentle');
              setState(() => _active = null);
              return;
            }
          }
          _countdown = phases[_phaseIdx]['duration'];
          NotificationService().playSound('gentle');
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_active != null) {
      final phase = _active!['phases'][_phaseIdx];
      final color = Colors.blue;
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_active!['name'], style: TextStyle(fontFamily: 'Fraunces', fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
        Text('Round ${_round + 1}/${_active!['recommended_rounds']}', style: const TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 30),
        Container(width: 220, height: 220,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.12), border: Border.all(color: color, width: 3)),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(phase['name'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text('$_countdown', style: const TextStyle(fontFamily: 'monospace', fontSize: 52, fontWeight: FontWeight.w600)),
            Text(phase['instruction'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textMuted), textAlign: TextAlign.center),
          ])),
        ),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: () { _timer?.cancel(); setState(() => _active = null); },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger.withOpacity(0.12), foregroundColor: AppColors.danger),
            child: const Text('⏹ Stop')),
      ]));
    }
    if (_loading) return const LoadingView();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _exercises.length,
      itemBuilder: (_, i) {
        final ex = _exercises[i];
        return Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ex['name'], style: TextStyle(fontFamily: 'Fraunces', fontSize: 17, fontWeight: FontWeight.bold, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(ex['desc'] ?? '', style: TextStyle(fontSize: 13, color: isDark ? AppColors.textMutedDark : AppColors.textMuted, height: 1.4)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => _start(ex), child: const Text('▶ Start Session'))),
          ])));
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// LIBRARY TAB
// ══════════════════════════════════════════════════════════════════
class _LibraryTab extends StatefulWidget {
  const _LibraryTab();
  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab> {
  final _api = ApiService();
  List<dynamic> _exercises = [];
  bool _loading = true, _bpSafe = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getExerciseLibrary(bpSafe: _bpSafe);
    if (resp.success) setState(() => _exercises = resp.data['exercises'] ?? []);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Row(children: [
        FilterChip(label: const Text('❤️ BP-Safe Only'), selected: _bpSafe,
            onSelected: (v) { setState(() => _bpSafe = v); _load(); },
            selectedColor: AppColors.success.withOpacity(0.15)),
      ])),
      Expanded(child: _loading ? const LoadingView() : ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _exercises.length,
        itemBuilder: (_, i) {
          final ex = _exercises[i];
          return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
            leading: CircleAvatar(backgroundColor: AppColors.exercise.withOpacity(0.1),
                child: Text({'cardio':'🏃','strength':'💪','yoga':'🧘','flexibility':'🤸','breathing':'🫁','sports':'⚽'}[ex['category']] ?? '🏋️')),
            title: Text(ex['name'], style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
            subtitle: Text(ex['description'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
            trailing: ex['bp_safe'] == true ? const Text('❤️') : null,
            onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              builder: (_) => Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ex['name'], style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
                const SizedBox(height: 8),
                Text(ex['description'] ?? '', style: TextStyle(fontSize: 14, color: isDark ? AppColors.textMutedDark : AppColors.textMuted, height: 1.5)),
                const SizedBox(height: 12),
                Text('Instructions', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(ex['instructions'] ?? '', style: TextStyle(fontSize: 13, color: isDark ? AppColors.textMutedDark : AppColors.textMuted, height: 1.6)),
                const SizedBox(height: 20),
              ]))),
          ));
        },
      )),
    ]);
  }
}

// ── Shared helper widgets ─────────────────────────────────────────
class _Card extends StatelessWidget {
  final bool isDark; final Color cardBg, border; final Widget child;
  const _Card({required this.isDark, required this.cardBg, required this.border, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))]),
    child: child,
  );
}

class _CardTitle extends StatelessWidget {
  final String text; final bool isDark;
  const _CardTitle(this.text, this.isDark);
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? AppColors.textOnDark : AppColors.textPrimary));
}

class _MiniStat extends StatelessWidget {
  final String emoji, label, value; final Color color; final bool isDark;
  const _MiniStat(this.emoji, this.label, this.value, this.color, this.isDark);
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withOpacity(isDark ? 0.15 : 0.08), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      Text(label, style: TextStyle(fontSize: 10, color: isDark ? AppColors.textMutedDark : AppColors.textMuted, fontWeight: FontWeight.w600)),
    ]),
  ));
}

class _LiveStat extends StatelessWidget {
  final String emoji, value, label;
  const _LiveStat(this.emoji, this.value, this.label);
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(emoji, style: const TextStyle(fontSize: 18)),
    const SizedBox(height: 4),
    Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60, fontWeight: FontWeight.w600)),
  ]));
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 36, color: Colors.white.withOpacity(0.15));
}

class _LegendDot extends StatelessWidget {
  final Color color; final String label;
  const _LegendDot(this.color, this.label);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
  ]);
}