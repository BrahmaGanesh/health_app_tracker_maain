// lib/screens/sleep_tracker_screen.dart — Offline-first + Dark Mode
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../services/sync_service.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import 'package:healthtrack/widgets/common_widgets.dart' hide AppBottomNav;
import 'bp_tracker_screen.dart' show _CardBox, _SyncBadge;

class SleepTrackerScreen extends StatefulWidget {
  const SleepTrackerScreen({super.key});
  @override State<SleepTrackerScreen> createState() => _SleepTrackerScreenState();
}

class _SleepTrackerScreenState extends State<SleepTrackerScreen> {
  final _sync = SyncService();
  final _api  = ApiService();

  List<dynamic> _logs = [];
  double? _avgHours, _targetHours;
  double? _avgQuality;
  bool _loading = true, _saving = false;

  TimeOfDay _sleepTime = const TimeOfDay(hour: 22, minute: 30);
  TimeOfDay _wakeTime  = const TimeOfDay(hour: 6,  minute: 0);
  int    _quality      = 4;
  int    _interruptions= 0;
  String _mood         = 'normal';

  static const _moods   = {'refreshed':'😄 Refreshed','normal':'🙂 Normal','tired':'😪 Tired','groggy':'😵 Groggy'};
  static const _qEmoji  = {1:'😣',2:'😔',3:'😐',4:'🙂',5:'😊'};
  static const _qLabel  = {1:'Very Poor',2:'Poor',3:'Fair',4:'Good',5:'Excellent'};

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getSleep(days: 14);
    if (resp.success) {
      setState(() {
        _logs        = resp.data['logs'] ?? [];
        _avgHours    = resp.data['avg_hours']?.toDouble();
        _avgQuality  = resp.data['avg_quality']?.toDouble();
        _targetHours = resp.data['target_hours']?.toDouble() ?? 7.5;
        _loading     = false;
      });
    } else { setState(() => _loading = false); }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final sleepStr = '${_sleepTime.hour.toString().padLeft(2,'0')}:${_sleepTime.minute.toString().padLeft(2,'0')}';
    final wakeStr  = '${_wakeTime.hour.toString().padLeft(2,'0')}:${_wakeTime.minute.toString().padLeft(2,'0')}';

    // Calculate hours
    int sleepMins = _sleepTime.hour * 60 + _sleepTime.minute;
    int wakeMins  = _wakeTime.hour  * 60 + _wakeTime.minute;
    if (wakeMins <= sleepMins) wakeMins += 24 * 60;
    final durationHours = (wakeMins - sleepMins) / 60.0;

