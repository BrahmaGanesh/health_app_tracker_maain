// lib/screens/weight_tracker_screen.dart — Offline-first + Dark Mode
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../services/sync_service.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart' hide AppBottomNav;
import 'bp_tracker_screen.dart' show _CardBox, _SyncBadge, _LDot;

class WeightTrackerScreen extends StatefulWidget {
  const WeightTrackerScreen({super.key});
  @override State<WeightTrackerScreen> createState() => _WeightTrackerScreenState();
}

class _WeightTrackerScreenState extends State<WeightTrackerScreen> {
  final _sync      = SyncService();
  final _api       = ApiService();
  final _weightCtrl = TextEditingController();
  final _notesCtrl  = TextEditingController();

  List<dynamic> _readings = [];
  double? _bmi, _targetWeight, _change;
  String? _bmiStatus;
  int _progressPct = 0;
  bool _loading = true, _saving = false;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _weightCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getWeight(days: 60);
    if (resp.success) {
      setState(() {
        _readings    = resp.data['readings'] ?? [];
        _bmi         = resp.data['bmi']?.toDouble();
        _bmiStatus   = resp.data['bmi_status'];
        _change      = resp.data['change']?.toDouble();
        _targetWeight= resp.data['target_weight']?.toDouble();
        _progressPct = resp.data['progress_pct'] ?? 0;
        _loading     = false;
      });
    } else { setState(() => _loading = false); }
  }

  Future<void> _save() async {
    final w = double.tryParse(_weightCtrl.text);
    if (w == null || w < 20 || w > 300) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid weight (20–300 kg)'))); return; }
    setState(() => _saving = true);
    await _sync.saveMetricOffline(type: 'weight', value1: w, notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim());
    setState(() => _saving = false);
    _weightCtrl.clear(); _notesCtrl.clear();
    FocusScope.of(context).unfocus();
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_sync.isOnline ? '✅ Saved & synced' : '💾 Saved offline'), backgroundColor: AppColors.success));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card   = isDark ? AppColors.cardDark : Colors.white;
    final brd    = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp     = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm     = isDark ? AppColors.textMutedDark : AppColors.textMuted;
    final latest = _readings.isNotEmpty ? _readings.first : null;
    final change = _change ?? 0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Weight Tracker', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [SyncBadge(_sync.isOnline), IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: _loading ? const LoadingView() : RefreshIndicator(
        onRefresh: _load, color: AppColors.violet,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Hero
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.violet, Color(0xFF6D28D9)]),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: AppColors.violet.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))],
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('CURRENT WEIGHT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.white70)),
                  const SizedBox(height: 6),
                  Text(latest != null ? '${latest['value_1']} kg' : '—',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 42, fontWeight: FontWeight.w700, color: Colors.white, height: 1)),
                  Text(latest?['recorded_date'] ?? 'No data', style: const TextStyle(fontSize: 12, color: Colors.white60)),
                  const SizedBox(height: 8),
                  if (change != 0) Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(100)),
                    child: Text('${change > 0 ? '+' : ''}${change.toStringAsFixed(1)} kg since start',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: change <= 0 ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5)))),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_bmi?.toString() ?? '—', style: const TextStyle(fontFamily: 'monospace', fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
                  const Text('BMI', style: TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(_bmiStatus ?? '', style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
                ]),
              ]),
            ),
            const SizedBox(height: 16),

            // Log form
            CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('➕ Log Weight', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
              const SizedBox(height: 14),
              TextField(controller: _weightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Weight (kg)', hintText: '70.5', suffixText: 'kg')),
              const SizedBox(height: 10),
              TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'Morning weigh-in')),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.violet, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_sync.isOnline ? '⚖️ Save & Sync' : '💾 Save Offline', style: const TextStyle(fontWeight: FontWeight.bold)),
              )),
            ])),
            const SizedBox(height: 16),

            // Goal progress
            if (_targetWeight != null)
              CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('🎯 Goal Progress', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Target: ${_targetWeight}kg', style: TextStyle(fontSize: 13, color: tm)),
                  Text('$_progressPct%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.violet)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(100), child: LinearProgressIndicator(
                  value: _progressPct / 100, minHeight: 10,
                  backgroundColor: AppColors.violet.withOpacity(0.12), color: AppColors.violet)),
              ])),
            const SizedBox(height: 16),

            // Chart
            if (_readings.length >= 3)
              CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('📈 Trend', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
                const SizedBox(height: 14),
                SizedBox(height: 170, child: _buildChart(isDark)),
              ])),
            const SizedBox(height: 16),

            // History
            CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('📋 History', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
              const SizedBox(height: 10),
              if (_readings.isEmpty)
                Center(child: Text('No readings yet.', style: TextStyle(color: tm)))
              else
                ..._readings.take(15).map((r) => ListTile(contentPadding: EdgeInsets.zero, dense: true,
                  leading: const Text('⚖️', style: TextStyle(fontSize: 20)),
                  title: Text('${r['value_1']} kg', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.violet)),
                  trailing: Text(r['recorded_date'] ?? '', style: TextStyle(fontSize: 12, color: tm)),
                )),
            ])),
            const SizedBox(height: 80),
          ]),
        ),
      ),
    );
  }

  Widget _buildChart(bool isDark) {
    final rev = _readings.reversed.toList().take(30).toList();
    final spots = <FlSpot>[];
    for (int i = 0; i < rev.length; i++) spots.add(FlSpot(i.toDouble(), (rev[i]['value_1'] ?? 0).toDouble()));
    return LineChart(LineChartData(
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: isDark ? Colors.white10 : Colors.grey.shade100, strokeWidth: 1)),
      titlesData: const FlTitlesData(topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36))),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(spots: spots, isCurved: true, color: AppColors.violet, barWidth: 3, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: AppColors.violet.withOpacity(0.08))),
        if (_targetWeight != null) LineChartBarData(spots: List.generate(rev.length, (i) => FlSpot(i.toDouble(), _targetWeight!)), isCurved: false, color: AppColors.mint, barWidth: 1.5, dashArray: [6, 4], dotData: const FlDotData(show: false)),
      ],
    ));
  }
}