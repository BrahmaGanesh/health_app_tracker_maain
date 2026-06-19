// ============================================================
// lib/screens/reminders_screen.dart — Smart Repeating Reminders
// ============================================================

import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/common_widgets.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _api = ApiService();

  List<dynamic> _reminders = [];
  bool _loading = true;

  final _catIcons = {
    'water': '💧',
    'medicine': '💊',
    'bp': '❤️',
    'exercise': '🏃',
    'sleep': '😴',
    'sugar': '🩺',
    'steps': '👟',
    'custom': '🔔'
  };

  final _catColors = {
    'water': AppColors.water,
    'medicine': AppColors.medicine,
    'bp': AppColors.danger,
    'exercise': AppColors.exercise,
    'sleep': AppColors.sleep,
    'sugar': AppColors.warning,
    'steps': AppColors.info,
    'custom': AppColors.textMuted
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final resp = await _api.getReminders();

    if (resp.success) {
      _reminders = resp.data['reminders'] ?? [];
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _setupDefaults() async {
    final resp = await _api.setupDefaultReminders();

    if (resp.success) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${resp.message}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _markDone(int id) async {
    await NotificationService().markReminderDone(id);
    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Marked done for today!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _snooze(int id) async {
    await NotificationService().snoozeReminder(id, minutes: 10);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏰ Snoozed for 10 minutes'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  Future<void> _delete(int id) async {
    final confirm = await showConfirmDialog(
      context,
      'Delete Reminder',
      'Remove this reminder permanently?',
    );

    if (!confirm) return;

    await _api.deleteReminder(id);
    await _load();
  }

  Future<void> _toggle(int id, bool current) async {
    await _api.updateReminder(id, {'is_active': !current});
    await _load();
  }

  void _showAddSheet() {
    final titleCtrl = TextEditingController();
    final messageCtrl = TextEditingController();

    String category = 'water';
    String sound = 'health_alert';
    int interval = 5;

    TimeOfDay selectedTime = const TimeOfDay(hour: 8, minute: 0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSt) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '⏰ New Reminder',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    TextField(controller: titleCtrl),
                    TextField(controller: messageCtrl),

                    DropdownButtonFormField<String>(
                      value: category,
                      items: _catIcons.keys.map((c) {
                        return DropdownMenuItem(
                          value: c,
                          child: Text(c),
                        );
                      }).toList(),
                      onChanged: (v) => setSt(() => category = v ?? 'water'),
                    ),

                    ListTile(
                      title: const Text('Reminder Time'),
                      trailing: TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );
                          if (t != null) {
                            setSt(() => selectedTime = t);
                          }
                        },
                        child: Text(selectedTime.format(context)),
                      ),
                    ),

                    Row(
                      children: [3, 5, 10].map((mins) {
                        final sel = interval == mins;

                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setSt(() => interval = mins),
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: sel
                                    ? Colors.green.withOpacity(0.2)
                                    : Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                children: [
                                  Text('$mins'),
                                  const Text('min'),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    ElevatedButton(
                      onPressed: () async {
                        if (titleCtrl.text.trim().isEmpty) return;

                        final resp = await _api.createReminder({
                          'title': titleCtrl.text.trim(),
                          'message': messageCtrl.text.trim(),
                          'category': category,
                          'remind_time':
                              '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                          'repeat_interval_mins': interval,
                          'sound_name': sound,
                          'sound_enabled': true,
                          'is_active': true,
                          'is_daily': true,
                          'max_repeats': 10,
                        });

                        if (ctx.mounted) Navigator.pop(ctx);

                        if (resp.success && mounted) {
                          await _load();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✅ ${resp.message}'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      },
                      child: const Text('Create Reminder'),
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
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          if (_reminders.isEmpty)
            TextButton(
              onPressed: _setupDefaults,
              child: const Text('Quick Setup'),
            ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reminders.isEmpty
              ? const Center(child: Text("No reminders"))
              : ListView.builder(
                  itemCount: _reminders.length,
                  itemBuilder: (context, i) {
                    final r = _reminders[i];

                    final cat = r['category'] ?? 'custom';
                    final color = _catColors[cat] ?? Colors.grey;
                    final icon = _catIcons[cat] ?? '🔔';

                    final active = r['is_active'] == true;
                    final doneToday = r['is_done_today'] == true;

                    return Opacity(
                      opacity: active ? 1.0 : 0.55,
                      child: Card(
                        margin: const EdgeInsets.all(8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withOpacity(0.2),
                            child: Text(icon),
                          ),
                          title: Text(
                            (r['title'] ?? 'Untitled').toString(),
                          ),
                          subtitle: Text(
                            '⏰ ${r['remind_time'] ?? "--"} | 🔁 ${r['repeat_interval_mins'] ?? 0} min',
                          ),
                          trailing: PopupMenuButton(
                            onSelected: (value) {
                              final id = (r['id'] ?? 0);

                              if (value == 'done') _markDone(id);
                              if (value == 'snooze') _snooze(id);
                              if (value == 'toggle') _toggle(id, active);
                              if (value == 'delete') _delete(id);
                            },
                            itemBuilder: (context) => [
                              if (!doneToday)
                                const PopupMenuItem(
                                  value: 'done',
                                  child: Text('Mark Done'),
                                ),
                              const PopupMenuItem(
                                value: 'snooze',
                                child: Text('Snooze'),
                              ),
                              PopupMenuItem(
                                value: 'toggle',
                                child: Text(active ? 'Disable' : 'Enable'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}