    await _sync.saveMetricOffline(type: 'sleep', value1: durationHours, value2: _quality.toDouble());
    setState(() => _saving = false);
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_sync.isOnline ? '😴 ${durationHours.toStringAsFixed(1)}h logged & synced' : '💾 Sleep saved offline'),
        backgroundColor: AppColors.sleep));
  }

  Future<void> _pickTime(bool isSleep) async {
    final t = await showTimePicker(context: context, initialTime: isSleep ? _sleepTime : _wakeTime);
    if (t != null) setState(() => isSleep ? _sleepTime = t : _wakeTime = t);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card   = isDark ? AppColors.cardDark : Colors.white;
    final brd    = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp     = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm     = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Sleep Tracker', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [SyncBadge(_sync.isOnline), IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: _loading ? const LoadingView() : RefreshIndicator(
        onRefresh: _load, color: AppColors.sleep,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Hero
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF4C1D95), AppColors.sleep], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: AppColors.sleep.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))],
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('14-DAY AVERAGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.white70)),
                  const SizedBox(height: 6),
                  Text(_avgHours != null ? '${_avgHours!.toStringAsFixed(1)}h' : '—',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 42, fontWeight: FontWeight.w700, color: Colors.white, height: 1)),
                  Text('Target: ${_targetHours?.toStringAsFixed(1)}h', style: const TextStyle(fontSize: 12, color: Colors.white60)),
                  const SizedBox(height: 8),
                  if (_avgQuality != null) Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(100)),
                    child: Text('Avg quality: ${_avgQuality!.toStringAsFixed(1)}/5', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
                ])),
                const Text('😴', style: TextStyle(fontSize: 56)),
              ]),
            ),
            const SizedBox(height: 16),

            // Log form
            CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("➕ Log Last Night's Sleep", style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => _pickTime(true),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(color: isDark ? const Color(0xFF1A2E45) : Colors.grey.shade50, borderRadius: BorderRadius.circular(14), border: Border.all(color: brd)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Bedtime', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tm, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text(_sleepTime.format(context), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.sleep)),
                    ])),
                )),
                const SizedBox(width: 10),
                Expanded(child: GestureDetector(
                  onTap: () => _pickTime(false),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(color: isDark ? const Color(0xFF1A2E45) : Colors.grey.shade50, borderRadius: BorderRadius.circular(14), border: Border.all(color: brd)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Wake Time', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tm, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text(_wakeTime.format(context), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.gold)),
                    ])),
                )),
              ]),
              const SizedBox(height: 16),
              Text('Sleep Quality', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tm, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Row(children: [1,2,3,4,5].map((v) {
                final sel = v == _quality;
                return Expanded(child: GestureDetector(
                  onTap: () => setState(() => _quality = v),
                  child: AnimatedContainer(duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.sleep.withOpacity(isDark ? 0.25 : 0.12) : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade50),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sel ? AppColors.sleep : brd, width: sel ? 2 : 1)),
                    child: Column(children: [
                      Text(_qEmoji[v]!, style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 2),
                      Text(_qLabel[v]!, style: TextStyle(fontSize: 9, color: sel ? AppColors.sleep : tm, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                    ]),
                  ),
                ));
              }).toList()),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(value: _mood, decoration: const InputDecoration(labelText: 'Mood on Wake'),
                  items: _moods.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (v) => setState(() => _mood = v ?? 'normal'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Interruptions', hintText: '0'),
                    onChanged: (v) => _interruptions = int.tryParse(v) ?? 0)),
              ]),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.sleep, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_sync.isOnline ? '😴 Save Sleep Log' : '💾 Save Offline', style: const TextStyle(fontWeight: FontWeight.bold)),
              )),
            ])),
            const SizedBox(height: 16),

            // 14-day chart
            if (_logs.isNotEmpty)
              CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('📊 14-Day Pattern', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
                const SizedBox(height: 14),
                SizedBox(height: 160, child: BarChart(BarChartData(
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  maxY: 12,
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28,
                        getTitlesWidget: (v, _) => Text('${v.toInt()}h', style: TextStyle(fontSize: 9, color: tm))))),
                  barGroups: _logs.reversed.toList().asMap().entries.map((e) {
                    final hrs = (e.value['duration_hours'] ?? 0).toDouble();
                    return BarChartGroupData(x: e.key, barRods: [
                      BarChartRodData(toY: hrs, color: hrs >= (_targetHours ?? 7.5) ? AppColors.sleep : AppColors.warning,
                          width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(5))),
                    ]);
                  }).toList(),
                ))),
              ])),
            const SizedBox(height: 16),

            // History
            CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('📋 History', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
              const SizedBox(height: 10),
              ..._logs.map((l) => ListTile(contentPadding: EdgeInsets.zero, dense: true,
                leading: Text(_qEmoji[l['quality']] ?? '😴', style: const TextStyle(fontSize: 22)),
                title: Text('${l['duration_hours'] ?? '—'}h · ${l['quality_label'] ?? ''}',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: tp)),
                subtitle: Text('${l['log_date'] ?? ''} · ${l['sleep_time'] ?? ''} → ${l['wake_time'] ?? ''}',
                    style: TextStyle(fontSize: 11, color: tm)),
              )),
            ])),
            const SizedBox(height: 80),
          ]),
        ),
      ),
    );
  }
}