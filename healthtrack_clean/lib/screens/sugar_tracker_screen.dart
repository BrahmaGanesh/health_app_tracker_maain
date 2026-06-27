// lib/screens/sugar_tracker_screen.dart — Blood Sugar Tracker
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart' hide AppBottomNav;

class SugarTrackerScreen extends StatefulWidget {
  const SugarTrackerScreen({super.key});
  @override
  State<SugarTrackerScreen> createState() => _SugarTrackerScreenState();
}

class _SugarTrackerScreenState extends State<SugarTrackerScreen> {
  final _api = ApiService();
  bool _loading = true, _saving = false;
  List<dynamic> _readings = [];
  Map<String, dynamic>? _latest;
  String _status = 'No Reading';

  final _fastingCtrl   = TextEditingController();
  final _postMealCtrl  = TextEditingController();
  final _notesCtrl     = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _fastingCtrl.dispose(); _postMealCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getSugar(days: 30);
    if (resp.success) {
      setState(() {
        _readings = resp.data['readings'] ?? [];
        _latest   = resp.data['latest'];
        _status   = resp.data['status'] ?? 'No Reading';
        _loading  = false;
      });
    } else { setState(() => _loading = false); }
  }

  Future<void> _save() async {
    final fasting  = double.tryParse(_fastingCtrl.text);
    final postMeal = double.tryParse(_postMealCtrl.text);
    if (fasting == null && postMeal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter at least one value')));
      return;
    }
    setState(() => _saving = true);
    final resp = await _api.addSugar(
        fasting: fasting, postMeal: postMeal,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim());
    setState(() => _saving = false);
    if (resp.success) {
      _fastingCtrl.clear(); _postMealCtrl.clear(); _notesCtrl.clear();
      FocusScope.of(context).unfocus();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success));
    }
  }

  Color get _statusColor {
    switch (_status) {
      case 'Normal':         return AppColors.success;
      case 'Pre-Diabetic':   return AppColors.warning;
      case 'Diabetes Range': return AppColors.danger;
      default: return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Blood Sugar', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading ? const LoadingView() : RefreshIndicator(
        onRefresh: _load,
        color: AppColors.sugar,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Status Hero ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_statusColor.withOpacity(0.85), _statusColor],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('LATEST STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.white70)),
                  const SizedBox(height: 6),
                  Text(_status, style: const TextStyle(fontFamily: 'Fraunces', fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
                  if (_latest != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_latest!['value_1'] != null ? 'Fasting: ${_latest!['value_1']?.toInt()} mg/dL' : ''}'
                      '${_latest!['value_2'] != null ? '  Post-meal: ${_latest!['value_2']?.toInt()} mg/dL' : ''}',
                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                    Text(_latest!['recorded_time'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.white60)),
                  ],
                ])),
                const Text('🩺', style: TextStyle(fontSize: 48)),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Reference ranges ────────────────────────────────
            Row(children: [
              Expanded(child: _RangeCard(label: 'Normal Fasting', value: '< 100 mg/dL', color: AppColors.success, isDark: isDark)),
              const SizedBox(width: 10),
              Expanded(child: _RangeCard(label: 'Pre-Diabetic', value: '100–125 mg/dL', color: AppColors.warning, isDark: isDark)),
              const SizedBox(width: 10),
              Expanded(child: _RangeCard(label: 'Diabetic', value: '≥ 126 mg/dL', color: AppColors.danger, isDark: isDark)),
            ]),
            const SizedBox(height: 16),

            // ── Log form ─────────────────────────────────────────
            _LogCard(
              fastingCtrl: _fastingCtrl,
              postMealCtrl: _postMealCtrl,
              notesCtrl: _notesCtrl,
              saving: _saving,
              onSave: _save,
              isDark: isDark,
            ),
            const SizedBox(height: 16),

            // ── Trend chart ──────────────────────────────────────
            if (_readings.length >= 2) ...[
              _TrendChart(readings: _readings, isDark: isDark),
              const SizedBox(height: 16),
            ],

            // ── History list ─────────────────────────────────────
            _HistoryList(readings: _readings, isDark: isDark),
            const SizedBox(height: 80),
          ]),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }
}

