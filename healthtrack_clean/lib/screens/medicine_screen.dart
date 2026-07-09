// lib/screens/medicine_screen.dart — Module 4: Medicine Management
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/local_db_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart';

class MedicineScreen extends StatefulWidget {
  const MedicineScreen({super.key});
  @override State<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends State<MedicineScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _db  = LocalDb();
  late TabController _tabs;
  List<dynamic> _medicines = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this); _load(); }
  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getMedicines();
    if (resp.success) {
      setState(() => _medicines = resp.data['medicines'] ?? []);
      // Cache locally for offline
      for (final m in _medicines) {
        await _db.saveMedicine({
          'id': m['id'], 'server_id': m['id'], 'name': m['name'],
          'dosage': m['dosage'], 'timing': m['timing'], 'frequency': m['frequency'],
          'with_food': m['with_food'], 'condition_name': m['condition'],
          'active': 1, 'stock_count': m['stock_count'] ?? 0, 'synced': 1,
        });
      }
    } else {
      final local = await _db.getMedicines();
      setState(() => _medicines = local);
    }
    setState(() => _loading = false);
  }

  Future<void> _toggleTaken(dynamic med) async {
    final id = med['id'] as int;
    final newTaken = !(med['taken_today'] == true);
    await _db.logMedicineTaken(id, newTaken);
    if (SyncService().isOnline) await _api.logMedicineTaken(id, newTaken);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    final lowStock = _medicines.where((m) => (m['stock_count'] ?? 99) <= (m['low_stock_alert'] ?? 5)).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Medicines', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => _showAddSheet(isDark))],
        bottom: TabBar(controller: _tabs, labelColor: AppColors.medicine, unselectedLabelColor: tm, indicatorColor: AppColors.medicine,
            tabs: const [Tab(text: '💊 Today'), Tab(text: '📅 Adherence')]),
      ),
      body: _loading ? const LoadingView() : TabBarView(controller: _tabs, children: [
        _buildTodayTab(isDark, tp, tm, lowStock),
        _buildAdherenceTab(isDark, tp, tm),
      ]),
      bottomNavigationBar: const AppBottomNav(currentIndex: 4),
    );
  }

  Widget _buildTodayTab(bool isDark, Color tp, Color tm, List lowStock) {
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (lowStock.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.warning.withOpacity(0.3))),
              child: Row(children: [
                const Text('⚠️', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(child: Text('${lowStock.length} medicine(s) running low on stock', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.warning))),
              ]),
            ),
          if (_medicines.isEmpty)
            const EmptyState(emoji: '💊', title: 'No medicines added', subtitle: 'Tap + to add your first medicine')
          else
            ..._medicines.map((m) {
              final taken = m['taken_today'] == true;
              final stock = m['stock_count'] ?? 0;
              final lowStockFlag = stock <= (m['low_stock_alert'] ?? 5);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: taken ? AppColors.success.withOpacity(0.3) : brd)),
                child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                  GestureDetector(
                    onTap: () => _toggleTaken(m),
                    child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: 44, height: 44,
                      decoration: BoxDecoration(color: taken ? AppColors.success.withOpacity(0.15) : AppColors.medicine.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                      child: Icon(taken ? Icons.check_rounded : Icons.medication_rounded, color: taken ? AppColors.success : AppColors.medicine, size: 22)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m['name'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tp, decoration: taken ? TextDecoration.lineThrough : null)),
                    Text('${m['dosage'] ?? ''} · ${m['timing'] ?? ''}', style: TextStyle(fontSize: 12, color: tm)),
                    if (lowStockFlag) Padding(padding: const EdgeInsets.only(top: 4), child: Text('⚠️ $stock tablets left', style: const TextStyle(fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w700))),
                  ])),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: tm, size: 20),
                    onSelected: (a) { if (a == 'stock') _showStockSheet(m, isDark); else if (a == 'delete') _delete(m['id']); },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'stock', child: Text('📦 Update Stock')),
                      const PopupMenuItem(value: 'delete', child: Text('🗑️ Delete')),
                    ],
                  ),
                ])),
              );
            }),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildAdherenceTab(bool isDark, Color tp, Color tm) {
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: _medicines.map((m) {
        final adherence = (m['adherence_pct'] ?? 0).toDouble();
        final color = adherence >= 90 ? AppColors.success : adherence >= 70 ? AppColors.warning : AppColors.danger;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16), border: Border.all(color: brd)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(m['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: tp))),
              Text('${adherence.toInt()}%', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(100), child: LinearProgressIndicator(value: adherence / 100, minHeight: 8, backgroundColor: color.withOpacity(0.12), color: color)),
            const SizedBox(height: 6),
            Text('Last 30 days adherence', style: TextStyle(fontSize: 11, color: tm)),
          ]),
        );
      }).toList(),
    );
  }

  void _showStockSheet(dynamic med, bool isDark) {
    final ctrl = TextEditingController(text: '${med['stock_count'] ?? 0}');
    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('📦 Update Stock — ${med['name']}', style: const TextStyle(fontFamily: 'Fraunces', fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tablet count remaining')),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
            final v = int.tryParse(ctrl.text);
            if (v != null) {
              await _db.updateMedicineStock(med['id'], v);
              if (SyncService().isOnline) await _api.updateMedicineStock(med['id'], v);
            }
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          }, child: const Text('Save'))),
        ]),
      ),
    );
  }

  Future<void> _delete(int id) async {
    final ok = await showConfirmDialog(context, 'Delete Medicine', 'Remove this medicine permanently?');
    if (ok) { await _api.deleteMedicine(id); _load(); }
  }

  void _showAddSheet(bool isDark) {
    final nameCtrl = TextEditingController(), dosageCtrl = TextEditingController(), stockCtrl = TextEditingController();
    String timing = 'morning', frequency = 'daily', withFood = 'doesn\'t_matter';

    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (_, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('💊 Add Medicine', style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Medicine Name', hintText: 'e.g. Metformin')),
          const SizedBox(height: 10),
          TextField(controller: dosageCtrl, decoration: const InputDecoration(labelText: 'Dosage', hintText: 'e.g. 500mg')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: timing, decoration: const InputDecoration(labelText: 'Timing'),
            items: const [DropdownMenuItem(value: 'morning', child: Text('🌅 Morning')), DropdownMenuItem(value: 'afternoon', child: Text('☀️ Afternoon')), DropdownMenuItem(value: 'evening', child: Text('🌆 Evening')), DropdownMenuItem(value: 'night', child: Text('🌙 Night'))],
            onChanged: (v) => setSt(() => timing = v ?? 'morning')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: withFood, decoration: const InputDecoration(labelText: 'With Food'),
            items: const [DropdownMenuItem(value: 'before_food', child: Text('Before Food')), DropdownMenuItem(value: 'after_food', child: Text('After Food')), DropdownMenuItem(value: 'doesn\'t_matter', child: Text('Doesn\'t Matter'))],
            onChanged: (v) => setSt(() => withFood = v ?? 'doesn\'t_matter')),
          const SizedBox(height: 10),
          TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Current Stock (tablets)', hintText: '30')),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
            if (nameCtrl.text.trim().isEmpty) return;
            final resp = await _api.addMedicine({
              'name': nameCtrl.text.trim(), 'dosage': dosageCtrl.text.trim(), 'timing': timing,
              'frequency': frequency, 'with_food': withFood, 'stock_count': int.tryParse(stockCtrl.text) ?? 0,
            });
            if (ctx.mounted) Navigator.pop(ctx);
            if (resp.success) { _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success)); }
          }, child: const Text('💊 Add Medicine', style: TextStyle(fontWeight: FontWeight.bold)))),
        ])),
      )),
    );
  }
}