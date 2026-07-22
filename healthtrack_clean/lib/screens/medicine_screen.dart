// lib/screens/medicine_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart';

class MedicineScreen extends StatefulWidget {
  const MedicineScreen({super.key});

  @override
  State<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends State<MedicineScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Medicines',
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.medicine,
          unselectedLabelColor:
              isDark ? AppColors.textMutedDark : AppColors.textMuted,
          indicatorColor: AppColors.medicine,
          tabs: const [
            Tab(text: '💊 Today'),
            Tab(text: '📅 Adherence'),
            Tab(text: '⚙️ Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _TodayTab(),
          _AdherenceTab(),
          _SettingsTab(),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 4),
    );
  }
}

class _TodayTab extends StatefulWidget {
  const _TodayTab();

  @override
  State<_TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<_TodayTab> {
  final _api = ApiService();
  final _picker = ImagePicker();
  final _searchCtrl = TextEditingController();

  Map<String, dynamic>? _dash;
  List<dynamic> _meds = [];
  bool _loading = true;

  String _filterStatus = 'all';
  String _filterSchedule = 'all';
  String _sortBy = 'time';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final results = await Future.wait([
      _api.getMedicines(),
      _api.get('/medicines/dashboard'),
    ]);

    if (results[0].success) {
      _meds = results[0].data['medicines'] ?? [];
    }
    if (results[1].success) {
      _dash = results[1].data;
    }

    if (_sortBy == 'name') {
      _meds.sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  List<dynamic> get _filtered {
    var list = List<dynamic>.from(_meds);

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((m) => (m['name'] ?? '').toString().toLowerCase().contains(q))
          .toList();
    }

    if (_filterStatus != 'all') {
      list = list.where((m) => m['today_status'] == _filterStatus).toList();
    }

    if (_filterSchedule != 'all') {
      list = list.where((m) => m['schedule_type'] == _filterSchedule).toList();
    }

    if (_sortBy == 'name') {
      list.sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));
    }

