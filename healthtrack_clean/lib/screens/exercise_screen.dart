// ============================================================
// lib/screens/exercise_screen.dart — Exercise Hub
// Tabs: Log Exercise, Steps, Breathing, Library, History
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/step_tracking_service.dart';
import '../widgets/common_widgets.dart';

class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({super.key});

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiService();

  Map<String, dynamic>? _historyData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getExerciseHistory(days: 7);
    if (resp.success) setState(() => _historyData = resp.data);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Exercise', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.exercise,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.exercise,
          tabs: const [
            Tab(text: '🏋️ Log'),
            Tab(text: '👟 Steps'),
            Tab(text: '🫁 Breathing'),
            Tab(text: '📚 Library'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LogExerciseTab(historyData: _historyData, loading: _loading, onSaved: _load),
          _StepsTab(onSaved: _load),
          const _BreathingTab(),
          const _LibraryTab(),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }
}

// ════════════════════════════════════════════════════════════
// LOG EXERCISE TAB
// ════════════════════════════════════════════════════════════
class _LogExerciseTab extends StatefulWidget {
  final Map<String, dynamic>? historyData;
  final bool loading;
  final VoidCallback onSaved;
  const _LogExerciseTab({required this.historyData, required this.loading, required this.onSaved});

  @override
  State<_LogExerciseTab> createState() => _LogExerciseTabState();
}

