// ============================================================
// lib/screens/weight_tracker_screen.dart — Weight Tracker
// Logs weight with exact timestamp, shows BMI, trend chart, goal progress
// ============================================================

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

class WeightTrackerScreen extends StatefulWidget {
  const WeightTrackerScreen({super.key});

  @override
  State<WeightTrackerScreen> createState() => _WeightTrackerScreenState();
}

class _WeightTrackerScreenState extends State<WeightTrackerScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _saving = false;
  List<dynamic> _readings = [];
  Map<String, dynamic>? _latest;
  double? _change;
  double? _targetWeight;
  int _progressPct = 0;
  double? _bmi;
  String? _bmiStatus;

  final _weightCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getWeight(days: 60);
    if (resp.success) {
      setState(() {
        _readings = resp.data['readings'] ?? [];
        _latest = resp.data['latest'];
        _change = resp.data['change']?.toDouble();
        _targetWeight = resp.data['target_weight']?.toDouble();
        _progressPct = resp.data['progress_pct'] ?? 0;
        _bmi = resp.data['bmi']?.toDouble();
        _bmiStatus = resp.data['bmi_status'];
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final w = double.tryParse(_weightCtrl.text);
    if (w == null || w < 20 || w > 300) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid weight (20-300 kg)')));
      return;
    }

    setState(() => _saving = true);
    final resp = await _api.addWeight(w, notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim());
    setState(() => _saving = false);

    if (resp.success) {
      _weightCtrl.clear(); _notesCtrl.clear();
      FocusScope.of(context).unfocus();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: const Text('Weight Tracker', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold))),
      body: _loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.violet,
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
                    if (_targetWeight != null) _buildGoalProgress(),
                    const SizedBox(height: 16),
                    if (_readings.length >= 2) _buildChart(),
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
          child: StatCard(
            label: 'Current', value: _latest != null ? '${_latest!['value_1']} kg' : '—',
            sublabel: _latest != null ? _latest!['recorded_date'] : 'No data', emoji: '⚖️', color: AppColors.violet,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            label: 'BMI', value: _bmi != null ? '$_bmi' : '—',
            sublabel: _bmiStatus ?? '', emoji: '📏', color: AppColors.sage,
          ),
        ),
      ],
    );
  }

  Widget _buildLogForm() {
    return SectionCard(
      title: '➕ Log Weight',
      child: Column(
        children: [
          TextField(controller: _weightCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Weight', hintText: '70.5', suffixText: 'kg')),
          const SizedBox(height: 12),
          TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'e.g. Morning weigh-in')),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.violet.withOpacity(0.15), foregroundColor: AppColors.violet),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.violet))
                  : const Text('⚖️ Save Weight (logs current time)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalProgress() {
    final change = _change ?? 0;
    final changeText = change == 0 ? 'No change' : (change > 0 ? '+${change.toStringAsFixed(1)} kg' : '${change.toStringAsFixed(1)} kg');
    final changeColor = change <= 0 ? AppColors.success : AppColors.warning;

    return SectionCard(
      title: '🎯 Goal Progress',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Target: ${_targetWeight}kg', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              Text(changeText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: changeColor)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(value: _progressPct / 100, minHeight: 10, backgroundColor: AppColors.violet.withOpacity(0.12), color: AppColors.violet),
          ),
          const SizedBox(height: 6),
          Text('$_progressPct% to goal', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final spots = <FlSpot>[];
    for (int i = 0; i < _readings.length; i++) {
      spots.add(FlSpot(i.toDouble(), (_readings[i]['value_1'] ?? 0).toDouble()));
    }

    return SectionCard(
      title: '📈 Trend',
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            titlesData: const FlTitlesData(
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots, isCurved: true, color: AppColors.violet, barWidth: 3,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, color: AppColors.violet.withOpacity(0.1)),
              ),
              if (_targetWeight != null)
                LineChartBarData(
                  spots: List.generate(_readings.length, (i) => FlSpot(i.toDouble(), _targetWeight!)),
                  isCurved: false, color: AppColors.mint, barWidth: 1.5, dashArray: [6, 4],
                  dotData: const FlDotData(show: false),
                ),
            ],
          ),
        ),
      ),
    );
  }
}