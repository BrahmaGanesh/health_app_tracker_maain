// lib/screens/analytics_screen.dart — Analytics + Dark Mode
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/step_tracking_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart' hide AppBottomNav;
import 'bp_tracker_screen.dart' show _CardBox, _LDot;

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabs;
  Map<String,dynamic>? _dashboard, _bp, _weight, _sugar, _sleep;
  bool _loading = true;

  @override
  void initState() { super.initState(); _tabs = TabController(length: 4, vsync: this); _load(); }
  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await Future.wait([_api.getDashboard(), _api.getBP(days: 30), _api.getWeight(days: 60), _api.getSugar(days: 30), _api.getSleep(days: 30)]);
    if (r[0].success) _dashboard = r[0].data;
    if (r[1].success) _bp       = r[1].data;
    if (r[2].success) _weight   = r[2].data;
    if (r[3].success) _sugar    = r[3].data;
    if (r[4].success) _sleep    = r[4].data;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Analytics', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
        bottom: TabBar(controller: _tabs,
          labelColor: AppColors.sage, unselectedLabelColor: isDark ? AppColors.textMutedDark : AppColors.textMuted,
          indicatorColor: AppColors.sage, isScrollable: true,
          tabs: const [Tab(text: '📊 Overview'), Tab(text: '❤️ BP'), Tab(text: '👟 Steps'), Tab(text: '💤 Sleep')],
        ),
      ),
      body: _loading ? const LoadingView() : TabBarView(controller: _tabs, children: [
        _OverviewTab(dashboard: _dashboard, weight: _weight, sugar: _sugar, isDark: isDark),
        _BPTab(bp: _bp, isDark: isDark),
        _StepsTab(isDark: isDark),
        _SleepTab(sleep: _sleep, isDark: isDark),
      ]),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }
}

// ── OVERVIEW TAB ─────────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  final Map<String,dynamic>? dashboard, weight, sugar;
  final bool isDark;
  const _OverviewTab({this.dashboard, this.weight, this.sugar, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp   = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm   = isDark ? AppColors.textMutedDark : AppColors.textMuted;
    final score = dashboard?['health_score'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Health Score
        if (score != null) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.navy, Color(0xFF1E3F6E)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              ProgressRing(percent: (score['total_score'] ?? 0) / 100, centerText: '${(score['total_score'] ?? 0).toInt()}',
                  label: score['grade'] ?? '', color: AppColors.mint, radius: 52),
              const SizedBox(width: 20),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Health Score', style: TextStyle(fontFamily: 'Fraunces', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                for (final e in [('BP', score['bp_score']), ('Water', score['water_score']), ('Sleep', score['sleep_score']), ('Exercise', score['exercise_score'])])
                  Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
                    SizedBox(width: 56, child: Text(e.$1, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7)))),
                    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(100), child: LinearProgressIndicator(
                        value: ((e.$2 ?? 0) as num).toDouble() / 100, minHeight: 5,
                        backgroundColor: Colors.white.withOpacity(0.15), color: AppColors.mint))),
                    SizedBox(width: 28, child: Text(' ${(e.$2 ?? 0).toInt()}', style: const TextStyle(fontSize: 10, color: Colors.white, fontFamily: 'monospace'))),
                  ])),
              ])),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // Weight BMI
        if (weight != null)
          CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('⚖️ Weight & BMI', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
            const SizedBox(height: 12),
            Row(children: [
              _Kpi('Current', '${weight!['latest']?['value_1'] ?? '—'} kg', AppColors.violet, isDark),
              const SizedBox(width: 12),
              _Kpi('BMI', '${weight!['bmi'] ?? '—'}', AppColors.sage, isDark),
              const SizedBox(width: 12),
              _Kpi('Status', weight!['bmi_status'] ?? '—', AppColors.info, isDark),
            ]),
          ])),
        const SizedBox(height: 16),

        // Sugar
        if (sugar != null)
          CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('🩺 Blood Sugar', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
            const SizedBox(height: 12),
            Row(children: [
              _Kpi('Fasting', '${sugar!['latest']?['value_1']?.toInt() ?? '—'} mg', AppColors.sugar, isDark),
              const SizedBox(width: 12),
              _Kpi('Status', sugar!['status'] ?? '—',
                  sugar!['status'] == 'Normal' ? AppColors.success : sugar!['status'] == 'Pre-Diabetic' ? AppColors.warning : AppColors.danger, isDark),
            ]),
          ])),
        const SizedBox(height: 80),
      ]),
    );
  }
}

