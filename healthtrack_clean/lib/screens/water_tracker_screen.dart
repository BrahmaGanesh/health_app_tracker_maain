// lib/screens/water_tracker_screen.dart — Offline-first + Dark Mode
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../services/sync_service.dart';
import '../services/local_db_service.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart' hide AppBottomNav;
import 'bp_tracker_screen.dart' show _CardBox, _SyncBadge, _LDot;

class WaterTrackerScreen extends StatefulWidget {
  const WaterTrackerScreen({super.key});
  @override State<WaterTrackerScreen> createState() => _WaterTrackerScreenState();
}

class _WaterTrackerScreenState extends State<WaterTrackerScreen> {
  final _db   = LocalDb();
  final _sync = SyncService();
  final _api  = ApiService();
  final _customCtrl = TextEditingController();

  double _todayTotal = 0, _target = 2.5;
  int    _pct = 0;
  List<dynamic> _logs = [], _week = [];
  bool _loading = true, _saving = false;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _customCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (_sync.isOnline) {
      final resp = await _api.getWaterToday();
      if (resp.success) {
        setState(() {
          _todayTotal = (resp.data['today_total'] ?? 0).toDouble();
          _target     = (resp.data['target'] ?? 2.5).toDouble();
          _pct        = resp.data['pct'] ?? 0;
          _logs       = resp.data['logs'] ?? [];
          _week       = resp.data['week'] ?? [];
          _loading    = false;
        });
        return;
      }
    }
    // Offline fallback
    final local = await _db.getMetrics('water', days: 7);
    double total = 0;
    for (final r in local) {
      final d = r['log_date'] as String;
      if (d == DateTime.now().toIso8601String().substring(0, 10)) total += (r['value1'] as num? ?? 0).toDouble();
    }
    setState(() {
      _todayTotal = total;
      _pct        = (_target > 0 ? (total / _target * 100).clamp(0, 100) : 0).toInt();
      _logs       = local.where((r) => r['log_date'] == DateTime.now().toIso8601String().substring(0, 10)).map((r) => {'value_1': r['value1'], 'recorded_time': r['recorded_at']?.toString().substring(11, 16) ?? ''}).toList();
      _loading    = false;
    });
  }

  Future<void> _add(double litres) async {
    setState(() => _saving = true);
    await _sync.saveMetricOffline(type: 'water', value1: litres);
    setState(() => _saving = false);
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_sync.isOnline ? '💧 +${litres}L saved' : '💾 +${litres}L saved offline'),
        backgroundColor: AppColors.water));
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
        title: const Text('Water Intake', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
       actions: [SyncBadge(_sync.isOnline), IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: _loading ? const LoadingView() : RefreshIndicator(
        onRefresh: _load, color: AppColors.water,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Hero progress card
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF0369A1), Color(0xFF0EA5E9)]),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: AppColors.water.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))],
              ),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('TODAY\'S INTAKE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.white70)),
                    const SizedBox(height: 6),
                    Text('${_todayTotal.toStringAsFixed(2)}L', style: const TextStyle(fontFamily: 'monospace', fontSize: 42, fontWeight: FontWeight.w700, color: Colors.white, height: 1)),
                    Text('of ${_target.toStringAsFixed(1)}L goal', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  ])),
                  ProgressRing(percent: _pct / 100, centerText: '$_pct%', label: 'done', color: Colors.white, radius: 44),
                ]),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: LinearProgressIndicator(value: _pct / 100, minHeight: 10, backgroundColor: Colors.white.withOpacity(0.2), color: Colors.white),
                ),
                const SizedBox(height: 8),
                if (_todayTotal >= _target)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(100)),
                    child: const Text('🎉 Daily goal achieved!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              ]),
            ),
            const SizedBox(height: 16),

            // Quick add
            CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('💧 Quick Add', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
              const SizedBox(height: 12),
              Row(children: [
                for (final a in [('🥛', 'Glass', 0.25), ('🍶', 'Bottle', 0.5), ('💧', 'Large', 1.0)])
                  Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton(
                      onPressed: _saving ? null : () => _add(a.$3),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.water.withOpacity(isDark ? 0.2 : 0.1),
                        foregroundColor: AppColors.water, elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColors.water.withOpacity(0.3))),
                      ),
                      child: Column(children: [
                        Text(a.$1, style: const TextStyle(fontSize: 22)),
                        const SizedBox(height: 4),
                        Text(a.$2, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        Text('${a.$3}L', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                      ]),
                    ),
                  )),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: _customCtrl, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Custom (litres)', hintText: '0.3', suffixText: 'L'))),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _saving ? null : () {
                    final v = double.tryParse(_customCtrl.text);
                    if (v != null && v > 0) { _add(v); _customCtrl.clear(); }
                  },
                  child: const Text('Add'),
                ),
              ]),
            ])),
            const SizedBox(height: 16),

            // Week chart
            if (_week.isNotEmpty)
              CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('📊 This Week', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
                const SizedBox(height: 14),
                SizedBox(height: 150, child: BarChart(BarChartData(
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= _week.length) return const SizedBox.shrink();
                      return Padding(padding: const EdgeInsets.only(top: 4), child: Text(_week[i]['day'] ?? '', style: TextStyle(fontSize: 10, color: tm)));
                    })),
                  ),
                  barGroups: _week.asMap().entries.map((e) {
                    final litres = (e.value['litres'] ?? 0).toDouble();
                    return BarChartGroupData(x: e.key, barRods: [
                      BarChartRodData(toY: litres, color: litres >= _target ? AppColors.success : AppColors.water,
                          width: 18, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
                    ]);
                  }).toList(),
                  maxY: (_target * 1.5),
                ))),
              ])),
            const SizedBox(height: 16),

            // Today's log
            CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("📋 Today's Log", style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
              const SizedBox(height: 10),
              if (_logs.isEmpty)
                Center(child: Text('No water logged today yet.', style: TextStyle(color: tm, fontSize: 13)))
              else
                ..._logs.map((l) => ListTile(contentPadding: EdgeInsets.zero, dense: true,
                  leading: const Text('💧', style: TextStyle(fontSize: 20)),
                  title: Text('${l['value_1']}L', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.water)),
                  trailing: Text(l['recorded_time'] ?? '', style: TextStyle(fontSize: 12, color: tm)),
                )),
            ])),
            const SizedBox(height: 80),
          ]),
        ),
      ),
    );
  }
}