    return list;
  }

  Future<void> _action(dynamic med, String action) async {
    if (action == 'taken' || action == 'skip' || action == 'missed') {
      await _api.logMedicineTaken(med['id'], action == 'taken');
      await _api.post(
        '/medicines/${med['id']}/log',
        data: {'action': action},
      );
      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'taken'
                ? '✅ ${med['name']} marked as taken'
                : action == 'skip'
                    ? '⚪ Dose skipped'
                    : '🔴 Dose missed',
          ),
          backgroundColor: action == 'taken'
              ? AppColors.success
              : action == 'skip'
                  ? AppColors.textMuted
                  : AppColors.danger,
        ),
      );
    } else if (action == 'snooze') {
      await _showSnoozeDialog(med);
    } else if (action == 'ai_verify') {
      await _runAiVerification(med);
    } else if (action == 'stock') {
      _showStockSheet(med);
    } else if (action == 'edit') {
      _showEditSheet(med);
    } else if (action == 'delete') {
      await _confirmDelete(med);
    }
  }

  Future<void> _showSnoozeDialog(dynamic med) async {
    final options = [5, 10, 15, 30, 60];

    await showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('⏰ Remind Me Later'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options
                .map(
                  (m) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.timer_rounded, size: 18),
                    title: Text('In $m minutes'),
                    onTap: () async {
                      Navigator.pop(context);
                      await _api.post(
                        '/medicines/${med['id']}/log',
                        data: {
                          'action': 'snooze',
                          'snooze_minutes': m,
                        },
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('⏰ Reminder in $m min'),
                          backgroundColor: AppColors.info,
                        ),
                      );
                    },
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Future<void> _runAiVerification(dynamic med) async {
    final img = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 800,
    );
    if (img == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🤖 Verifying...'),
          duration: Duration(seconds: 3),
        ),
      );
    }

    final bytes = await File(img.path).readAsBytes();
    final resp = await _api.post(
      '/medicines/${med['id']}/verify',
      data: {'image': base64Encode(bytes)},
    );

    if (resp.success) {
      await _load();
      final verified = resp.data['verified'] == true;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            verified
                ? '🟢 AI Verified: Medicine confirmed in photo'
                : '⚠️ AI could not confirm this medicine',
          ),
          backgroundColor:
              verified ? AppColors.success : AppColors.warning,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _confirmDelete(dynamic med) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Text('💊 ', style: TextStyle(fontSize: 22)),
              Text('Delete Medicine?'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to permanently delete ${med['name']}?',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.danger.withOpacity(0.2),
                  ),
                ),
                child: const Text(
                  'This action cannot be undone.\nAll history and reminders for this medicine will also be deleted.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.danger,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      await _api.deleteMedicine(med['id']);
      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🗑️ ${med['name']} deleted'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _showStockSheet(dynamic med) {
    final ctrl = TextEditingController(text: '${med['stock_count'] ?? 0}');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '📦 Update Stock — ${med['name']}',
                style: const TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Tablets remaining',
                  suffixText: med['type_label'] ?? 'units',
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final v = int.tryParse(ctrl.text);
                    if (v == null) return;

                    await _api.updateMedicineStock(med['id'], v);
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                  },
                  child: const Text(
                    'Save Stock',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditSheet(dynamic med) => _showAddSheet(existing: med);

  void _showAddSheet({dynamic existing}) {
    if (_dash?['can_add'] == false && existing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🔒 Limit reached (${_dash!['used']}/${_dash!['limit']}). Upgrade for more.',
          ),
          backgroundColor: AppColors.warning,
          action: SnackBarAction(
            label: 'Upgrade',
            textColor: Colors.white,
            onPressed: () => Navigator.pushNamed(context, '/plans'),
          ),
        ),
      );
      return;
    }

    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final doseCtrl = TextEditingController(text: existing?['dosage'] ?? '');
    final stockCtrl =
        TextEditingController(text: '${existing?['stock_count'] ?? 0}');
    final notesCtrl = TextEditingController(text: existing?['notes'] ?? '');

    String medType = existing?['medicine_type'] ?? 'tablet';
    String withFood = existing?['with_food'] ?? 'after_food';
    String schedule = existing?['schedule_type'] ?? 'morning';
    List<String> customTimes =
        List<String>.from(existing?['custom_times'] ?? []);
    int threshold = existing?['low_stock_threshold'] ?? 5;
    bool autoReduce = existing?['auto_reduce_stock'] ?? true;
    bool reminder = existing?['reminder_enabled'] ?? true;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (_, setSt) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      existing == null
                          ? '💊 Add Medicine'
                          : '✏️ Edit ${existing['name']}',
                      style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Medicine Name *',
                        hintText: 'e.g. Paracetamol',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: doseCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Dosage',
                              hintText: '500mg',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: medType,
                            decoration:
                                const InputDecoration(labelText: 'Type'),
                            items: const {
                              'tablet': '💊 Tablet',
                              'capsule': '💊 Capsule',
                              'syrup': '🥄 Syrup',
                              'injection': '💉 Injection',
                              'drops': '💧 Drops',
                              'inhaler': '🫁 Inhaler',
                              'ointment': '🧴 Ointment',
                              'powder': '🥄 Powder',
                              'other': '📦 Other',
                            }.entries.map((e) {
                              return DropdownMenuItem<String>(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            }).toList(),
                            onChanged: (v) => setSt(() => medType = v ?? 'tablet'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: withFood,
                      decoration: const InputDecoration(labelText: 'With Food'),
                      items: const [
                        DropdownMenuItem(
                          value: 'before_food',
                          child: Text('Before Food'),
                        ),
                        DropdownMenuItem(
                          value: 'after_food',
                          child: Text('After Food'),
                        ),
                        DropdownMenuItem(
                          value: 'doesnt_matter',
                          child: Text("Doesn't Matter"),
                        ),
                      ],
                      onChanged: (v) =>
                          setSt(() => withFood = v ?? 'after_food'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: schedule,
                      decoration: const InputDecoration(labelText: 'Schedule'),
                      items: const [
                        DropdownMenuItem(
                          value: 'morning',
                          child: Text('🌅 Morning (8:00 AM)'),
                        ),
                        DropdownMenuItem(
                          value: 'afternoon',
                          child: Text('☀️ Afternoon (1:00 PM)'),
                        ),
                        DropdownMenuItem(
                          value: 'evening',
                          child: Text('🌆 Evening (6:00 PM)'),
                        ),
                        DropdownMenuItem(
                          value: 'night',
                          child: Text('🌙 Night (9:30 PM)'),
                        ),
                        DropdownMenuItem(
                          value: 'custom',
                          child: Text('⏰ Custom Time(s)'),
                        ),
                      ],
                      onChanged: (v) =>
                          setSt(() => schedule = v ?? 'morning'),
                    ),
                    if (schedule == 'custom') ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          ...customTimes.map(
                            (t) => Chip(
                              label: Text(t),
                              onDeleted: () =>
                                  setSt(() => customTimes.remove(t)),
                            ),
                          ),
                          ActionChip(
                            label: const Text('+ Add Time'),
                            onPressed: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime:
                                    const TimeOfDay(hour: 8, minute: 0),
                              );
                              if (t != null) {
                                setSt(() {
                                  customTimes.add(
                                    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                                  );
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: stockCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Current Stock',
                              hintText: '30',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Low Stock Alert',
                              hintText: '$threshold',
                            ),
                            onChanged: (v) =>
                                threshold = int.tryParse(v) ?? 5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Auto-reduce stock on taken',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: autoReduce,
                      onChanged: (v) => setSt(() => autoReduce = v),
                      activeColor: AppColors.sage,
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Enable reminders',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: reminder,
                      onChanged: (v) => setSt(() => reminder = v),
                      activeColor: AppColors.sage,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (nameCtrl.text.trim().isEmpty) return;

                          final data = {
                            'name': nameCtrl.text.trim(),
                            'dosage': doseCtrl.text.trim(),
                            'medicine_type': medType,
                            'with_food': withFood,
                            'schedule_type': schedule,
                            'custom_times': customTimes,
                            'stock_count': int.tryParse(stockCtrl.text) ?? 0,
                            'low_stock_threshold': threshold,
                            'auto_reduce_stock': autoReduce,
                            'reminder_enabled': reminder,
                            'notes': notesCtrl.text.trim(),
                          };

                          ApiResponse resp;
                          if (existing != null) {
                            resp = await _api.put(
                              '/medicines/${existing['id']}',
                              data: data,
                            );
                          } else {
                            resp = await _api.addMedicine(data);
                          }

                          if (ctx.mounted) Navigator.pop(ctx);

                          if (resp.success) {
                            await _load();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('✅ ${resp.message}'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('❌ ${resp.message}'),
                                backgroundColor: AppColors.danger,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.medicine,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          existing == null
                              ? '💊 Add Medicine'
                              : '✅ Save Changes',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          if (_dash != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _DashCard(
                          '💊',
                          '${_dash!['total'] ?? 0}',
                          'Total',
                          AppColors.medicine,
                          isDark,
                        ),
                        const SizedBox(width: 8),
                        _DashCard(
                          '🟡',
                          '${_dash!['pending'] ?? 0}',
                          'Pending',
                          AppColors.warning,
                          isDark,
                        ),
                        const SizedBox(width: 8),
                        _DashCard(
                          '🔵',
                          '${_dash!['taken'] ?? 0}',
                          'Taken',
                          AppColors.info,
                          isDark,
                        ),
                        const SizedBox(width: 8),
                        _DashCard(
                          '🔴',
                          '${_dash!['missed'] ?? 0}',
                          'Missed',
                          AppColors.danger,
                          isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: brd),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Today's Medicines",
                                  style: TextStyle(
                                    fontFamily: 'Fraunces',
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: tp,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(100),
                                  child: LinearProgressIndicator(
                                    value:
                                        ((_dash!['completion_pct'] as num?) ?? 0) /
                                            100,
                                    minHeight: 10,
                                    color: AppColors.success,
                                    backgroundColor: AppColors.success
                                        .withOpacity(0.1),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_dash!['completion_pct'] ?? 0}% complete',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: tm,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          if ((_dash!['low_stock'] as int? ?? 0) > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.warning.withOpacity(0.3),
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    '📦',
                                    style: TextStyle(fontSize: 20),
                                  ),
                                  Text(
                                    '${_dash!['low_stock']}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                  const Text(
                                    'Low',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.warning,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_dash!['limit'] != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: brd),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_dash!['used']}/${_dash!['limit']} medicines (${(_dash!['plan'] as String? ?? 'free').toUpperCase()} plan)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tm,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (_dash!['can_add'] == false)
                              GestureDetector(
                                onTap: () =>
                                    Navigator.pushNamed(context, '/plans'),
                                child: const Text(
                                  'Upgrade →',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.violet,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '🔍 Search medicines...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final s in const [
                          ('all', 'All'),
                          ('pending', '🟡 Pending'),
                          ('taken', '🔵 Taken'),
                          ('ai_verified', '🟢 Verified'),
                          ('missed', '🔴 Missed'),
                          ('skipped', '⚪ Skipped'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _filterStatus = s.$1),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _filterStatus == s.$1
                                      ? AppColors.medicine
                                      : (isDark
                                          ? const Color(0xFF1A2E45)
                                          : Colors.grey.shade100),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  s.$2,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _filterStatus == s.$1
                                        ? Colors.white
                                        : tm,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _filterSchedule,
                          decoration: const InputDecoration(
                            labelText: 'Schedule',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All')),
                            DropdownMenuItem(
                                value: 'morning', child: Text('Morning')),
                            DropdownMenuItem(
                                value: 'afternoon', child: Text('Afternoon')),
                            DropdownMenuItem(
                                value: 'evening', child: Text('Evening')),
                            DropdownMenuItem(value: 'night', child: Text('Night')),
                            DropdownMenuItem(
                                value: 'custom', child: Text('Custom')),
                          ],
                          onChanged: (v) =>
                              setState(() => _filterSchedule = v ?? 'all'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _sortBy,
                          decoration: const InputDecoration(labelText: 'Sort'),
                          items: const [
                            DropdownMenuItem(value: 'time', child: Text('By Time')),
                            DropdownMenuItem(value: 'name', child: Text('By Name')),
                          ],
                          onChanged: (v) =>
                              setState(() => _sortBy = v ?? 'time'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(child: LoadingView())
          else if (_filtered.isEmpty)
            SliverFillRemaining(
              child: EmptyState(
                emoji: '💊',
                title: 'No medicines',
                subtitle: 'Tap + to add a medicine',
                action: _dash?['can_add'] == true
                    ? ElevatedButton(
                        onPressed: () => _showAddSheet(),
                        child: const Text('+ Add Medicine'),
                      )
                    : null,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _MedicineCard(
                    med: _filtered[i],
                    isDark: isDark,
                    card: card,
                    brd: brd,
                    tp: tp,
                    tm: tm,
                    isPremium: _dash?['is_premium'] == true,
                    onAction: _action,
                  ),
                  childCount: _filtered.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

class _MedicineCard extends StatelessWidget {
  final dynamic med;
  final bool isDark;
  final bool isPremium;
  final Color card;
  final Color brd;
  final Color tp;
  final Color tm;
  final Future<void> Function(dynamic, String) onAction;

  const _MedicineCard({
    required this.med,
    required this.isDark,
    required this.isPremium,
    required this.card,
    required this.brd,
    required this.tp,
    required this.tm,
    required this.onAction,
  });

  static const _statusConfig = {
    'pending': ('🟡', 'Pending', Color(0xFFF59E0B)),
    'taken': ('🔵', 'Taken', Color(0xFF3B82F6)),
    'ai_verified': ('🟢', 'AI Verified', Color(0xFF22C55E)),
    'missed': ('🔴', 'Missed', Color(0xFFEF4444)),
    'skipped': ('⚪', 'Skipped', Color(0xFF9CA3AF)),
  };

  @override
  Widget build(BuildContext context) {
    final status = med['today_status'] ?? 'pending';
    final cfg = _statusConfig[status] ?? _statusConfig['pending']!;
    final isDone = status == 'taken' || status == 'ai_verified';
    final lowStock = med['low_stock_alert'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDone ? cfg.$3.withOpacity(isDark ? 0.12 : 0.05) : card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDone
              ? cfg.$3.withOpacity(0.3)
              : (lowStock
                  ? AppColors.warning.withOpacity(0.4)
                  : brd),
          width: isDone || lowStock ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: isDone ? null : () => onAction(med, 'taken'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: cfg.$3.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        cfg.$1,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med['name'] ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: tp,
                          decoration:
                              isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (med['dosage'] != null &&
                              med['dosage'].toString().isNotEmpty)
                            Text(
                              '${med['dosage']} · ',
                              style: TextStyle(fontSize: 12, color: tm),
                            ),
                          Text(
                            med['type_label'] ?? '',
                            style: TextStyle(fontSize: 12, color: tm),
                          ),
                          Text(
                            ' · ${_foodLabel(med['with_food'])}',
                            style: TextStyle(fontSize: 12, color: tm),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cfg.$3.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              '${cfg.$1} ${cfg.$2}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: cfg.$3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _scheduleLabel(med),
                              style: TextStyle(
                                fontSize: 10,
                                color: tm,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: tm, size: 20),
                  color: card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (a) => onAction(med, a),
                  itemBuilder: (_) => [
                    if (!isDone)
                      const PopupMenuItem(
                        value: 'taken',
                        child: Text('✅  Mark as Taken'),
                      ),
                    if (!isDone)
                      const PopupMenuItem(
                        value: 'snooze',
                        child: Text('⏰  Snooze'),
                      ),
                    if (!isDone)
                      const PopupMenuItem(
                        value: 'skip',
                        child: Text('⏭️  Skip Dose'),
                      ),
                    if (status == 'taken' || status == 'ai_verified')
                      PopupMenuItem(
                        value: 'ai_verify',
                        enabled: isPremium,
                        child: Text(
                          isPremium
                              ? '🤖  AI Verify Photo'
                              : '🔒  AI Verify (Premium)',
                          style: TextStyle(
                            color: isPremium ? null : AppColors.textMuted,
                          ),
                        ),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'stock',
                      child: Text('📦  Update Stock'),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('✏️  Edit'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        '🗑️  Delete',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (!isDone) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => onAction(med, 'taken'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '✅ Taken',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => onAction(med, 'snooze'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: BorderSide(
                          color: AppColors.warning.withOpacity(0.5),
                        ),
                      ),
                      child: const Text(
                        '⏰ Snooze',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => onAction(med, 'skip'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: BorderSide(
                          color: Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      child: const Text(
                        '⏭️ Skip',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (lowStock) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.warning.withOpacity(0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Text('📦', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Low stock: ${med['stock_count']} ${med['type_label'] ?? 'units'} remaining',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => onAction(med, 'stock'),
                      child: const Text(
                        'Update →',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (status == 'ai_verified') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Text('🟢', style: TextStyle(fontSize: 14)),
                    SizedBox(width: 6),
                    Text(
                      'AI Verified — medicine confirmed in photo',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _foodLabel(dynamic v) {
    const map = {
      'before_food': 'Before Food',
      'after_food': 'After Food',
      'doesnt_matter': 'Anytime',
    };
    return map[v?.toString()] ?? '';
  }

  String _scheduleLabel(dynamic m) {
    final s = m['schedule_type'] ?? 'morning';
    if (s == 'custom') {
      return (m['custom_times'] as List?)?.join(', ') ?? 'Custom';
    }
    const map = {
      'morning': '🌅 8:00 AM',
      'afternoon': '☀️ 1:00 PM',
      'evening': '🌆 6:00 PM',
      'night': '🌙 9:30 PM',
    };
    return map[s] ?? s;
  }
}

class _AdherenceTab extends StatefulWidget {
  const _AdherenceTab();

  @override
  State<_AdherenceTab> createState() => _AdherenceTabState();
}

class _AdherenceTabState extends State<_AdherenceTab> {
  final _api = ApiService();

  List<dynamic> _meds = [];
  bool _loading = true;
  int? _selectedMedId;
  Map<String, dynamic>? _history;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final r = await _api.getMedicines();
    if (r.success) {
      _meds = r.data['medicines'] ?? [];
      if (_meds.isNotEmpty && _selectedMedId == null) {
        await _selectMed(_meds[0]['id']);
      }
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _selectMed(int id) async {
    setState(() => _selectedMedId = id);
    final r = await _api.getMedicineAdherence(id, days: 30);
    if (r.success && mounted) {
      setState(() => _history = r.data);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    if (_loading) return const LoadingView();
    if (_meds.isEmpty) {
      return const EmptyState(
        emoji: '💊',
        title: 'No medicines',
        subtitle: 'Add medicines to see adherence',
      );
    }

    final calendar = _history?['calendar'] as List? ?? [];
    final adh = (_history?['adherence_pct'] as num?)?.toDouble() ?? 0;
    final color = adh >= 90
        ? AppColors.success
        : adh >= 70
            ? AppColors.warning
            : AppColors.danger;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _meds.map((m) {
              final sel = m['id'] == _selectedMedId;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _selectMed(m['id']),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: sel
                          ? AppColors.medicine
                          : (isDark
                              ? const Color(0xFF1A2E45)
                              : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: sel ? AppColors.medicine : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      m['name'],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: sel ? Colors.white : tm,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: brd),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '30-Day Adherence',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: tp,
                    ),
                  ),
                  Text(
                    '${adh.toInt()}%',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: adh / 100),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 10,
                      color: color,
                      backgroundColor: color.withOpacity(0.1),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _HistStat(
                    '🔵',
                    '${_history?['taken_count'] ?? 0}',
                    'Taken',
                    AppColors.info,
                  ),
                  _HistStat(
                    '🔴',
                    '${_history?['missed_count'] ?? 0}',
                    'Missed',
                    AppColors.danger,
                  ),
                  _HistStat(
                    '⚪',
                    '${_history?['skipped_count'] ?? 0}',
                    'Skipped',
                    AppColors.textMuted,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (calendar.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: brd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📅 Calendar',
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: tp,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: calendar.map((c) {
                    const colors = {
                      'pending': AppColors.warning,
                      'taken': AppColors.info,
                      'ai_verified': AppColors.success,
                      'missed': AppColors.danger,
                      'skipped': AppColors.textMuted,
                    };
                    final col = colors[c['status']] ?? AppColors.textMuted;

                    return Tooltip(
                      message: '${c['date']}: ${c['status']}',
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: col.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: col.withOpacity(0.4)),
                        ),
                        child: Center(
                          child: Text(
                            c['emoji'] ?? '🟡',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: const [
                    _CalLegend('🔵', 'Taken', AppColors.info),
                    _CalLegend('🟢', 'AI Verified', AppColors.success),
                    _CalLegend('🔴', 'Missed', AppColors.danger),
                    _CalLegend('⚪', 'Skipped', AppColors.textMuted),
                    _CalLegend('🟡', 'Pending', AppColors.warning),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final _api = ApiService();
  Map<String, dynamic>? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.get('/medicines/settings');
    if (r.success) {
      setState(() {
        _settings = r.data;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _save(String key, dynamic value) async {
    setState(() => _settings?[key] = value);
    await _api.post('/medicines/settings', data: {key: value});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    if (_loading) return const LoadingView();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _SettSection(
          '🔔 Notifications',
          card,
          brd,
          children: [
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(
                'Enable Reminders',
                style: TextStyle(fontSize: 14, color: tp),
              ),
              subtitle: Text(
                'Notify when medicine is due',
                style: TextStyle(fontSize: 11, color: tm),
              ),
              value: _settings?['notifications_enabled'] ?? true,
              activeColor: AppColors.sage,
              onChanged: (v) => _save('notifications_enabled', v),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(
                'Reminder Sound',
                style: TextStyle(fontSize: 14, color: tp),
              ),
              trailing: DropdownButton<String>(
                value: _settings?['reminder_sound'] ?? 'medicine',
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(
                    value: 'medicine',
                    child: Text('🔔 Medicine'),
                  ),
                  DropdownMenuItem(
                    value: 'health_alert',
                    child: Text('🔔 Alert'),
                  ),
                  DropdownMenuItem(
                    value: 'gentle',
                    child: Text('🔔 Gentle'),
                  ),
                ],
                onChanged: (v) => _save('reminder_sound', v),
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(
                'Snooze Duration',
                style: TextStyle(fontSize: 14, color: tp),
              ),
              trailing: DropdownButton<int>(
                value: _settings?['snooze_duration'] ?? 10,
                underline: const SizedBox(),
                items: [5, 10, 15, 30]
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text('$m min'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => _save('snooze_duration', v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SettSection(
          '📦 Stock Management',
          card,
          brd,
          children: [
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(
                'Auto-Reduce Stock',
                style: TextStyle(fontSize: 14, color: tp),
              ),
              subtitle: Text(
                'Reduce count when marked as taken',
                style: TextStyle(fontSize: 11, color: tm),
              ),
              value: _settings?['auto_stock_reduction'] ?? true,
              activeColor: AppColors.sage,
              onChanged: (v) => _save('auto_stock_reduction', v),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(
                'Low Stock Threshold',
                style: TextStyle(fontSize: 14, color: tp),
              ),
              subtitle: Text(
                'Alert when stock falls to this level',
                style: TextStyle(fontSize: 11, color: tm),
              ),
              trailing: DropdownButton<int>(
                value: _settings?['low_stock_threshold'] ?? 5,
                underline: const SizedBox(),
                items: [3, 5, 7, 10, 14, 30]
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text('$v units'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => _save('low_stock_threshold', v),
              ),
            ),
          ],
        ),
        if (_settings?['escalating_reminders'] == true) ...[
          const SizedBox(height: 12),
          _SettSection(
            '⭐ Smart Reminders (Premium)',
            card,
            brd,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Text('🔄', style: TextStyle(fontSize: 20)),
                title: Text(
                  'Escalating reminders active',
                  style: TextStyle(fontSize: 14, color: tp),
                ),
                subtitle: Text(
                  'Reminds every 10 min up to 3 times if not taken',
                  style: TextStyle(fontSize: 11, color: tm),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }
}

class _DashCard extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final Color color;
  final bool isDark;

  const _DashCard(
    this.emoji,
    this.value,
    this.label,
    this.color,
    this.isDark,
  );

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: color.withOpacity(0.8),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistStat extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final Color color;

  const _HistStat(this.emoji, this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CalLegend extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;

  const _CalLegend(this.emoji, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SettSection extends StatelessWidget {
  final String title;
  final Color card;
  final Color brd;
  final List<Widget> children;

  const _SettSection(
    this.title,
    this.card,
    this.brd, {
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}