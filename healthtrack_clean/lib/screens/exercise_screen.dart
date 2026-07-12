// lib/screens/exercise_screen.dart — Premium Exercise Hub
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
import '../widgets/common_widgets.dart';
import '../widgets/tts_speaker_button.dart';

class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({super.key});

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sync = SyncService();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Exercise',
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (sync.isOnline
                          ? AppColors.success
                          : AppColors.warning)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: sync.isOnline
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      sync.isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: sync.isOnline
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.exercise,
          unselectedLabelColor:
              isDark ? AppColors.textMutedDark : AppColors.textMuted,
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
      body: const TabBarView(
        children: [
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

// ════════════════════════════════════════════════════════════════
// LOG TAB — premium cards, timeline design
// ════════════════════════════════════════════════════════════════
class _LogTab extends StatefulWidget {
  const _LogTab();

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  final _api = ApiService();
  final _sync = SyncService();

  final _nameCtrl = TextEditingController();
  final _durCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<dynamic> _history = [];
  bool _loading = true;
  bool _saving = false;

  String _type = 'cardio';
  String _intensity = 'moderate';

  int _todayMins = 0;
  int _totalCal = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _durCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    final r = await _api.getExerciseHistory(days: 7);

    if (!mounted) return;

    if (r.success) {
      setState(() {
        _history = r.data['logs'] ?? [];
        _todayMins = r.data['today_mins'] ?? 0;
        _totalCal = r.data['total_calories'] ?? 0;
      });
    }

    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;

    setState(() => _saving = true);

    await _api.logExercise(
      exerciseName: _nameCtrl.text.trim(),
      exerciseType: _type,
      durationMinutes: int.tryParse(_durCtrl.text),
      intensity: _intensity,
    );

    if (!mounted) return;

    setState(() => _saving = false);
    _nameCtrl.clear();
    _durCtrl.clear();
    _notesCtrl.clear();
    FocusScope.of(context).unfocus();

    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Logged!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _StatPill(
                '⏱️',
                '$_todayMins min',
                'Today',
                const Color(0xFF047857),
                isDark,
              ),
              const SizedBox(width: 10),
              _StatPill(
                '🔥',
                '$_totalCal',
                'Calories',
                AppColors.danger,
                isDark,
              ),
              const SizedBox(width: 10),
              _StatPill(
                '📅',
                '${_history.length}',
                'Sessions',
                AppColors.violet,
                isDark,
              ),
            ],
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: brd),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '➕ Log Exercise',
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: tp,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Exercise Name',
                    hintText: 'e.g. Morning Walk',
                    prefixIcon: Icon(Icons.fitness_center_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _type,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: {
                          'cardio': '🏃 Cardio',
                          'strength': '💪 Strength',
                          'yoga': '🧘 Yoga',
                          'flexibility': '🤸 Stretch',
                          'sports': '⚽ Sports',
                          'other': '🏋️ Other',
                        }
                            .entries
                            .map(
                              (e) => DropdownMenuItem<String>(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _type = v ?? 'cardio'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _durCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Duration (min)',
                          hintText: '30',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _intensity,
                  decoration: const InputDecoration(labelText: 'Intensity'),
                  items: const [
                    DropdownMenuItem(
                      value: 'low',
                      child: Text('🚶 Low — Easy walk'),
                    ),
                    DropdownMenuItem(
                      value: 'moderate',
                      child: Text('🏃 Moderate — Brisk'),
                    ),
                    DropdownMenuItem(
                      value: 'high',
                      child: Text('🏃‍♂️ High — Running'),
                    ),
                    DropdownMenuItem(
                      value: 'very_high',
                      child: Text('🔥 Very High — HIIT'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _intensity = v ?? 'moderate'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'How did it feel?',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.exercise,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '🏋️ Log Exercise',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (!_loading && _history.isNotEmpty) ...[
            Text(
              '📋 Recent Sessions',
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: tp,
              ),
            ),
            const SizedBox(height: 12),
            ..._history.take(10).toList().asMap().entries.map((e) {
              final i = e.key;
              final l = e.value;
              final visibleHistory = _history.take(10).toList();
              final isLast = i == visibleHistory.length - 1;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.exercise.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            {
                                  'cardio': '🏃',
                                  'strength': '💪',
                                  'yoga': '🧘',
                                  'flexibility': '🤸',
                                  'sports': '⚽',
                                  'other': '🏋️',
                                }[l['exercise_type']] ??
                                '🏋️',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      if (!isLast)
                        Container(
                          width: 2,
                          height: 60,
                          color: AppColors.exercise.withOpacity(0.15),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: brd),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l['exercise_name'] ?? '',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: tp,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${l['duration_minutes'] ?? 0} min · ${l['intensity'] ?? ''} · ${l['log_date'] ?? ''}',
                                  style: TextStyle(fontSize: 11, color: tm),
                                ),
                                if (l['notes'] != null &&
                                    l['notes'].toString().isNotEmpty)
                                  Text(
                                    l['notes'].toString(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: tm,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '🔥 ${l['calories_burned'] ?? 0}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.exercise,
                                ),
                              ),
                              const Text(
                                'kcal',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// STEPS TAB — live counter + chart
// ════════════════════════════════════════════════════════════════
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
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    final stepSvc = context.watch<StepTrackingService>();
    final steps = stepSvc.todaySteps;
    final goal = stepSvc.dailyGoal;
    final dist = stepSvc.distanceKm;
    final cal = stepSvc.calories;
    final pct = stepSvc.progressPct;
    final tracking = stepSvc.isTracking;
    final week = stepSvc.weekHistory;

    return RefreshIndicator(
      onRefresh: () => stepSvc.syncNow(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: tracking
                    ? [const Color(0xFF1D4ED8), const Color(0xFF2563EB)]
                    : [const Color(0xFF334155), const Color(0xFF475569)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: (tracking ? AppColors.info : Colors.grey)
                      .withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: tracking
                                  ? const Color(0xFF4ADE80)
                                  : Colors.white38,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            tracking ? 'LIVE TRACKING' : 'PAUSED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: tracking
                                  ? const Color(0xFF4ADE80)
                                  : Colors.white60,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  '$steps',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 64,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                const Text(
                  'steps today',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white60,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 10,
                    backgroundColor: Colors.white.withOpacity(0.15),
                    color: stepSvc.goalAchieved
                        ? const Color(0xFF4ADE80)
                        : Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(pct * 100).toInt()}% of goal',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$goal steps',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _LiveStat('📍', '${dist}km', 'Distance'),
                    Container(
                      width: 1,
                      height: 36,
                      color: Colors.white.withOpacity(0.15),
                    ),
                    _LiveStat('🔥', '$cal', 'Calories'),
                    Container(
                      width: 1,
                      height: 36,
                      color: Colors.white.withOpacity(0.15),
                    ),
                    _LiveStat(
                      '🎯',
                      stepSvc.goalAchieved ? '✅' : '${goal - steps}',
                      stepSvc.goalAchieved ? 'Done!' : 'Left',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: tracking
                            ? () => stepSvc.stopTracking()
                            : () => stepSvc.startTracking(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tracking
                              ? Colors.red.withOpacity(0.2)
                              : Colors.green.withOpacity(0.2),
                          foregroundColor: tracking
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF4ADE80),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(
                            color: tracking
                                ? Colors.red.withOpacity(0.3)
                                : Colors.green.withOpacity(0.3),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          tracking ? '⏹ Stop' : '▶ Start',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () => stepSvc.syncNow(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.15),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '☁️ Sync',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (stepSvc.goalAchieved) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4ADE80).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Text(
                      '🏆 Daily goal achieved!',
                      style: TextStyle(
                        color: Color(0xFF4ADE80),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (week.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: brd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '📊 7-Day Steps',
                          style: TextStyle(
                            fontFamily: 'Fraunces',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: tp,
                          ),
                        ),
                      ),
                      Text(
                        'Goal: $goal/day',
                        style: TextStyle(
                          fontSize: 11,
                          color: tm,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 180,
                    child: BarChart(
                      BarChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color:
                                isDark ? Colors.white10 : Colors.grey.shade100,
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                              getTitlesWidget: (v, _) => Text(
                                '${(v / 1000).toStringAsFixed(0)}k',
                                style: TextStyle(fontSize: 9, color: tm),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              getTitlesWidget: (v, _) {
                                final i = v.toInt();
                                if (i < 0 || i >= week.length) {
                                  return const SizedBox.shrink();
                                }
                                final isToday = week[i].date ==
                                    DateTime.now()
                                        .toIso8601String()
                                        .substring(0, 10);
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    week[i].dayLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: isToday
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: isToday ? AppColors.info : tm,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: week
                            .asMap()
                            .entries
                            .map(
                              (e) => BarChartGroupData(
                                x: e.key,
                                barRods: [
                                  BarChartRodData(
                                    toY: e.value.steps.toDouble(),
                                    color: e.value.achieved
                                        ? const Color(0xFF22C55E)
                                        : AppColors.info,
                                    width: 24,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(8),
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                        maxY: (goal * 1.3).toDouble(),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(
                              y: goal.toDouble(),
                              color: Colors.amber.withOpacity(0.6),
                              strokeWidth: 1.5,
                              dashArray: [6, 4],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LDot(const Color(0xFF22C55E), 'Goal hit'),
                      const SizedBox(width: 12),
                      _LDot(AppColors.info, 'Steps'),
                      const SizedBox(width: 12),
                      _LDot(Colors.amber, 'Goal line'),
                    ],
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          if (stepSvc.status == 'no_permission')
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.warning.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  const Text('⚠️', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Permission needed',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Allow activity recognition to count steps',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      await stepSvc.requestPermission();
                      if (stepSvc.hasPermission) {
                        await stepSvc.startTracking();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    child: const Text(
                      'Allow',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          if (stepSvc.status == 'unavailable')
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: brd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '✏️ Manual Entry',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: tp,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Step count',
                            hintText: '8000',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _savingManual
                            ? null
                            : () async {
                                final v = int.tryParse(_manualCtrl.text);
                                if (v == null) return;
                                setState(() => _savingManual = true);
                                await stepSvc.setManualSteps(v);
                                _manualCtrl.clear();
                                if (mounted) {
                                  setState(() => _savingManual = false);
                                }
                              },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(isDark ? 0.1 : 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.info.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                const Text('💾', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Saved offline first, synced automatically. Resets every midnight.',
                    style: TextStyle(fontSize: 11, color: tm, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// BREATHING TAB — animated cards + bottom sheet + TTS
// ════════════════════════════════════════════════════════════════
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
  int _phaseIdx = 0;
  int _round = 0;
  int _countdown = 0;
  Timer? _timer;

  static const _gradients = [
    [Color(0xFF0369A1), Color(0xFF0EA5E9)],
    [Color(0xFF065F46), Color(0xFF10B981)],
    [Color(0xFF4C1D95), Color(0xFF7C3AED)],
    [Color(0xFF92400E), Color(0xFFF59E0B)],
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _api.getBreathingConfig();
    if (!mounted) return;

    if (r.success) {
      setState(() => _exercises = r.data['exercises'] ?? []);
    }
    setState(() => _loading = false);
  }

  void _openBottomSheet(Map<String, dynamic> ex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final instructions = ex['description']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, ctrl) => Stack(
          children: [
            ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _gradients[
                            _exercises.indexOf(ex) % _gradients.length],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('🫁', style: TextStyle(fontSize: 36)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    ex['name'] ?? '',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF142D4C),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (ex['duration'] != null)
                  Center(
                    child: Text(
                      '${ex['duration']} min',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  instructions,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.7,
                  ),
                ),
                if (ex['benefits'] != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Benefits',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF142D4C),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ex['benefits'].toString(),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black54,
                      height: 1.6,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _startSession(ex),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      '▶ Start Breathing Session',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              bottom: 24,
              right: 20,
              child: TtsSpeakerButton(text: instructions),
            ),
          ],
        ),
      ),
    );
  }

  void _startSession(Map<String, dynamic> ex) {
    Navigator.pop(context);
    final phases = (ex['phases'] as List?) ?? [{'duration': 4}];

    setState(() {
      _active = ex;
      _phaseIdx = 0;
      _round = 0;
      _countdown = (phases[0]['duration'] ?? 4) as int;
    });

    _runPhase();
  }

  void _runPhase() {
    _timer?.cancel();
    final phases = _active!['phases'] as List? ?? [{'name': 'Breathe', 'duration': 4}];

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _countdown--;

        if (_countdown <= 0) {
          _phaseIdx++;

          if (_phaseIdx >= phases.length) {
            _phaseIdx = 0;
            _round++;

            if (_round >= (_active!['recommended_rounds'] ?? 4)) {
              timer.cancel();
              NotificationService().playSound('gentle');
              _active = null;
              return;
            }
          }

          _countdown = phases[_phaseIdx]['duration'] ?? 4;
          NotificationService().playSound('gentle');
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    if (_active != null) {
      final phases =
          _active!['phases'] as List? ?? [{'name': 'Breathe', 'duration': 4}];
      final phase = phases[_phaseIdx];

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _active!['name'],
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: tp,
              ),
            ),
            Text(
              'Round ${_round + 1}/${_active!['recommended_rounds'] ?? 4}',
              style: TextStyle(color: tm),
            ),
            const SizedBox(height: 30),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1.0),
              duration: Duration(seconds: phase['duration'] ?? 4),
              curve: Curves.easeInOut,
              builder: (_, v, __) => Transform.scale(
                scale: v,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1D4ED8).withOpacity(0.15),
                    border: Border.all(
                      color: const Color(0xFF1D4ED8),
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          phase['name'] ?? '',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                        Text(
                          '$_countdown',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 52,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          phase['instruction'] ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () {
                _timer?.cancel();
                setState(() => _active = null);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger.withOpacity(0.12),
                foregroundColor: AppColors.danger,
                elevation: 0,
              ),
              child: const Text('⏹ Stop'),
            ),
          ],
        ),
      );
    }

    if (_loading) return const LoadingView();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _exercises.length,
      itemBuilder: (_, i) {
        final ex = _exercises[i];
        final grad = _gradients[i % _gradients.length];

        return GestureDetector(
          onTap: () => _openBottomSheet(ex),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: grad),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: grad[0].withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('🫁', style: TextStyle(fontSize: 26)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ex['name'] ?? '',
                          style: const TextStyle(
                            fontFamily: 'Fraunces',
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ex['description']?.toString().split('.').first ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (ex['duration'] != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  '${ex['duration']} min',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: const Text(
                                'Tap to start',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white54,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════
// LIBRARY TAB — premium cards + bottom sheet + TTS
// ════════════════════════════════════════════════════════════════
class _LibraryTab extends StatefulWidget {
  const _LibraryTab();

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();

  List<dynamic> _exercises = [];
  bool _loading = true;
  bool _bpSafe = false;
  String _category = 'all';

  static const _cats = [
    'all',
    'cardio',
    'strength',
    'yoga',
    'flexibility',
    'breathing',
    'sports',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.getExerciseLibrary(bpSafe: _bpSafe);

    if (!mounted) return;

    if (r.success) {
      setState(() => _exercises = r.data['exercises'] ?? []);
    }
    setState(() => _loading = false);
  }

  List<dynamic> get _filtered {
    var list = _exercises;

    if (_category != 'all') {
      list = list.where((e) => e['category'] == _category).toList();
    }

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((e) => (e['name'] ?? '').toString().toLowerCase().contains(q))
          .toList();
    }

    return list;
  }

  void _openExercise(Map<String, dynamic> ex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final instructions =
        ex['instructions']?.toString() ?? ex['description']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, ctrl) => Stack(
          children: [
            ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
              children: [
                BsHeader(
                  imageUrl: ex['image_url'],
                  emoji: {
                        'cardio': '🏃',
                        'strength': '💪',
                        'yoga': '🧘',
                        'flexibility': '🤸',
                        'breathing': '🫁',
                        'sports': '⚽',
                      }[ex['category']] ??
                      '🏋️',
                  title: ex['name'] ?? '',
                  badge: Row(
                    children: [
                      DifficultyChip(
                        difficulty: ex['difficulty'] ?? 'beginner',
                      ),
                      const SizedBox(width: 8),
                      if (ex['bp_safe'] == true)
                        const Text(
                          '❤️ BP Safe',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      MacroChip(
                        label: 'Duration',
                        value: '${ex['duration_mins'] ?? '—'} min',
                        color: AppColors.info,
                      ),
                      const SizedBox(width: 8),
                      MacroChip(
                        label: 'Cal/min',
                        value: '${ex['calories_per_min'] ?? '—'}',
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 8),
                      if (ex['muscle_group'] != null)
                        MacroChip(
                          label: 'Muscles',
                          value: ex['muscle_group'],
                          color: AppColors.violet,
                        ),
                      const SizedBox(width: 8),
                      if (ex['equipment'] != null)
                        MacroChip(
                          label: 'Equipment',
                          value: ex['equipment'],
                          color: AppColors.textMuted,
                        ),
                    ],
                  ),
                ),
                if (ex['description'] != null)
                  BsSection(
                    title: '📋 Description',
                    child: Text(
                      ex['description'],
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                        height: 1.6,
                      ),
                    ),
                  ),
                if (instructions.isNotEmpty)
                  BsSection(
                    title: '👟 Instructions',
                    child: Text(
                      instructions,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                        height: 1.8,
                      ),
                    ),
                  ),
                if (ex['benefits'] != null)
                  BsSection(
                    title: '💪 Benefits',
                    child: Text(
                      ex['benefits'],
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black54,
                        height: 1.6,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.exercise,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      '✅ Mark as Completed',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              bottom: 24,
              right: 20,
              child: TtsSpeakerButton(text: instructions),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final filtered = _filtered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search exercises...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
          ),
        ),

        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: _cats.map((c) {
              final sel = c == _category;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _category = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: sel
                          ? AppColors.exercise
                          : (isDark
                              ? const Color(0xFF1A2E45)
                              : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      c == 'all' ? 'All' : c[0].toUpperCase() + c.substring(1),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: sel ? Colors.white : tm,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              FilterChip(
                label: const Text('❤️ BP-Safe Only'),
                selected: _bpSafe,
                onSelected: (v) {
                  setState(() => _bpSafe = v);
                  _load();
                },
                selectedColor: AppColors.success.withOpacity(0.15),
                checkmarkColor: AppColors.success,
              ),
              const Spacer(),
              Text(
                '${filtered.length} exercises',
                style: TextStyle(
                  fontSize: 12,
                  color: tm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _loading
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: filtered.isEmpty
                      ? const EmptyState(
                          emoji: '🏋️',
                          title: 'No exercises found',
                          subtitle: 'Try different filters.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final ex = filtered[i];

                            return GestureDetector(
                              onTap: () =>
                                  _openExercise(ex as Map<String, dynamic>),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: card,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: brd),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.03),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: AppColors.exercise
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Center(
                                          child: Text(
                                            {
                                                  'cardio': '🏃',
                                                  'strength': '💪',
                                                  'yoga': '🧘',
                                                  'flexibility': '🤸',
                                                  'breathing': '🫁',
                                                  'sports': '⚽',
                                                }[ex['category']] ??
                                                '🏋️',
                                            style:
                                                const TextStyle(fontSize: 24),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              ex['name'] ?? '',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: tp,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              (ex['muscle_group'] ??
                                                      ex['description'] ??
                                                      '')
                                                  .toString(),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: tm,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              children: [
                                                DifficultyChip(
                                                  difficulty:
                                                      ex['difficulty'] ?? 'easy',
                                                ),
                                                if (ex['duration_mins'] != null)
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.info
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              100),
                                                    ),
                                                    child: Text(
                                                      '${ex['duration_mins']} min',
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: AppColors.info,
                                                      ),
                                                    ),
                                                  ),
                                                if (ex['bp_safe'] == true)
                                                  const Text(
                                                    '❤️',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: AppColors.textMuted,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

// ── Shared helper widgets ─────────────────────────────────────────
class _StatPill extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final Color color;
  final bool isDark;

  const _StatPill(
    this.emoji,
    this.value,
    this.label,
    this.color,
    this.isDark,
  );

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDark
                    ? AppColors.textMutedDark
                    : AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveStat extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;

  const _LiveStat(this.emoji, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white60,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LDot(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}