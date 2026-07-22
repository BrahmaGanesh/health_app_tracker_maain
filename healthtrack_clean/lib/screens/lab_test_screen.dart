// lib/screens/lab_test_screen.dart — Complete Lab Tests Module
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart';

class LabTestScreen extends StatefulWidget {
  const LabTestScreen({super.key});
  @override State<LabTestScreen> createState() => _LabTestScreenState();
}

class _LabTestScreenState extends State<LabTestScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _api = ApiService();
  Map<String,dynamic>? _dash;
  bool _dashLoading = true;
  int? _memberId;

  static const _cats = [
    ('blood_sugar', '🩸', 'Blood Sugar'),
    ('hba1c',       '📊', 'HbA1c'),
    ('cholesterol', '🫀', 'Cholesterol'),
    ('kidney',      '🫘', 'Kidney'),
    ('liver',       '🫁', 'Liver'),
    ('thyroid',     '🦋', 'Thyroid'),
    ('cbc',         '🔬', 'CBC'),
    ('vitamin',     '☀️', 'Vitamins'),
    ('other',       '🧪', 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _cats.length, vsync: this);
    _loadDash();
  }
  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _loadDash() async {
    setState(() => _dashLoading = true);
    final r = await _api.get('/lab-tests/dashboard', query: _memberId != null ? {'member_id': _memberId} : null);
    if (r.success) setState(() => _dash = r.data);
    setState(() => _dashLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Lab Tests', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => _showAddSheet()),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadDash),
        ],
        bottom: TabBar(
          controller: _tabs, isScrollable: true,
          labelColor: AppColors.danger,
          unselectedLabelColor: tm, indicatorColor: AppColors.danger,
          tabs: _cats.map((c) => Tab(text: '${c.$2} ${c.$3}')).toList(),
        ),
      ),
      body: Column(children: [
        // Dashboard strip
        if (!_dashLoading && _dash != null) _DashStrip(dash: _dash!, isDark: isDark),
        Expanded(child: TabBarView(controller: _tabs, children: _cats.map((c) =>
          _CategoryTab(category: c.$1, icon: c.$2, label: c.$3, memberId: _memberId, isDark: isDark)).toList())),
      ]),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }

  void _showAddSheet({Map<String,dynamic>? existing}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String category = existing?['test_category'] ?? _cats[_tabs.index].$1;
    final nameCtrl  = TextEditingController(text: existing?['test_name'] ?? '');
    final valCtrl   = TextEditingController(text: existing != null ? '${existing['value']}' : '');
    final unitCtrl  = TextEditingController(text: existing?['unit'] ?? '');
    final labCtrl   = TextEditingController(text: existing?['lab_name'] ?? '');
    final docCtrl   = TextEditingController(text: existing?['doctor_name'] ?? '');
    final notesCtrl = TextEditingController(text: existing?['notes'] ?? '');
    final refLowCtrl= TextEditingController(text: existing?['ref_range_low']?.toString() ?? '');
    final refHiCtrl = TextEditingController(text: existing?['ref_range_high']?.toString() ?? '');
    String? dateStr;
    int? repeatMonths;

    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (_, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text(existing == null ? '🧪 Add Lab Test' : '✏️ Edit Lab Test', style: const TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),

          // Category
          DropdownButtonFormField<String>(
            value: category, decoration: const InputDecoration(labelText: 'Test Category'),
            items: _cats.map((c) => DropdownMenuItem(value: c.$1, child: Text('${c.$2} ${c.$3}'))).toList(),
            onChanged: (v) => setSt(() => category = v ?? 'blood_sugar')),
          const SizedBox(height: 10),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Test Name *', hintText: 'e.g. Fasting Blood Glucose')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: valCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Result Value *'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'Unit', hintText: 'mg/dL'))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: refLowCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ref Range Low'))),
            const SizedBox(width: 6), const Text('–', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: refHiCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ref Range High'))),
          ]),
          const SizedBox(height: 10),
          ListTile(contentPadding: EdgeInsets.zero, dense: true,
            title: const Text('Test Date', style: TextStyle(fontSize: 12)),
            subtitle: Text(dateStr ?? (existing?['test_date'] ?? 'Tap to select'), style: const TextStyle(fontSize: 13)),
            trailing: const Icon(Icons.calendar_today_rounded, size: 18),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2010), lastDate: DateTime.now());
              if (d != null) setSt(() => dateStr = d.toIso8601String().substring(0, 10));
            }),
          TextField(controller: labCtrl, decoration: const InputDecoration(labelText: 'Laboratory / Hospital')),
          const SizedBox(height: 10),
          TextField(controller: docCtrl, decoration: const InputDecoration(labelText: 'Doctor Name (optional)')),
          const SizedBox(height: 10),
          TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)'), maxLines: 2),
          const SizedBox(height: 10),
          DropdownButtonFormField<int?>(value: repeatMonths, decoration: const InputDecoration(labelText: 'Repeat Reminder (optional)'),
            items: const [
              DropdownMenuItem(value: null, child: Text('No repeat reminder')),
              DropdownMenuItem(value: 3,    child: Text('Every 3 months')),
              DropdownMenuItem(value: 6,    child: Text('Every 6 months')),
              DropdownMenuItem(value: 12,   child: Text('Every 12 months')),
            ],
            onChanged: (v) => setSt(() => repeatMonths = v)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || valCtrl.text.trim().isEmpty) return;
              final data = {
                'test_category': category, 'test_name': nameCtrl.text.trim(),
                'value': double.tryParse(valCtrl.text), 'unit': unitCtrl.text.trim(),
                if (refLowCtrl.text.isNotEmpty) 'ref_range_low': double.tryParse(refLowCtrl.text),
                if (refHiCtrl.text.isNotEmpty)  'ref_range_high': double.tryParse(refHiCtrl.text),
                if (dateStr != null)             'test_date': dateStr,
                'lab_name': labCtrl.text.trim(), 'doctor_name': docCtrl.text.trim(),
                'notes': notesCtrl.text.trim(),
                if (repeatMonths != null) 'repeat_reminder_months': repeatMonths,
                if (_memberId != null) 'member_id': _memberId,
              };
              ApiResponse resp;
              if (existing != null) resp = await _api.put('/lab-tests/${existing['id']}', data: data);
              else resp = await _api.post('/lab-tests/', data: data);
              if (ctx.mounted) Navigator.pop(ctx);
              if (resp.success) {
                setState(() {}); // trigger tab refresh
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: Text(existing == null ? '🧪 Save Result' : '✅ Update', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          )),
        ])),
      )));
  }
}