// ── BP TAB ───────────────────────────────────────────────────────
class _BPTab extends StatelessWidget {
  final Map<String,dynamic>? bp; final bool isDark;
  const _BPTab({this.bp, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp   = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final readings = (bp?['readings'] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        if (readings.isNotEmpty) ...[
          Row(children: [
            _Kpi('Avg Sys', '${bp?['avg_sys']?.toInt() ?? '—'}', AppColors.danger, isDark),
            const SizedBox(width: 12),
            _Kpi('Avg Dia', '${bp?['avg_dia']?.toInt() ?? '—'}', AppColors.info, isDark),
            const SizedBox(width: 12),
            _Kpi('Readings', '${readings.length}', AppColors.violet, isDark),
          ]),
          const SizedBox(height: 16),
          CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('❤️ 30-Day Trend', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
            const SizedBox(height: 6),
            Row(children: [LDot(AppColors.danger,'Systolic'), const SizedBox(width: 12), LDot(AppColors.info,'Diastolic')]),
            const SizedBox(height: 12),
            SizedBox(height: 200, child: _buildBPChart(readings, isDark)),
          ])),
        ] else
          const EmptyState(emoji: '❤️', title: 'No BP data', subtitle: 'Log blood pressure readings to see trends here.'),
        const SizedBox(height: 80),
      ]),
    );
  }

  Widget _buildBPChart(List readings, bool isDark) {
    final rev  = readings.reversed.toList().take(20).toList();
    final spotsS = <FlSpot>[], spotsD = <FlSpot>[];
    for (int i = 0; i < rev.length; i++) {
      spotsS.add(FlSpot(i.toDouble(), (rev[i]['value_1'] ?? 0).toDouble()));
      spotsD.add(FlSpot(i.toDouble(), (rev[i]['value_2'] ?? 0).toDouble()));
    }
    return LineChart(LineChartData(
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: isDark ? Colors.white10 : Colors.grey.shade100, strokeWidth: 1)),
      titlesData: const FlTitlesData(topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32))),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(spots: spotsS, isCurved: true, color: AppColors.danger, barWidth: 2.5, dotData: const FlDotData(show: false)),
        LineChartBarData(spots: spotsD, isCurved: true, color: AppColors.info, barWidth: 2.5, dotData: const FlDotData(show: false)),
        LineChartBarData(spots: List.generate(rev.length, (i) => FlSpot(i.toDouble(), 120)), isCurved: false, color: AppColors.success.withOpacity(0.3), barWidth: 1, dashArray: [5,4], dotData: const FlDotData(show: false)),
      ],
    ));
  }
}