class _LogExerciseTabState extends State<_LogExerciseTab> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  String _type = 'cardio';
  String _intensity = 'moderate';
  bool _saving = false;

  final _types = {'cardio': '🏃 Cardio', 'strength': '💪 Strength', 'yoga': '🧘 Yoga', 'flexibility': '🤸 Stretching', 'sports': '⚽ Sports', 'other': '🏋️ Other'};

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final resp = await _api.logExercise(
      exerciseName: _nameCtrl.text.trim(), exerciseType: _type,
      durationMinutes: int.tryParse(_durationCtrl.text), intensity: _intensity,
    );
    setState(() => _saving = false);
    if (resp.success) {
      _nameCtrl.clear(); _durationCtrl.clear();
      widget.onSaved();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.historyData;
    return RefreshIndicator(
      onRefresh: () async => widget.onSaved(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data != null)
              Row(
                children: [
                  Expanded(child: StatCard(label: 'Today', value: '${data['today_mins'] ?? 0} min', sublabel: 'Target: ${data['target_mins'] ?? 30} min', emoji: '🕐', color: AppColors.exercise)),
                  const SizedBox(width: 12),
                  Expanded(child: StatCard(label: 'Calories', value: '${data['total_calories'] ?? 0}', sublabel: 'This week', emoji: '🔥', color: AppColors.danger)),
                ],
              ),
            const SizedBox(height: 16),
            SectionCard(
              title: '➕ Log Exercise',
              child: Column(
                children: [
                  TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Exercise Name', hintText: 'e.g. Morning Walk')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _type, decoration: const InputDecoration(labelText: 'Type'),
                    items: _types.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setState(() => _type = v ?? 'cardio'),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _durationCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duration (mins)', hintText: '30')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _intensity, decoration: const InputDecoration(labelText: 'Intensity'),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Low — Easy')),
                      DropdownMenuItem(value: 'moderate', child: Text('Moderate — Brisk')),
                      DropdownMenuItem(value: 'high', child: Text('High — Running')),
                      DropdownMenuItem(value: 'very_high', child: Text('Very High — HIIT')),
                    ],
                    onChanged: (v) => setState(() => _intensity = v ?? 'moderate'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.exercise.withOpacity(0.15), foregroundColor: AppColors.exercise),
                      child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('🏋️ Log Exercise'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (data != null && (data['logs'] as List).isNotEmpty)
              SectionCard(
                title: '📋 Recent Sessions', padding: EdgeInsets.zero,
                child: Column(
                  children: (data['logs'] as List).map<Widget>((l) {
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      leading: Text(_types[l['exercise_type']]?.split(' ').first ?? '🏋️', style: const TextStyle(fontSize: 20)),
                      title: Text(l['exercise_name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text('${l['duration_minutes'] ?? 0} min · ${l['log_date']}', style: const TextStyle(fontSize: 11)),
                      trailing: Text('🔥 ${l['calories_burned'] ?? 0}', style: const TextStyle(fontSize: 12, color: AppColors.exercise)),
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// STEPS TAB — Live tracking via phone pedometer sensor
// ════════════════════════════════════════════════════════════
class _StepsTab extends StatefulWidget {
  final VoidCallback onSaved;
  const _StepsTab({required this.onSaved});

  @override
  State<_StepsTab> createState() => _StepsTabState();
}

class _StepsTabState extends State<_StepsTab> {
  final _stepService = StepTrackingService();

  @override
  void initState() {
    super.initState();
    _init();
    _stepService.addListener(_onStepUpdate);
  }

  Future<void> _init() async {
    await _stepService.init(dailyGoal: 8000);
    if (!_stepService.hasPermission) {
      final granted = await _stepService.requestPermission();
      if (granted == true) {await _stepService.startTracking();}
    }
  }

  void _onStepUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stepService.removeListener(_onStepUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps    = _stepService.todaySteps;
    final goal     = _stepService.dailyGoal;
    final pct      = _stepService.progressPct;
    final calories = _stepService.estimatedCalories;
    final dist     = _stepService.estimatedDistanceKm;
    final tracking = _stepService.isTracking;
    final status   = _stepService.status;

    return RefreshIndicator(
      onRefresh: () async {
        await _stepService.syncNow();
        widget.onSaved();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Live counter card ─────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: tracking
                      ? [const Color(0xFF1D4ED8), const Color(0xFF3B82F6)]
                      : [const Color(0xFF334155), const Color(0xFF475569)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      ProgressRing(percent: pct, centerText: '$steps', label: 'steps', color: Colors.white, radius: 56),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: tracking ? Colors.greenAccent : Colors.grey)),
                              const SizedBox(width: 6),
                              Text(
                                tracking ? '🔴 LIVE' : (status == 'no_permission' ? 'No Permission' : 'Stopped'),
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: tracking ? Colors.greenAccent : Colors.white70),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            Text('$goal steps goal', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8))),
                            const SizedBox(height: 4),
                            Text('$dist km · $calories cal', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
                            if (_stepService.goalAchieved) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(100)),
                                child: const Text('🏆 Goal Achieved!', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  // ── Progress bar ──────────────────────────────
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: LinearProgressIndicator(
                      value: pct, minHeight: 8,
                      backgroundColor: Colors.white.withOpacity(0.15),
                      color: _stepService.goalAchieved ? Colors.greenAccent : Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Permission / Status banner ─────────────────────
            if (status == 'no_permission')
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.warning.withOpacity(0.25))),
                child: Row(children: [
                  const Text('⚠️', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Activity permission needed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const Text('Required to count steps using your phone\'s sensor.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ]),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final granted = await _stepService.requestPermission();
                      if (granted) await _stepService.startTracking();
                    },
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    child: const Text('Allow', style: TextStyle(fontSize: 12)),
                  ),
                ]),
              )
            else if (status == 'unavailable')
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.info.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                child: const Row(children: [
                  Text('ℹ️', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 10),
                  Expanded(child: Text('Pedometer not available on this device. Use manual entry below.', style: TextStyle(fontSize: 13, color: AppColors.textMuted))),
                ]),
              ),

            const SizedBox(height: 16),

            // ── Control buttons ───────────────────────────────
            if (_stepService.hasPermission && status != 'unavailable')
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: tracking ? () => _stepService.stopTracking() : () => _stepService.startTracking(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tracking ? AppColors.danger.withOpacity(0.12) : AppColors.info.withOpacity(0.12),
                        foregroundColor: tracking ? AppColors.danger : AppColors.info,
                        elevation: 0,
                      ),
                      child: Text(tracking ? '⏹ Stop Tracking' : '▶ Start Tracking'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () async { await _stepService.syncNow(); widget.onSaved(); },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.sage.withOpacity(0.12), foregroundColor: AppColors.sage, elevation: 0),
                    child: const Text('☁️ Sync'),
                  ),
                ],
              ),

            const SizedBox(height: 20),

            // ── Manual entry fallback ─────────────────────────
            SectionCard(
              title: '✏️ Manual Step Entry',
              child: Column(
                children: [
                  const Text('If auto-tracking isn\'t available, enter steps manually:', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 10),
                  _ManualStepsForm(onSaved: widget.onSaved, currentSteps: steps),
                ],
              ),
            ),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// BREATHING TAB
// ════════════════════════════════════════════════════════════
class _BreathingTab extends StatefulWidget {
  const _BreathingTab();

  @override
  State<_BreathingTab> createState() => _BreathingTabState();
}

class _BreathingTabState extends State<_BreathingTab> {
  final _api = ApiService();
  List<dynamic> _exercises = [];
  bool _loading = true;
  String? _activeId;
  int _phaseIdx = 0;
  int _round = 0;
  int _countdown = 0;
  Timer? _timer;
  Map<String, dynamic>? _activeEx;

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
    final resp = await _api.getBreathingConfig();
    if (resp.success) setState(() => _exercises = resp.data['exercises'] ?? []);
    setState(() => _loading = false);
  }

  void _start(Map<String, dynamic> ex) {
    setState(() {
      _activeId = ex['id'];
      _activeEx = ex;
      _phaseIdx = 0;
      _round = 0;
      _countdown = ex['phases'][0]['duration'];
    });
    _runPhase();
  }

  void _runPhase() {
    _timer?.cancel();
    final phases = _activeEx!['phases'] as List;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          _phaseIdx++;
          if (_phaseIdx >= phases.length) {
            _phaseIdx = 0;
            _round++;
            if (_round >= (_activeEx!['recommended_rounds'] as int? ?? 4)) {
              timer.cancel();
              _onComplete();
              return;
            }
          }
          _countdown = phases[_phaseIdx]['duration'];
          NotificationService().playSound('gentle');
        }
      });
    });
  }

  Future<void> _onComplete() async {
    NotificationService().playSound('gentle');
    final totalSecs = (_activeEx!['phases'] as List).fold<int>(0, (a, p) => a + (p['duration'] as int)) * (_activeEx!['recommended_rounds'] as int? ?? 4);
    await _api.logBreathing(_activeId!, _activeEx!['recommended_rounds'] as int? ?? 4, totalSecs);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎉 Breathing session complete!'), backgroundColor: AppColors.success));
      setState(() => _activeId = null);
    }
  }

  void _stop() {
    _timer?.cancel();
    setState(() => _activeId = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();

    if (_activeId != null) {
      final phase = _activeEx!['phases'][_phaseIdx];
      final color = Color(int.parse((phase['color'] as String).replaceFirst('#', '0xFF')));
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_activeEx!['name'], style: const TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Round ${_round + 1} of ${_activeEx!['recommended_rounds']}', style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 30),
            Container(
              width: 220, height: 220,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.15), border: Border.all(color: color, width: 4)),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(phase['name'], style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                    Text('$_countdown', style: const TextStyle(fontFamily: 'monospace', fontSize: 56, fontWeight: FontWeight.w600)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(phase['instruction'], style: const TextStyle(fontSize: 12, color: AppColors.textMuted), textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(onPressed: _stop, style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger.withOpacity(0.15), foregroundColor: AppColors.danger), child: const Text('⏹ Stop')),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _exercises.length,
      itemBuilder: (context, i) {
        final ex = _exercises[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ex['name'], style: const TextStyle(fontFamily: 'Fraunces', fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(ex['desc'], style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: (ex['benefits'] as List).map<Widget>((b) => PillChip(text: b, color: AppColors.sage)).toList(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(onPressed: () => _start(ex), child: const Text('▶ Start Session')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════
// LIBRARY TAB
// ════════════════════════════════════════════════════════════
class _LibraryTab extends StatefulWidget {
  const _LibraryTab();

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab> {
  final _api = ApiService();
  List<dynamic> _exercises = [];
  bool _loading = true;
  bool _bpSafeOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getExerciseLibrary(bpSafe: _bpSafeOnly);
    if (resp.success) setState(() => _exercises = resp.data['exercises'] ?? []);
    setState(() => _loading = false);
  }

  final _icons = {'cardio': '🏃', 'strength': '💪', 'yoga': '🧘', 'flexibility': '🤸', 'breathing': '🫁', 'sports': '⚽'};

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilterChip(
            label: const Text('❤️ BP-Safe Only'),
            selected: _bpSafeOnly,
            onSelected: (v) {
              setState(() => _bpSafeOnly = v);
              _load();
            },
            selectedColor: AppColors.success.withOpacity(0.15),
          ),
        ),
        Expanded(
          child: _loading
              ? const LoadingView()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _exercises.length,
                  itemBuilder: (context, i) {
                    final ex = _exercises[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: AppColors.exercise.withOpacity(0.1), child: Text(_icons[ex['category']] ?? '🏋️')),
                        title: Text(ex['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(ex['description'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                        trailing: ex['bp_safe'] == true ? const Text('❤️', style: TextStyle(fontSize: 16)) : null,
                        onTap: () => _showDetail(ex),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showDetail(Map<String, dynamic> ex) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ex['name'], style: const TextStyle(fontFamily: 'Fraunces', fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                PillChip(text: ex['category'], color: AppColors.exercise),
                PillChip(text: ex['difficulty'], color: AppColors.violet),
                if (ex['duration_mins'] != null) PillChip(text: '${ex['duration_mins']} min', color: AppColors.gold),
              ]),
              const SizedBox(height: 16),
              Text(ex['description'] ?? '', style: const TextStyle(fontSize: 14, height: 1.5)),
              const SizedBox(height: 16),
              const Text('Instructions', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 6),
              Text(ex['instructions'] ?? '', style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textMuted)),
              const SizedBox(height: 16),
              const Text('Benefits', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 6),
              Text(ex['benefits'] ?? '', style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// MANUAL STEPS FORM — fallback if pedometer not available
// ════════════════════════════════════════════════════════════
class _ManualStepsForm extends StatefulWidget {
  final VoidCallback onSaved;
  final int currentSteps;
  const _ManualStepsForm({required this.onSaved, required this.currentSteps});

  @override
  State<_ManualStepsForm> createState() => _ManualStepsFormState();
}

class _ManualStepsFormState extends State<_ManualStepsForm> {
  final _api = ApiService();
  final _stepsCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _stepsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final steps = int.tryParse(_stepsCtrl.text);
    if (steps == null || steps < 0) return;
    setState(() => _saving = true);
    final resp = await _api.addSteps(steps);
    setState(() => _saving = false);
    if (resp.success) {
      _stepsCtrl.clear();
      // Also update live service so UI is consistent
      StepTrackingService().syncNow();
      widget.onSaved();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('👟 ${resp.message}'), backgroundColor: AppColors.info));
    }
  }

  @override
  Widget build(BuildContext context) {
    _stepsCtrl.text = widget.currentSteps > 0 ? '${widget.currentSteps}' : '';
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _stepsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Step Count', hintText: '8000'),
            onTap: () => _stepsCtrl.clear(),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.info.withOpacity(0.12),
            foregroundColor: AppColors.info, elevation: 0,
          ),
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('👟 Save'),
        ),
      ],
    );
  }
}