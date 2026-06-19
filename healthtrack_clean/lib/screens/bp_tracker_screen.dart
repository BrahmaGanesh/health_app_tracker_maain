// ============================================================
// lib/screens/bp_tracker_screen.dart — Blood Pressure Tracker
// Logs systolic/diastolic/pulse with exact timestamp, shows chart
// ============================================================

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

class BPTrackerScreen extends StatefulWidget {
  const BPTrackerScreen({super.key});

  @override
  State<BPTrackerScreen> createState() => _BPTrackerScreenState();
}

class _BPTrackerScreenState extends State<BPTrackerScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _saving = false;
  List<dynamic> _readings = [];
  Map<String, dynamic>? _latest;
  double? _avgSys, _avgDia;

  final _sysCtrl = TextEditingController();
  final _diaCtrl = TextEditingController();
  final _pulseCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sysCtrl.dispose();
    _diaCtrl.dispose();
    _pulseCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getBP(days: 14);
    if (resp.success) {
      setState(() {
        _readings = resp.data['readings'] ?? [];
        _latest = resp.data['latest'];
        _avgSys = resp.data['avg_sys']?.toDouble();
        _avgDia = resp.data['avg_dia']?.toDouble();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final sys = double.tryParse(_sysCtrl.text);
    final dia = double.tryParse(_diaCtrl.text);
    if (sys == null || dia == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid systolic and diastolic values')));
      return;
    }

    setState(() => _saving = true);
    // Note: backend saves recorded_at = datetime.utcnow() automatically — exact current time
    final resp = await _api.addBP(sys, dia,
        pulse: double.tryParse(_pulseCtrl.text), notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim());
    setState(() => _saving = false);

    if (resp.success) {
      _sysCtrl.clear(); _diaCtrl.clear(); _pulseCtrl.clear(); _notesCtrl.clear();
      FocusScope.of(context).unfocus();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success));
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resp.message), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _delete(int id) async {
    final confirm = await showConfirmDialog(context, 'Delete Reading', 'Remove this BP reading?');
    if (!confirm) return;
    await _api.deleteBP(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: const Text('Blood Pressure', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold))),
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
                    _buildLatestCard(),
                    const SizedBox(height: 16),
                    _buildLogForm(),
                    const SizedBox(height: 16),
                    if (_readings.isNotEmpty) _buildChart(),
                    const SizedBox(height: 16),
                    _buildHistory(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLatestCard() {
    final status = _latest != null ? (_latest!['bp_status'] ?? '—') : 'No Reading';
    final color = AppTheme.bpStatusColor(status);

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Latest BP',
            value: _latest != null ? '${_latest!['value_1']?.toInt()}/${_latest!['value_2']?.toInt()}' : '—',
            sublabel: _latest != null ? '${status} · ${_latest!['recorded_time']}' : 'No data yet',
            emoji: '❤️', color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            label: '14-Day Avg', value: _avgSys != null ? '${_avgSys!.toInt()}/${_avgDia!.toInt()}' : '—',
            sublabel: '${_readings.length} readings', emoji: '📊', color: AppColors.violet,
          ),
        ),
      ],
    );
  }

  Widget _buildLogForm() {
    return SectionCard(
      title: '➕ Log Reading',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: TextField(controller: _sysCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Systolic', hintText: '120', suffixText: 'mmHg'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _diaCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Diastolic', hintText: '80', suffixText: 'mmHg'))),
            ],
          ),
          const SizedBox(height: 12),
          TextField(controller: _pulseCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pulse (optional)', hintText: '72', suffixText: 'bpm')),
          const SizedBox(height: 12),
          TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'e.g. After morning walk')),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
                  : const Text('❤️ Save Reading (logs current time)'),
            ),
          ),
          const SizedBox(height: 4),
          const Text('Recorded with the exact date & time you save it.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final spots = <FlSpot>[];
    final spotsD = <FlSpot>[];
    for (int i = 0; i < _readings.length; i++) {
      spots.add(FlSpot(i.toDouble(), (_readings[i]['value_1'] ?? 0).toDouble()));
      spotsD.add(FlSpot(i.toDouble(), (_readings[i]['value_2'] ?? 0).toDouble()));
    }

    return SectionCard(
      title: '📈 Trend (14 Days)',
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: true, horizontalInterval: 20, drawVerticalLine: false),
            titlesData: const FlTitlesData(
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(spots: spots, isCurved: true, color: AppColors.danger, barWidth: 2.5, dotData: const FlDotData(show: false)),
              LineChartBarData(spots: spotsD, isCurved: true, color: AppColors.info, barWidth: 2.5, dotData: const FlDotData(show: false)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistory() {
    return SectionCard(
      title: '📋 History',
      padding: EdgeInsets.zero,
      child: _readings.isEmpty
          ? const Padding(padding: EdgeInsets.all(16), child: Text('No readings yet.', style: TextStyle(color: AppColors.textMuted)))
          : Column(
              children: _readings.map<Widget>((r) {
                final status = r['bp_status'] ?? '';
                final color = AppTheme.bpStatusColor(status);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  leading: Container(
                    width: 8, height: 40,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                  ),
                  title: Text('${r['value_1']?.toInt()}/${r['value_2']?.toInt()} mmHg', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                  subtitle: Text('${r['recorded_date']} · ${r['recorded_time']} · $status', style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20), onPressed: () => _delete(r['id'])),
                );
              }).toList(),
            ),
    );
  }
}