// ── Dashboard strip ───────────────────────────────────────────────
class _DashStrip extends StatelessWidget {
  final Map<String,dynamic> dash; final bool isDark;
  const _DashStrip({required this.dash, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tm   = isDark ? AppColors.textMutedDark : AppColors.textMuted;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16), border: Border.all(color: brd)),
      child: Row(children: [
        _Strip('🧪', '${dash['total_tests'] ?? 0}', 'Tests', AppColors.danger, isDark),
        _Strip('⚠️', '${dash['abnormal_count'] ?? 0}', 'Abnormal', AppColors.warning, isDark),
        _Strip('📊', '${dash['categories_tracked'] ?? 0}', 'Tracked', AppColors.info, isDark),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('Last updated', style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
          Text(dash['last_updated']?.toString().substring(0,10) ?? '—', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
        ])),
      ]),
    );
  }
}
class _Strip extends StatelessWidget {
  final String emoji, value, label; final Color color; final bool isDark;
  const _Strip(this.emoji, this.value, this.label, this.color, this.isDark);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(right: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(emoji, style: const TextStyle(fontSize: 16)),
    Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w700, color: color)),
    Text(label, style: TextStyle(fontSize: 9, color: color.withOpacity(0.8), fontWeight: FontWeight.w700)),
  ]));
}

