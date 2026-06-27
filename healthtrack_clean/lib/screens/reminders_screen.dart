// lib/screens/reminders_screen.dart — Smart Reminders + Offline-first + Dark Mode
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/notification_service.dart';
import '../services/local_db_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart' hide AppBottomNav;
import 'bp_tracker_screen.dart' show _SyncBadge;

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _api   = ApiService();
  final _sync  = SyncService();
  final _db    = LocalDb();
  List<dynamic> _reminders = [];
  bool _loading = true;

  static const _catIcons  = {'water':'💧','medicine':'💊','bp':'❤️','exercise':'🏃','sleep':'😴','sugar':'🩺','steps':'👟','custom':'🔔'};
  static const _catColors = {'water':AppColors.water,'medicine':AppColors.medicine,'bp':AppColors.danger,'exercise':AppColors.exercise,'sleep':AppColors.sleep,'sugar':AppColors.sugar,'steps':AppColors.info,'custom':AppColors.textMuted};

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Try server first; fall back to local cache
    if (_sync.isOnline) {
      final resp = await _api.getReminders();
      if (resp.success) {
        setState(() { _reminders = resp.data['reminders'] ?? []; _loading = false; });
        return;
      }
    }
    // Offline: use local DB cache
    final local = await _db.getCachedReminders();
    setState(() { _reminders = local; _loading = false; });
  }

  Future<void> _setupDefaults() async {
    final resp = await _api.setupDefaultReminders();
    if (resp.success) { await _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success)); }
  }

  Future<void> _markDone(dynamic id) async {
    // Offline-first: update local then sync
    await _db.markReminderDoneLocal(id is int ? id : int.tryParse(id.toString()) ?? 0);
    if (_sync.isOnline) await _api.markReminderDone(id is int ? id : int.parse(id.toString()));
    await NotificationService().markReminderDone(id is int ? id : int.parse(id.toString()));
    _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Done for today!'), backgroundColor: AppColors.success));
  }

  Future<void> _snooze(dynamic id) async {
    if (_sync.isOnline) await _api.snoozeReminder(id is int ? id : int.parse(id.toString()), 10);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⏰ Snoozed 10 min'), backgroundColor: AppColors.warning));
  }

  Future<void> _delete(dynamic id) async {
    final ok = await showConfirmDialog(context, 'Delete Reminder', 'Remove this reminder?');
    if (!ok) return;
    if (_sync.isOnline) await _api.deleteReminder(id is int ? id : int.parse(id.toString()));
    _load();
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
        title: const Text('Reminders', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [
          SyncBadge(_sync.isOnline),
          if (_reminders.isEmpty)
            TextButton(onPressed: _setupDefaults, child: const Text('Quick Setup', style: TextStyle(color: AppColors.sage, fontWeight: FontWeight.w700))),
          IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => _showAddSheet(isDark, card, brd, tp, tm)),
        ],
      ),
      body: Column(children: [

        // Info banner
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.mint.withOpacity(isDark ? 0.1 : 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.mint.withOpacity(0.25)),
          ),
          child: Row(children: [
            const Text('💡', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Repeats with sound every few minutes until you tap "Done ✓". Resets at midnight. Works offline.',
              style: TextStyle(fontSize: 12, color: isDark ? AppColors.mint : AppColors.sage, fontWeight: FontWeight.w600, height: 1.4),
            )),
          ]),
        ),

        Expanded(child: _loading
            ? const LoadingView()
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.sage,
                child: _reminders.isEmpty
                    ? EmptyState(
                        emoji: '⏰', title: 'No reminders yet',
                        subtitle: 'Set up 8 smart defaults — water, BP, medicine, exercise, sleep.',
                        action: ElevatedButton(onPressed: _setupDefaults, child: const Text('⚡ Quick Setup (8 Defaults)')),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _reminders.length,
                        itemBuilder: (_, i) {
                          final r       = _reminders[i];
                          final cat     = r['category'] ?? 'custom';
                          final color   = _catColors[cat] ?? AppColors.textMuted;
                          final icon    = _catIcons[cat] ?? '🔔';
                          final active  = r['is_active'] == true || r['is_active'] == 1;
                          final done    = r['is_done_today'] == true || r['is_done_today'] == 1;

                          return AnimatedOpacity(
                            opacity: active ? 1.0 : 0.45,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: card,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: done ? AppColors.success.withOpacity(0.3) : brd),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [

                                  // Icon
                                  Container(width: 46, height: 46, decoration: BoxDecoration(color: color.withOpacity(isDark ? 0.2 : 0.1), borderRadius: BorderRadius.circular(14)),
                                      child: Center(child: Text(icon, style: const TextStyle(fontSize: 20)))),
                                  const SizedBox(width: 12),

                                  // Info
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(r['title'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tp)),
                                    const SizedBox(height: 4),
                                    Wrap(spacing: 6, runSpacing: 4, children: [
                                      _Tag('⏰ ${r['remind_time'] ?? ''}', color),
                                      _Tag('🔁 ${r['repeat_interval_mins'] ?? 5}min', color),
                                      if (r['sound_name'] != null) _Tag('🔊 ${r['sound_name'].toString().replaceAll('_',' ')}', tm),
                                      if (done) _Tag('✓ Done today', AppColors.success, bgColor: AppColors.success.withOpacity(0.12)),
                                    ]),
                                  ])),

                                  // Actions
                                  PopupMenuButton<String>(
                                    icon: Icon(Icons.more_vert_rounded, size: 20, color: tm),
                                    color: card,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    onSelected: (action) {
                                      if (action == 'done')   _markDone(r['id']);
                                      else if (action == 'snooze') _snooze(r['id']);
                                      else if (action == 'delete') _delete(r['id']);
                                    },
                                    itemBuilder: (_) => [
                                      if (!done) PopupMenuItem(value: 'done', child: Row(children: [const Text('✓  '), Text('Mark Done', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600))])),
                                      PopupMenuItem(value: 'snooze', child: Row(children: [const Text('⏰  '), Text('Snooze 10 min', style: TextStyle(color: tp))])),
                                      PopupMenuItem(value: 'delete', child: Row(children: [const Text('🗑️  '), Text('Delete', style: TextStyle(color: AppColors.danger))])),
                                    ],
                                  ),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
              ),
        ),
      ]),
    );
  }

  void _showAddSheet(bool isDark, Color card, Color brd, Color tp, Color tm) {
    final titleCtrl   = TextEditingController();
    String category   = 'water';
    String sound      = 'health_alert';
    int    interval   = 5;
    TimeOfDay selTime = const TimeOfDay(hour: 8, minute: 0);

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Handle
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('⏰ New Reminder', style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900, color: tp)),
            const SizedBox(height: 16),
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Drink Water')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _catIcons.entries.map((e) => DropdownMenuItem(value: e.key, child: Text('${e.value} ${e.key[0].toUpperCase()}${e.key.substring(1)}'))).toList(),
              onChanged: (v) => setSt(() => category = v ?? 'water'),
            ),
            const SizedBox(height: 10),
            ListTile(contentPadding: EdgeInsets.zero,
              title: Text('Reminder Time', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tm)),
              trailing: TextButton(
                onPressed: () async { final t = await showTimePicker(context: context, initialTime: selTime); if (t != null) setSt(() => selTime = t); },
                child: Text(selTime.format(context), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.sage)))),
            const SizedBox(height: 6),
            Text('Repeat Interval', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tm)),
            const SizedBox(height: 8),
            Row(children: [3, 5, 10].map((m) {
              final sel = interval == m;
              return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: GestureDetector(
                onTap: () => setSt(() => interval = m),
                child: AnimatedContainer(duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.sage.withOpacity(isDark ? 0.2 : 0.1) : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sel ? AppColors.sage : Colors.transparent, width: 2)),
                  child: Column(children: [
                    Text('$m', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: sel ? AppColors.sage : tm)),
                    Text('min', style: TextStyle(fontSize: 10, color: sel ? AppColors.sage : tm, fontWeight: FontWeight.w600)),
                  ]),
                ),
              )));
            }).toList()),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: sound,
              decoration: const InputDecoration(labelText: '🔊 Sound'),
              items: const [
                DropdownMenuItem(value: 'health_alert', child: Text('Health Alert')),
                DropdownMenuItem(value: 'water_drop',   child: Text('Water Drop')),
                DropdownMenuItem(value: 'medicine',     child: Text('Medicine Bell')),
                DropdownMenuItem(value: 'gentle',       child: Text('Gentle Chime')),
                DropdownMenuItem(value: 'urgent',       child: Text('Urgent Alert')),
              ],
              onChanged: (v) => setSt(() => sound = v ?? 'health_alert'),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                final resp = await _api.createReminder({
                  'title': titleCtrl.text.trim(), 'category': category,
                  'remind_time': '${selTime.hour.toString().padLeft(2,'0')}:${selTime.minute.toString().padLeft(2,'0')}',
                  'repeat_interval_mins': interval, 'sound_name': sound,
                  'sound_enabled': true, 'is_active': true, 'is_daily': true, 'max_repeats': 10,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (resp.success) { _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success)); }
              },
              child: const Text('⏰ Create Reminder', style: TextStyle(fontWeight: FontWeight.bold)),
            )),
          ])),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text; final Color color; final Color? bgColor;
  const _Tag(this.text, this.color, {this.bgColor});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: bgColor ?? color.withOpacity(0.1), borderRadius: BorderRadius.circular(100)),
    child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
  );
}