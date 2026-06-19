// ============================================================
// lib/screens/analytics_screen.dart — Health Analytics & Trends
// BP/Weight/Sugar trends, health score, predictions
// ============================================================

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _api = ApiService();
  bool _loading = true;
  Map<String, dynamic>? _dashboard;
  Map<String, dynamic>? _bpData;
  Map<String, dynamic>? _weightData;
  Map<String, dynamic>? _sugarData;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _api.getDashboard(),
      _api.getBP(days: 30),
      _api.getWeight(days: 60),
      _api.getSugar(days: 30),
    ]);
    if (results[0].success) _dashboard = results[0].data;
    if (results[1].success) _bpData = results[1].data;
    if (results[2].success) _weightData = results[2].data;
    if (results[3].success) _sugarData = results[3].data;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: const Text('Analytics', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold))),
      body: _loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.sage,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_dashboard?['health_score'] != null) _buildScoreCard(),
                    const SizedBox(height: 16),
                    if (_bpData != null && (_bpData!['readings'] as List).isNotEmpty) _buildBPChart(),
                    const SizedBox(height: 16),
                    if (_weightData != null && (_weightData!['readings'] as List).length >= 2) _buildWeightChart(),
                    const SizedBox(height: 16),
                    if (_sugarData != null && (_sugarData!['readings'] as List).isNotEmpty) _buildSugarSection(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }

  Widget _buildScoreCard() {
    final score = _dashboard!['health_score'];
    final total = (score['total_score'] ?? 0).toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.navy, Color(0xFF1E3F6E)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          ProgressRing(percent: total / 100, centerText: '${total.toInt()}', label: score['grade'] ?? '', color: AppColors.mint, radius: 50),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Health Score', style: TextStyle(fontFamily: 'Fraunces', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                _scoreRow('BP', score['bp_score']),
                _scoreRow('Water', score['water_score']),
                _scoreRow('Sleep', score['sleep_score']),
                _scoreRow('Exercise', score['exercise_score']),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreRow(String label, dynamic value) {
    final v = (value ?? 0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7)))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(value: v / 100, minHeight: 5, backgroundColor: Colors.white.withOpacity(0.15), color: AppColors.mint),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 28, child: Text('${v.toInt()}', style: const TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'monospace'), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildBPChart() {
    final readings = _bpData!['readings'] as List;
    final spotsS = <FlSpot>[], spotsD = <FlSpot>[];
    for (int i = 0; i < readings.length; i++) {
      spotsS.add(FlSpot(i.toDouble(), (readings[i]['value_1'] ?? 0).toDouble()));
      spotsD.add(FlSpot(i.toDouble(), (readings[i]['value_2'] ?? 0).toDouble()));
    }

    return SectionCard(
      title: '❤️ Blood Pressure (30 Days)',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)),
        const SizedBox(width: 4), const Text('Sys', style: TextStyle(fontSize: 11)),
        const SizedBox(width: 8),
        Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.info, shape: BoxShape.circle)),
        const SizedBox(width: 4), const Text('Dia', style: TextStyle(fontSize: 11)),
      ]),
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: LineChart(LineChartData(
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              titlesData: const FlTitlesData(
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(spots: spotsS, isCurved: true, color: AppColors.danger, barWidth: 2.5, dotData: const FlDotData(show: false)),
                LineChartBarData(spots: spotsD, isCurved: true, color: AppColors.info, barWidth: 2.5, dotData: const FlDotData(show: false)),
              ],
            )),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text('Avg: ${_bpData!['avg_sys']?.toInt() ?? '—'}/${_bpData!['avg_dia']?.toInt() ?? '—'}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              Text('${readings.length} readings', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeightChart() {
    final readings = _weightData!['readings'] as List;
    final spots = <FlSpot>[];
    for (int i = 0; i < readings.length; i++) {
      spots.add(FlSpot(i.toDouble(), (readings[i]['value_1'] ?? 0).toDouble()));
    }

    final change = _weightData!['change']?.toDouble() ?? 0;

    return SectionCard(
      title: '⚖️ Weight Trend (60 Days)',
      trailing: PillChip(text: change == 0 ? 'No change' : (change > 0 ? '+${change.toStringAsFixed(1)}kg' : '${change.toStringAsFixed(1)}kg'), color: change <= 0 ? AppColors.success : AppColors.warning),
      child: SizedBox(
        height: 180,
        child: LineChart(LineChartData(
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: const FlTitlesData(
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(spots: spots, isCurved: true, color: AppColors.violet, barWidth: 3, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: AppColors.violet.withOpacity(0.1))),
          ],
        )),
      ),
    );
  }

  Widget _buildSugarSection() {
    final latest = _sugarData!['latest'];
    final status = _sugarData!['status'] ?? '';
    final statusColor = status == 'Normal' ? AppColors.success : (status == 'Pre-Diabetic' ? AppColors.warning : AppColors.danger);

    return SectionCard(
      title: '🩺 Blood Sugar',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fasting: ${latest?['value_1']?.toInt() ?? '—'} mg/dL', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                if (latest?['value_2'] != null) Text('Post-meal: ${latest['value_2'].toInt()} mg/dL', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                const SizedBox(height: 6),
                PillChip(text: status, color: statusColor),
              ],
            ),
          ),
          Text('🩺', style: const TextStyle(fontSize: 36)),
        ],
      ),
    );
  }
}