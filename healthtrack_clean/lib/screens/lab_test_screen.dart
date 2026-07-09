// lib/screens/lab_test_screen.dart — Module 8: Lab Test Tracker
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/local_db_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart';

class LabTestScreen extends StatefulWidget {
  const LabTestScreen({super.key});
  @override State<LabTestScreen> createState() => _LabTestScreenState();
}

class _LabTestScreenState extends State<LabTestScreen> {
  final _api = ApiService();
  final _db  = LocalDb();

  static const _testTypes = {
    'blood_sugar':  ('🩺', 'Blood Sugar', 'mg/dL'),
    'hba1c':        ('🩸', 'HbA1c', '%'),
    'cholesterol':  ('🫀', 'Cholesterol', 'mg/dL'),
    'hemoglobin':   ('💉', 'Hemoglobin', 'g/dL'),
    'vitamin_d':    ('☀️', 'Vitamin D', 'ng/mL'),
    'kidney':       ('🫘', 'Kidney (Creatinine)', 'mg/dL'),
    'liver':        ('🫁', 'Liver (ALT)', 'U/L'),
    'custom':       ('📋', 'Custom Test', ''),
  };

  String _selectedType = 'blood_sugar';
  List<dynamic> _tests = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (SyncService().isOnline) {
      final resp = await _api.getLabTests(_selectedType);
      if (resp.success) { setState(() { _tests = resp.data['tests'] ?? []; _loading = false; }); return; }
    }
    final local = await _db.getLabTests(_selectedType);
    setState(() { _tests = local; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp   = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm   = isDark ? AppColors.textMutedDark : AppColors.textMuted;
    final typeInfo = _testTypes[_selectedType]!;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Lab Tests', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => _showAddSheet(isDark))],
      ),
      body: Column(children: [
        SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          children: _testTypes.entries.map((e) {
            final sel = e.key == _selectedType;
            return Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
              onTap: () { setState(() => _selectedType = e.key); _load(); },
              child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: sel ? AppColors.danger : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100), borderRadius: BorderRadius.circular(100)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(e.value.$1, style: const TextStyle(fontSize: 13)), const SizedBox(width: 5),
                  Text(e.value.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : tm)),
                ])),
            ));
          }).toList())),
        Expanded(child: _loading ? const LoadingView() : RefreshIndicator(onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (_tests.isNotEmpty) ...[
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: brd)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${typeInfo.$1} ${typeInfo.$2} Trend', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
                  const SizedBox(height: 14),
                  SizedBox(height: 180, child: _buildChart(isDark)),
                ])),
              const SizedBox(height: 16),
            ],
            Container(decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: brd)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 6), child: Text('📋 History', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp))),
                if (_tests.isEmpty)
                  Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('No ${typeInfo.$2} readings yet.', style: TextStyle(color: tm))))
                else
                  ..._tests.map((t) => ListTile(dense: true,
                    title: Text('${t['value']} ${t['unit'] ?? typeInfo.$3}', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 15, color: tp)),
                    subtitle: Text('${t['lab_name'] ?? 'Lab'} · ${t['test_date'] ?? ''}', style: TextStyle(fontSize: 11, color: tm)),
                  )),
              ])),
            const SizedBox(height: 80),
          ]))),
      ]),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }

  Widget _buildChart(bool isDark) {
    final rev = _tests.reversed.toList();
    final spots = <FlSpot>[];
    for (int i = 0; i < rev.length; i++) spots.add(FlSpot(i.toDouble(), (rev[i]['value'] ?? 0).toDouble()));
    return LineChart(LineChartData(
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: isDark ? Colors.white10 : Colors.grey.shade100, strokeWidth: 1)),
      titlesData: const FlTitlesData(topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36))),
      borderData: FlBorderData(show: false),
      lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: AppColors.danger, barWidth: 2.5, dotData: const FlDotData(show: true), belowBarData: BarAreaData(show: true, color: AppColors.danger.withOpacity(0.08)))],
    ));
  }

  void _showAddSheet(bool isDark) {
    final valueCtrl = TextEditingController(), labCtrl = TextEditingController();
    DateTime testDate = DateTime.now();
    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (_, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_testTypes[_selectedType]!.$1} Log ${_testTypes[_selectedType]!.$2}', style: const TextStyle(fontFamily: 'Fraunces', fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(controller: valueCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Value', suffixText: _testTypes[_selectedType]!.$3)),
          const SizedBox(height: 10),
          TextField(controller: labCtrl, decoration: const InputDecoration(labelText: 'Lab Name (optional)', hintText: 'e.g. City Diagnostics')),
          const SizedBox(height: 10),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Test Date'),
            trailing: TextButton(onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: testDate, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null) setSt(() => testDate = d);
            }, child: Text('${testDate.day}/${testDate.month}/${testDate.year}'))),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
            final v = double.tryParse(valueCtrl.text);
            if (v == null) return;
            final resp = await _api.addLabTest({
              'test_type': _selectedType, 'value': v, 'lab_name': labCtrl.text.trim(),
              'test_date': testDate.toIso8601String().substring(0, 10),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            if (resp.success) { _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Saved'), backgroundColor: AppColors.success)); }
          }, child: const Text('Save Result', style: TextStyle(fontWeight: FontWeight.bold)))),
        ]),
      )),
    );
  }
}