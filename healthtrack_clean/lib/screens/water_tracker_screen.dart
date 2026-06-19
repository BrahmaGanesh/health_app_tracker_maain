// ============================================================
// lib/screens/water_tracker_screen.dart — Water Intake Tracker
// Quick-add buttons, today's total, 7-day chart
// ============================================================

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

class WaterTrackerScreen extends StatefulWidget {
  const WaterTrackerScreen({super.key});

  @override
  State<WaterTrackerScreen> createState() => _WaterTrackerScreenState();
}

class _WaterTrackerScreenState extends State<WaterTrackerScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _saving = false;
  double _todayTotal = 0;
  double _target = 2.5;
  int _pct = 0;
  List<dynamic> _logs = [];
  List<dynamic> _week = [];
  final _customCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getWaterToday();
    if (resp.success) {
      setState(() {
        _todayTotal = (resp.data['today_total'] ?? 0).toDouble();
        _target = (resp.data['target'] ?? 2.5).toDouble();
        _pct = resp.data['pct'] ?? 0;
        _logs = resp.data['logs'] ?? [];
        _week = resp.data['week'] ?? [];
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _addWater(double litres) async {
    setState(() => _saving = true);
    final resp = await _api.addWater(litres);
    setState(() => _saving = false);
    if (resp.success) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('💧 ${resp.message}'), backgroundColor: AppColors.water));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: const Text('Water Intake', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold))),
      body: _loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.water,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProgressCard(),
                    const SizedBox(height: 16),
                    _buildQuickAdd(),
                    const SizedBox(height: 16),
                    if (_week.isNotEmpty) _buildWeekChart(),
                    const SizedBox(height: 16),
                    _buildTodayLogs(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProgressCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF38BDF8)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          ProgressRing(
            percent: _pct / 100, centerText: '${_pct}%', label: 'of goal',
            color: Colors.white, radius: 50,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_todayTotal.toStringAsFixed(2)}L', style: const TextStyle(fontFamily: 'monospace', fontSize: 32, fontWeight: FontWeight.w600, color: Colors.white)),
                Text('of ${_target.toStringAsFixed(1)}L target', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8))),
                const SizedBox(height: 8),
                if (_todayTotal >= _target)
                  const Text('🎉 Goal achieved today!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAdd() {
    final amounts = [
      {'label': 'Glass', 'value': 0.25, 'emoji': '🥛'},
      {'label': 'Bottle', 'value': 0.5, 'emoji': '🍶'},
      {'label': 'Large', 'value': 1.0, 'emoji': '💧'},
    ];

    return SectionCard(
      title: '➕ Quick Add',
      child: Column(
        children: [
          Row(
            children: amounts.map((a) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ElevatedButton(
                    onPressed: _saving ? null : () => _addWater(a['value'] as double),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.water.withOpacity(0.12), foregroundColor: AppColors.water, elevation: 0),
                    child: Column(
                      children: [
                        Text(a['emoji'] as String, style: const TextStyle(fontSize: 20)),
                        Text('${a['label']}\n${a['value']}L', style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Custom amount', hintText: '0.3', suffixText: 'L'),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _saving
                    ? null
                    : () {
                        final v = double.tryParse(_customCtrl.text);
                        if (v != null && v > 0) {
                          _addWater(v);
                          _customCtrl.clear();
                        }
                      },
                child: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeekChart() {
    final bars = <BarChartGroupData>[];
    for (int i = 0; i < _week.length; i++) {
      final litres = (_week[i]['litres'] ?? 0).toDouble();
      bars.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: litres, color: litres >= _target ? AppColors.success : AppColors.water, width: 18, borderRadius: BorderRadius.circular(6)),
      ]));
    }

    return SectionCard(
      title: '📊 This Week',
      child: SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= _week.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 4), child: Text(_week[i]['day'], style: const TextStyle(fontSize: 10, color: AppColors.textMuted)));
              })),
            ),
            barGroups: bars,
          ),
        ),
      ),
    );
  }

  Widget _buildTodayLogs() {
    return SectionCard(
      title: "📋 Today's Log",
      padding: EdgeInsets.zero,
      child: _logs.isEmpty
          ? const Padding(padding: EdgeInsets.all(16), child: Text('No water logged yet today.', style: TextStyle(color: AppColors.textMuted)))
          : Column(
              children: _logs.map<Widget>((l) {
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Text('💧', style: TextStyle(fontSize: 20)),
                  title: Text('${l['value_1']}L', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                  trailing: Text(l['recorded_time'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                );
              }).toList(),
            ),
    );
  }
}