// ── Category tab ──────────────────────────────────────────────────
class _CategoryTab extends StatefulWidget {
  final String category, icon, label; final int? memberId; final bool isDark;
  const _CategoryTab({required this.category, required this.icon, required this.label, this.memberId, required this.isDark});
  @override State<_CategoryTab> createState() => _CategoryTabState();
}
class _CategoryTabState extends State<_CategoryTab> {
  final _api = ApiService();
  List<dynamic> _tests = []; Map<String,dynamic>? _graph;
  bool _loading = true; String _period = '6m';

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _api.getLabTests(widget.category, memberId: widget.memberId),
      _api.get('/lab-tests/graph', query: {'category': widget.category, 'period': _period, if (widget.memberId != null) 'member_id': widget.memberId}),
    ]);
    if (results[0].success) setState(() => _tests = results[0].data['tests'] ?? []);
    if (results[1].success) setState(() => _graph = results[1].data);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp   = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm   = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    if (_loading) return const LoadingView();

    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(14), children: [
      // Latest result card
      if (_tests.isNotEmpty) ...[
        _LatestCard(test: _tests.first, isDark: isDark, card: card, brd: brd, tp: tp, tm: tm),
        const SizedBox(height: 14),
      ],

      // Graph
      if (_graph != null && (_graph!['points'] as List).isNotEmpty) ...[
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: brd)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${widget.icon} ${widget.label} Trend', style: TextStyle(fontFamily: 'Fraunces', fontSize: 15, fontWeight: FontWeight.bold, color: tp))),
              ...['3m','6m','1y','all'].map((p) => GestureDetector(
                onTap: () { setState(() => _period = p); _load(); },
                child: Container(margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _period == p ? AppColors.danger : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100), borderRadius: BorderRadius.circular(100)),
                  child: Text(p, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _period == p ? Colors.white : tm))))),
            ]),
            const SizedBox(height: 14),
            SizedBox(height: 180, child: _LabChart(graph: _graph!, isDark: isDark)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _GraphStat('Lowest',  '${_graph!['stats']['min']}', AppColors.success),
              _GraphStat('Average', '${_graph!['stats']['avg']}', AppColors.info),
              _GraphStat('Highest', '${_graph!['stats']['max']}', AppColors.danger),
            ]),
          ])),
        const SizedBox(height: 14),
      ],

      // History list
      if (_tests.isEmpty)
        const EmptyState(emoji: '🧪', title: 'No results yet', subtitle: 'Tap + to add your first lab test result')
      else ...[
        Text('📋 History', style: TextStyle(fontFamily: 'Fraunces', fontSize: 15, fontWeight: FontWeight.bold, color: tp)),
        const SizedBox(height: 10),
        ..._tests.asMap().entries.map((e) => _TestRow(
          test: e.value, isDark: isDark, card: card, brd: brd, tp: tp, tm: tm,
          isLatest: e.key == 0,
          onDelete: () async {
            final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Delete Lab Test?'),
              content: const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Are you sure you want to permanently delete this lab test record? This action cannot be undone.', style: TextStyle(fontSize: 13)),
                SizedBox(height: 8),
                Text('The linked document in the Documents Module will not be deleted.', style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
              ]),
              actions: [TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(_, true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white), child: const Text('Delete'))],
            ));
            if (ok == true) {
              await _api.delete('/lab-tests/${e.value['id']}');
              _load();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ Deleted. Linked document kept.'), backgroundColor: AppColors.success));
            }
          },
          onAiInsight: () => _showAiInsight(e.value),
        )),
      ],
      const SizedBox(height: 80),
    ]));
  }

  Future<void> _showAiInsight(Map<String,dynamic> test) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      content: const Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: AppColors.sage), SizedBox(height: 12), Text('Getting AI insights...')]),
    ));
    final resp = await _api.get('/lab-tests/${test['id']}/ai-insight');
    if (mounted) Navigator.pop(context);
    if (!resp.success) return;
    if (!mounted) return;
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(children: [Text('🤖 ', style: TextStyle(fontSize: 22)), Text('AI Insight')]),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${test['test_name']}: ${test['value']} ${test['unit'] ?? ''} — ${test['status']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 10),
        Text(resp.data['insight'] ?? '', style: const TextStyle(fontSize: 13, height: 1.6)),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.info.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
          child: Text(resp.data['disclaimer'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }
}

// ── Latest result card ────────────────────────────────────────────
class _LatestCard extends StatelessWidget {
  final dynamic test; final bool isDark; final Color card, brd, tp, tm;
  const _LatestCard({required this.test, required this.isDark, required this.card, required this.brd, required this.tp, required this.tm});
  @override
  Widget build(BuildContext context) {
    final statusColor = _parseColor(test['status_color']);
    final trend = test['trend'] ?? '→';
    return Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5)),
      child: Row(children: [
        Container(width: 64, height: 64, decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(16)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${test['value']}', style: TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w900, color: statusColor)),
          Text(test['unit'] ?? '', style: TextStyle(fontSize: 9, color: statusColor, fontWeight: FontWeight.w700)),
        ])),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(test['test_name'] ?? '', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: tp)),
          const SizedBox(height: 4),
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(100)),
              child: Text(test['status'] ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor))),
            const SizedBox(width: 8),
            Text(trend, style: TextStyle(fontSize: 18, color: trend == '↑' ? AppColors.danger : trend == '↓' ? AppColors.success : AppColors.textMuted)),
            if (test['change'] != null) Text('${test['change'] > 0 ? '+' : ''}${test['change']}', style: TextStyle(fontSize: 11, color: tm, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 3),
          Text(test['test_date'] ?? '', style: TextStyle(fontSize: 11, color: tm)),
        ])),
      ]));
  }
}