// ── STEPS TAB ────────────────────────────────────────────────────
class _StepsTab extends StatelessWidget {
  final bool isDark;
  const _StepsTab({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final stepSvc = context.watch<StepTrackingService>();
    final week    = stepSvc.weekHistory;
    final card    = isDark ? AppColors.cardDark : Colors.white;
    final brd     = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp      = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm      = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    final totalWeek = week.fold(0, (a, d) => a + d.steps);
    final avgDay    = week.isNotEmpty ? (totalWeek / week.length).round() : 0;
    final daysHit   = week.where((d) => d.achieved).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          _Kpi('Today', '${stepSvc.todaySteps}', AppColors.info, isDark),
          const SizedBox(width: 12),
          _Kpi('Avg/Day', '$avgDay', AppColors.sage, isDark),
          const SizedBox(width: 12),
          _Kpi('Goals Hit', '$daysHit/7', AppColors.success, isDark),
        ]),
        const SizedBox(height: 16),
        if (week.isNotEmpty)
          CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('👟 7-Day Steps', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
            const SizedBox(height: 14),
            SizedBox(height: 200, child: BarChart(BarChartData(
              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: isDark ? Colors.white10 : Colors.grey.shade100, strokeWidth: 1)),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36,
                    getTitlesWidget: (v, _) => Text('${(v/1000).toStringAsFixed(0)}k', style: TextStyle(fontSize: 9, color: tm)))),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= week.length) return const SizedBox.shrink();
                      return Padding(padding: const EdgeInsets.only(top: 4), child: Text(week[i].dayLabel, style: TextStyle(fontSize: 10, color: tm)));
                    })),
              ),
              barGroups: week.asMap().entries.map((e) => BarChartGroupData(x: e.key, barRods: [
                BarChartRodData(toY: e.value.steps.toDouble(),
                    color: e.value.achieved ? AppColors.success : AppColors.info,
                    width: 24, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
              ])).toList(),
              maxY: (stepSvc.dailyGoal * 1.3).toDouble(),
              extraLinesData: ExtraLinesData(horizontalLines: [
                HorizontalLine(y: stepSvc.dailyGoal.toDouble(), color: Colors.amber.withOpacity(0.6), strokeWidth: 1.5, dashArray: [6, 4]),
              ]),
            ))),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              LDot(AppColors.success, 'Goal achieved'), const SizedBox(width: 12),
              LDot(AppColors.info, 'Steps'), const SizedBox(width: 12),
              LDot(Colors.amber, 'Goal line'),
            ]),
          ])),
        const SizedBox(height: 80),
      ]),
    );
  }
}

// ── SLEEP TAB ─────────────────────────────────────────────────────
class _SleepTab extends StatelessWidget {
  final Map<String,dynamic>? sleep; final bool isDark;
  const _SleepTab({this.sleep, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp   = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm   = isDark ? AppColors.textMutedDark : AppColors.textMuted;
    final logs = (sleep?['logs'] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          _Kpi('Avg Sleep', '${sleep?['avg_hours']?.toStringAsFixed(1) ?? '—'}h', AppColors.sleep, isDark),
          const SizedBox(width: 12),
          _Kpi('Avg Quality', '${sleep?['avg_quality']?.toStringAsFixed(1) ?? '—'}/5', AppColors.gold, isDark),
          const SizedBox(width: 12),
          _Kpi('Nights', '${logs.length}', AppColors.violet, isDark),
        ]),
        const SizedBox(height: 16),
        if (logs.isNotEmpty)
          CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('😴 Sleep Pattern', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
            const SizedBox(height: 14),
            SizedBox(height: 180, child: BarChart(BarChartData(
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              maxY: 12,
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}h', style: TextStyle(fontSize: 9, color: tm))))),
              barGroups: logs.reversed.toList().take(14).toList().asMap().entries.map((e) {
                final hrs = (e.value['duration_hours'] ?? 0).toDouble();
                return BarChartGroupData(x: e.key, barRods: [
                  BarChartRodData(toY: hrs, color: hrs >= 7.5 ? AppColors.sleep : AppColors.warning,
                      width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(5))),
                ]);
              }).toList(),
            ))),
          ])),
        const SizedBox(height: 80),
      ]),
    );
  }
}

// ── Shared KPI box ─────────────────────────────────────────────────
class _Kpi extends StatelessWidget {
  final String label, value; final Color color; final bool isDark;
  const _Kpi(this.label, this.value, this.color, this.isDark);
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withOpacity(isDark ? 0.15 : 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.25))),
    child: Column(children: [
      Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700, color: color), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 3),
      Text(label, style: TextStyle(fontSize: 10, color: isDark ? AppColors.textMutedDark : AppColors.textMuted, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
    ]),
  ));
}