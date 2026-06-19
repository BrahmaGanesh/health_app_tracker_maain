// ============================================================
// lib/screens/sleep_tracker_screen.dart — Sleep Tracker
// Logs sleep/wake time, quality rating, 14-day history chart
// ============================================================

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

class SleepTrackerScreen extends StatefulWidget {
  const SleepTrackerScreen({super.key});

  @override
  State<SleepTrackerScreen> createState() => _SleepTrackerScreenState();
}

class _SleepTrackerScreenState extends State<SleepTrackerScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _saving = false;
  List<dynamic> _logs = [];
  double? _avgHours, _targetHours;
  double? _avgQuality;

  TimeOfDay _sleepTime = const TimeOfDay(hour: 22, minute: 30);
  TimeOfDay _wakeTime = const TimeOfDay(hour: 6, minute: 0);
  int _quality = 4;
  int _interruptions = 0;
  String _mood = 'normal';

  final _moods = {'refreshed': '😄 Refreshed', 'normal': '🙂 Normal', 'tired': '😪 Tired', 'groggy': '😵 Groggy'};
  final _qualityEmojis = {1: '😣', 2: '😔', 3: '😐', 4: '🙂', 5: '😊'};
  final _qualityLabels = {1: 'Very Poor', 2: 'Poor', 3: 'Fair', 4: 'Good', 5: 'Excellent'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getSleep(days: 14);
    if (resp.success) {
      setState(() {
        _logs = resp.data['logs'] ?? [];
        _avgHours = resp.data['avg_hours']?.toDouble();
        _avgQuality = resp.data['avg_quality']?.toDouble();
        _targetHours = resp.data['target_hours']?.toDouble() ?? 7.5;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final sleepStr = '${_sleepTime.hour.toString().padLeft(2, '0')}:${_sleepTime.minute.toString().padLeft(2, '0')}';
    final wakeStr = '${_wakeTime.hour.toString().padLeft(2, '0')}:${_wakeTime.minute.toString().padLeft(2, '0')}';

    final resp = await _api.addSleep(
      sleepTime: sleepStr, wakeTime: wakeStr, quality: _quality,
      interruptions: _interruptions, moodOnWake: _mood,
    );
    setState(() => _saving = false);

    if (resp.success) {
      await _load();
      if (mounted) {
        final hrs = resp.data['duration_hours'];
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('😴 Sleep logged — ${hrs}hrs'), backgroundColor: AppColors.sleep));
      }
    }
  }

  Future<void> _pickTime(bool isSleep) async {
    final picked = await showTimePicker(context: context, initialTime: isSleep ? _sleepTime : _wakeTime);
    if (picked != null) {
      setState(() {
        if (isSleep) _sleepTime = picked;
        else _wakeTime = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: const Text('Sleep Tracker', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold))),
      body: _loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.sleep,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatsRow(),
                    const SizedBox(height: 16),
                    _buildLogForm(),
                    const SizedBox(height: 16),
                    if (_logs.isNotEmpty) _buildChart(),
                    const SizedBox(height: 16),
                    _buildHistory(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: StatCard(label: '14-Day Avg', value: _avgHours != null ? '${_avgHours}h' : '—',
              sublabel: 'Target: ${_targetHours}h', emoji: '😴', color: AppColors.sleep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(label: 'Avg Quality', value: _avgQuality != null ? '$_avgQuality/5' : '—',
              sublabel: '${_logs.length} nights logged', emoji: '⭐', color: AppColors.gold),
        ),
      ],
    );
  }

  Widget _buildLogForm() {
    return SectionCard(
      title: "➕ Log Last Night's Sleep",
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickTime(true),
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Sleep Time'),
                    child: Text(_sleepTime.format(context)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickTime(false),
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Wake Time'),
                    child: Text(_wakeTime.format(context)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Align(alignment: Alignment.centerLeft, child: Text('Sleep Quality', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
          const SizedBox(height: 8),
          Row(
            children: [1, 2, 3, 4, 5].map((v) {
              final selected = v == _quality;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _quality = v),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.sleep.withOpacity(0.15) : Colors.grey.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? AppColors.sleep : Colors.transparent, width: 1.5),
                    ),
                    child: Column(
                      children: [
                        Text(_qualityEmojis[v]!, style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 2),
                        Text(_qualityLabels[v]!, style: TextStyle(fontSize: 9, color: selected ? AppColors.sleep : AppColors.textMuted), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Interruptions'),
                  onChanged: (v) => _interruptions = int.tryParse(v) ?? 0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _mood,
                  decoration: const InputDecoration(labelText: 'Mood on Wake'),
                  items: _moods.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (v) => setState(() => _mood = v ?? 'normal'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.sleep.withOpacity(0.15), foregroundColor: AppColors.sleep),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.sleep))
                  : const Text('😴 Save Sleep Log'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final reversed = _logs.reversed.toList();
    final bars = <BarChartGroupData>[];
    for (int i = 0; i < reversed.length; i++) {
      final hrs = (reversed[i]['duration_hours'] ?? 0).toDouble();
      bars.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: hrs, color: hrs >= (_targetHours ?? 7.5) ? AppColors.sleep : AppColors.warning, width: 12, borderRadius: BorderRadius.circular(4)),
      ]));
    }

    return SectionCard(
      title: '📈 14-Day Pattern',
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            maxY: 12,
            titlesData: const FlTitlesData(
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
            ),
            barGroups: bars,
          ),
        ),
      ),
    );
  }

  Widget _buildHistory() {
    return SectionCard(
      title: '📋 History',
      padding: EdgeInsets.zero,
      child: _logs.isEmpty
          ? const Padding(padding: EdgeInsets.all(16), child: Text('No sleep logs yet.', style: TextStyle(color: AppColors.textMuted)))
          : Column(
              children: _logs.map<Widget>((l) {
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Text(_qualityEmojis[l['quality']] ?? '😴', style: const TextStyle(fontSize: 22)),
                  title: Text('${l['duration_hours'] ?? '—'}h · ${l['quality_label'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text('${l['log_date']} · ${l['sleep_time'] ?? ''} → ${l['wake_time'] ?? ''}', style: const TextStyle(fontSize: 11)),
                );
              }).toList(),
            ),
    );
  }
}