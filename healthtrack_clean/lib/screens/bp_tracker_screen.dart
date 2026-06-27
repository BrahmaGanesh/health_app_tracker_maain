// lib/screens/bp_tracker_screen.dart — Offline-first + Dark Mode
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../services/sync_service.dart';
import '../services/local_db_service.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart' hide AppBottomNav;

class BPTrackerScreen extends StatefulWidget {
  const BPTrackerScreen({super.key});
  @override State<BPTrackerScreen> createState() => _BPTrackerScreenState();
}

class _BPTrackerScreenState extends State<BPTrackerScreen> {
  final _db   = LocalDb();
  final _sync = SyncService();
  final _api  = ApiService();
  final _sysCtrl   = TextEditingController();
  final _diaCtrl   = TextEditingController();
  final _pulseCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<Map<String,dynamic>> _readings = [];
  bool _loading = true, _saving = false;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _sysCtrl.dispose(); _diaCtrl.dispose(); _pulseCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Load from local DB first (offline-first)
    final local = await _db.getMetrics('bp', days: 30);
    // Also try server if online
    if (_sync.isOnline) {
      final resp = await _api.getBP(days: 30);
      if (resp.success) {
        setState(() { _readings = List<Map<String,dynamic>>.from(resp.data['readings'] ?? []); _loading = false; });
        return;
      }
    }
    setState(() {
      _readings = local.map((r) => {
        'id': r['id'], 'value_1': r['value1'], 'value_2': r['value2'],
        'recorded_date': r['log_date'], 'recorded_time': r['recorded_at']?.toString().substring(11,16) ?? '',
        'bp_status': _bpStatus(r['value1']?.toDouble() ?? 0, r['value2']?.toDouble() ?? 0),
      }).toList();
      _loading = false;
    });
  }

  String _bpStatus(double sys, double dia) {
    if (sys >= 180 || dia >= 120) return 'Crisis';
    if (sys >= 140 || dia >= 90)  return 'High Stage 2';
    if (sys >= 130 || dia >= 80)  return 'High Stage 1';
    if (sys >= 120)               return 'Elevated';
    return 'Normal';
  }

  Future<void> _save() async {
    final sys = double.tryParse(_sysCtrl.text);
    final dia = double.tryParse(_diaCtrl.text);
    if (sys == null || dia == null) return;
    setState(() => _saving = true);

    // OFFLINE-FIRST: save locally then sync
    await _sync.saveMetricOffline(type: 'bp', value1: sys, value2: dia,
        value3: double.tryParse(_pulseCtrl.text), notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim());

    setState(() => _saving = false);
    _sysCtrl.clear(); _diaCtrl.clear(); _pulseCtrl.clear(); _notesCtrl.clear();
    FocusScope.of(context).unfocus();
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_sync.isOnline ? '✅ Saved & synced' : '💾 Saved offline — will sync when online'),
        backgroundColor: _sync.isOnline ? AppColors.success : AppColors.warning));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card   = isDark ? AppColors.cardDark : Colors.white;
    final brd    = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp     = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm     = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    final latest = _readings.isNotEmpty ? _readings.first : null;
    final status = latest?['bp_status'] ?? 'No Reading';
    final sc     = AppTheme.bpStatusColor(status);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Blood Pressure', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [
          _SyncBadge(_sync.isOnline),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading ? const LoadingView() : RefreshIndicator(
        onRefresh: _load, color: AppColors.danger,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Status hero ───────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [sc.withOpacity(0.85), sc], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: sc.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('BLOOD PRESSURE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.white70)),
                  const SizedBox(height: 6),
                  Text(latest != null ? '${latest['value_1']?.toInt()}/${latest['value_2']?.toInt()}' : '—',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 40, fontWeight: FontWeight.w700, color: Colors.white, height: 1)),
                  const Text('mmHg', style: TextStyle(fontSize: 12, color: Colors.white60)),
                  const SizedBox(height: 6),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(100)),
                    child: Text(status, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white))),
                ])),
                const Text('❤️', style: TextStyle(fontSize: 50)),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Stats row ─────────────────────────────────────
            Row(children: [
              _SmallCard('📊', 'Avg Sys', _readings.isNotEmpty ? '${(_readings.map((r) => (r['value_1'] ?? 0) as num).reduce((a,b)=>a+b) / _readings.length).toInt()}' : '—', AppColors.danger, isDark, card, brd, tp),
              const SizedBox(width: 12),
              _SmallCard('📊', 'Avg Dia', _readings.isNotEmpty ? '${(_readings.map((r) => (r['value_2'] ?? 0) as num).reduce((a,b)=>a+b) / _readings.length).toInt()}' : '—', AppColors.info, isDark, card, brd, tp),
              const SizedBox(width: 12),
              _SmallCard('📋', 'Readings', '${_readings.length}', AppColors.violet, isDark, card, brd, tp),
            ]),
            const SizedBox(height: 16),

            // ── Log form ──────────────────────────────────────
            _CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('➕ Log Reading', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: TextField(controller: _sysCtrl, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Systolic', hintText: '120', suffixText: 'mmHg'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _diaCtrl, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Diastolic', hintText: '80', suffixText: 'mmHg'))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: _pulseCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Pulse (optional)', hintText: '72', suffixText: 'bpm')),
              const SizedBox(height: 10),
              TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'After morning walk')),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_sync.isOnline ? '❤️ Save & Sync' : '💾 Save Offline', style: const TextStyle(fontWeight: FontWeight.bold)),
              )),
              const SizedBox(height: 6),
              Center(child: Text('Exact time is recorded automatically', style: TextStyle(fontSize: 11, color: tm))),
            ])),
            const SizedBox(height: 16),

            // ── Chart ─────────────────────────────────────────
            if (_readings.length >= 3)
              _CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('📈 Trend', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
                const SizedBox(height: 14),
                SizedBox(height: 170, child: _buildChart(isDark)),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _LDot(AppColors.danger, 'Systolic'),
                  const SizedBox(width: 16),
                  _LDot(AppColors.info, 'Diastolic'),
                  const SizedBox(width: 16),
                  _LDot(AppColors.success.withOpacity(0.5), 'Normal 120'),
                ]),
              ])),
            const SizedBox(height: 16),

            // ── History ───────────────────────────────────────
            _CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('📋 History', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
              const SizedBox(height: 10),
              if (_readings.isEmpty)
                Center(child: Text('No readings yet.', style: TextStyle(color: tm)))
              else
                ..._readings.take(20).map((r) {
                  final c = AppTheme.bpStatusColor(r['bp_status'] ?? '');
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: brd, width: 0.5))),
                    child: Row(children: [
                      Container(width: 4, height: 38, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r['value_1']?.toInt() ?? '—'}/${r['value_2']?.toInt() ?? '—'} mmHg',
                            style: TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w600, color: tp)),
                        Text('${r['bp_status'] ?? ''}${r['value_3'] != null ? '  •  Pulse: ${r['value_3']?.toInt()}' : ''}',
                            style: TextStyle(fontSize: 11, color: c)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(r['recorded_date'] ?? '', style: TextStyle(fontSize: 11, color: tm)),
                        Text(r['recorded_time'] ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tp)),
                      ]),
                    ]),
                  );
                }),
            ])),
            const SizedBox(height: 80),
          ]),
        ),
      ),
    );
  }

  Widget _buildChart(bool isDark) {
    final rev = _readings.reversed.toList().take(14).toList();
    final spotsS = <FlSpot>[], spotsD = <FlSpot>[];
    for (int i = 0; i < rev.length; i++) {
      spotsS.add(FlSpot(i.toDouble(), (rev[i]['value_1'] ?? 0).toDouble()));
      spotsD.add(FlSpot(i.toDouble(), (rev[i]['value_2'] ?? 0).toDouble()));
    }
    return LineChart(LineChartData(
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: isDark ? Colors.white10 : Colors.grey.shade100, strokeWidth: 1)),
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
        if (spotsS.isNotEmpty) LineChartBarData(
          spots: List.generate(rev.length, (i) => FlSpot(i.toDouble(), 120)),
          isCurved: false, color: AppColors.success.withOpacity(0.4), barWidth: 1, dashArray: [6, 4], dotData: const FlDotData(show: false)),
      ],
    ));
  }
}