class _RangeCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool isDark;
  const _RangeCard({required this.label, required this.value, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.8), fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _LogCard extends StatelessWidget {
  final TextEditingController fastingCtrl, postMealCtrl, notesCtrl;
  final bool saving, isDark;
  final VoidCallback onSave;
  const _LogCard({required this.fastingCtrl, required this.postMealCtrl,
      required this.notesCtrl, required this.saving, required this.onSave, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            const Text('🩺', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text('Log Blood Sugar', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
          ]),
        ),
        Divider(height: 1, color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              Expanded(child: TextField(
                controller: fastingCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Fasting (mg/dL)', hintText: '95', suffixText: 'mg/dL'),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextField(
                controller: postMealCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Post-Meal (mg/dL)', hintText: '140', suffixText: 'mg/dL'),
              )),
            ]),
            const SizedBox(height: 12),
            TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'e.g. After breakfast')),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving ? null : onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.sugar,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('🩺 Save Reading', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 8),
            Text('Saved with exact time: ${TimeOfDay.now().format(context)}',
                style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted), textAlign: TextAlign.center),
          ]),
        ),
      ]),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<dynamic> readings;
  final bool isDark;
  const _TrendChart({required this.readings, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    final spotsP = <FlSpot>[];
    final r = readings.reversed.toList().take(14).toList().reversed.toList();
    for (int i = 0; i < r.length; i++) {
      if (r[i]['value_1'] != null) spots.add(FlSpot(i.toDouble(), (r[i]['value_1'] as num).toDouble()));
      if (r[i]['value_2'] != null) spotsP.add(FlSpot(i.toDouble(), (r[i]['value_2'] as num).toDouble()));
    }
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            Text('📈 Trend', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
            const Spacer(),
            if (spots.isNotEmpty) ...[
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.sugar, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('Fasting', style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
            ],
            if (spotsP.isNotEmpty) ...[
              const SizedBox(width: 10),
              Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.info.withOpacity(0.8), shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('Post-meal', style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
            ],
          ]),
        ),
        Divider(height: 1, color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 180,
            child: LineChart(LineChartData(
              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: isDark ? Colors.white10 : Colors.grey.shade100, strokeWidth: 1)),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}', style: TextStyle(fontSize: 10, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)))),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                if (spots.isNotEmpty) LineChartBarData(spots: spots, isCurved: true, color: AppColors.sugar, barWidth: 2.5, dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: AppColors.sugar.withOpacity(0.08))),
                if (spotsP.isNotEmpty) LineChartBarData(spots: spotsP, isCurved: true, color: AppColors.info, barWidth: 2, dotData: const FlDotData(show: false)),
                // Normal range line at 100
                LineChartBarData(spots: List.generate(r.length, (i) => FlSpot(i.toDouble(), 100)),
                    isCurved: false, color: AppColors.success.withOpacity(0.4), barWidth: 1, dashArray: [5,4], dotData: const FlDotData(show: false)),
              ],
            )),
          ),
        ),
      ]),
    );
  }
}

class _HistoryList extends StatelessWidget {
  final List<dynamic> readings;
  final bool isDark;
  const _HistoryList({required this.readings, required this.isDark});

  Color _rowColor(dynamic r) {
    final v = (r['value_1'] ?? 0) as num;
    if (v < 100) return AppColors.success;
    if (v < 126) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Text('📋 History', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
        ),
        Divider(height: 1, color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200),
        if (readings.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text('No readings yet.', style: TextStyle(color: isDark ? AppColors.textMutedDark : AppColors.textMuted))),
          )
        else
          ...readings.take(15).map((r) {
            final c = _rowColor(r);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade100))),
              child: Row(children: [
                Container(width: 4, height: 36, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (r['value_1'] != null) Text('Fasting: ${(r['value_1'] as num).toInt()} mg/dL',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
                  if (r['value_2'] != null) Text('Post-meal: ${(r['value_2'] as num).toInt()} mg/dL',
                      style: TextStyle(fontSize: 12, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(r['recorded_date'] ?? '', style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
                  Text(r['recorded_time'] ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c)),
                ]),
              ]),
            );
          }),
      ]),
    );
  }
}