// ── Test history row ──────────────────────────────────────────────
class _TestRow extends StatelessWidget {
  final dynamic test; final bool isDark, isLatest; final Color card, brd, tp, tm;
  final VoidCallback onDelete; final VoidCallback onAiInsight;
  const _TestRow({required this.test, required this.isDark, required this.isLatest, required this.card, required this.brd, required this.tp, required this.tm, required this.onDelete, required this.onAiInsight});
  @override
  Widget build(BuildContext context) {
    final statusColor = _parseColor(test['status_color']);
    final trend = test['trend'] ?? '→';
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14), border: Border.all(color: isLatest ? statusColor.withOpacity(0.3) : brd)),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(trend, style: TextStyle(fontSize: 20, color: trend == '↑' ? AppColors.danger : trend == '↓' ? AppColors.success : AppColors.textMuted)),
        ]),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${test['value']}', style: TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700, color: statusColor)),
            Text(' ${test['unit'] ?? ''}', style: TextStyle(fontSize: 12, color: tm)),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(100)),
              child: Text(test['status'] ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor))),
          ]),
          Text('${test['test_date']} · ${test['lab_name'] ?? 'Lab'}', style: TextStyle(fontSize: 11, color: tm)),
          if (test['prev_value'] != null) Text('Prev: ${test['prev_value']} ${test['unit'] ?? ''}', style: TextStyle(fontSize: 10, color: tm)),
        ])),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: tm, size: 18),
          color: card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (a) { if (a == 'ai') onAiInsight(); else if (a == 'delete') onDelete(); },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'ai', child: Text('🤖  AI Insight', style: TextStyle(color: tp))),
            PopupMenuItem(value: 'delete', child: const Text('🗑️  Delete', style: TextStyle(color: AppColors.danger))),
          ],
        ),
      ]));
  }
}

// ── Chart ─────────────────────────────────────────────────────────
class _LabChart extends StatelessWidget {
  final Map<String,dynamic> graph; final bool isDark;
  const _LabChart({required this.graph, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final points = graph['points'] as List? ?? [];
    if (points.isEmpty) return const Center(child: Text('No data'));
    final spots = points.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value['value'] as num).toDouble())).toList();
    final vals  = spots.map((s) => s.y).toList();
    final minY  = (vals.reduce((a,b) => a<b?a:b) * 0.9);
    final maxY  = (vals.reduce((a,b) => a>b?a:b) * 1.1);

    return LineChart(LineChartData(
      minY: minY, maxY: maxY,
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: isDark ? Colors.white10 : Colors.grey.shade100, strokeWidth: 1)),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (v, _) {
          final i = v.toInt();
          if (i < 0 || i >= points.length || i % (points.length > 6 ? (points.length ~/ 4) : 1) != 0) return const SizedBox.shrink();
          final date = points[i]['date'].toString();
          return Padding(padding: const EdgeInsets.only(top: 4), child: Text(date.substring(5), style: TextStyle(fontSize: 9, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)));
        })),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, _) =>
          Text(v.toStringAsFixed(0), style: TextStyle(fontSize: 9, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)))),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [LineChartBarData(
        spots: spots, isCurved: true, color: AppColors.danger, barWidth: 2.5,
        dotData: FlDotData(show: true, getDotPainter: (spot, _, __, i) {
          final status = points[i]['status'] as String? ?? 'Normal';
          final isAbnormal = !['Normal','Good','Sufficient','Optimal'].contains(status);
          return FlDotCirclePainter(radius: 4, color: isAbnormal ? AppColors.danger : AppColors.success, strokeWidth: 1.5, strokeColor: Colors.white);
        }),
        belowBarData: BarAreaData(show: true, color: AppColors.danger.withOpacity(0.06)),
      )],
    ));
  }
}

// ── Graph stat ────────────────────────────────────────────────────
class _GraphStat extends StatelessWidget {
  final String label, value; final Color color;
  const _GraphStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w700, color: color)),
    Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.8), fontWeight: FontWeight.w600)),
  ]);
}

Color _parseColor(String? hex) {
  if (hex == null) return AppColors.textMuted;
  try { return Color(int.parse(hex.replaceFirst('#',''), radix: 16) | 0xFF000000); }
  catch (_) { return AppColors.textMuted; }
}