// ── Shared small helpers ──────────────────────────────────────────
class _CardBox extends StatelessWidget {
  final bool isDark; final Color cardBg, border; final Widget child;
  const _CardBox({required this.isDark, required this.cardBg, required this.border, required this.child});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))]),
    child: child);
}

class _SmallCard extends StatelessWidget {
  final String emoji, label, value; final Color color, cardBg, border, tp; final bool isDark;
  const _SmallCard(this.emoji, this.label, this.value, this.color, this.isDark, this.cardBg, this.border, this.tp);
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w700, color: color)),
      Text(label, style: TextStyle(fontSize: 10, color: tp, fontWeight: FontWeight.w600)),
    ]),
  ));
}

class _SyncBadge extends StatelessWidget {
  final bool online;
  const _SyncBadge(this.online);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Center(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: (online ? AppColors.success : AppColors.warning).withOpacity(0.12), borderRadius: BorderRadius.circular(100)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: online ? AppColors.success : AppColors.warning)),
        const SizedBox(width: 4),
        Text(online ? '● Synced' : '○ Offline', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: online ? AppColors.success : AppColors.warning)),
      ]),
    )),
  );
}

class _LDot extends StatelessWidget {
  final Color color; final String label;
  const _LDot(this.color, this.label);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
  ]);
}