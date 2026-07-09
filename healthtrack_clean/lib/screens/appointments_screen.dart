// lib/screens/appointments_screen.dart — Module 10: Appointment Manager
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/local_db_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});
  @override State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  final _api = ApiService();
  final _db  = LocalDb();
  List<dynamic> _appointments = [];
  bool _loading = true;

  static const _typeIcons = {'doctor':'👨‍⚕️','lab':'🧪','vaccination':'💉','other':'📅'};

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (SyncService().isOnline) {
      final resp = await _api.getAppointments();
      if (resp.success) { setState(() { _appointments = resp.data['appointments'] ?? []; _loading = false; }); return; }
    }
    final local = await _db.getAllAppointments();
    setState(() { _appointments = local; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp   = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm   = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    final today = DateTime.now();
    final upcoming = _appointments.where((a) {
      final d = DateTime.tryParse(a['appointment_date'] ?? '');
      return d != null && !d.isBefore(DateTime(today.year, today.month, today.day)) && a['completed'] != true;
    }).toList();
    final past = _appointments.where((a) => !upcoming.contains(a)).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Appointments', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => _showAddSheet(isDark))],
      ),
      body: _loading ? const LoadingView() : RefreshIndicator(onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (upcoming.isNotEmpty) ...[
            Text('📅 Upcoming', style: TextStyle(fontFamily: 'Fraunces', fontSize: 17, fontWeight: FontWeight.bold, color: tp)),
            const SizedBox(height: 10),
            ...upcoming.map((a) => _AppointmentCard(appt: a, isDark: isDark, card: card, brd: brd, tp: tp, tm: tm,
                icon: _typeIcons[a['appointment_type']] ?? '📅',
                onComplete: () async { await _db.markAppointmentComplete(a['id']); if (SyncService().isOnline) await _api.markAppointmentDone(a['id']); _load(); },
                onDelete: () async { final ok = await showConfirmDialog(context, 'Delete', 'Remove this appointment?'); if (ok) { await _api.deleteAppointment(a['id']); _load(); } })),
            const SizedBox(height: 20),
          ],
          if (past.isNotEmpty) ...[
            Text('✅ Past', style: TextStyle(fontFamily: 'Fraunces', fontSize: 17, fontWeight: FontWeight.bold, color: tp)),
            const SizedBox(height: 10),
            ...past.take(10).map((a) => _AppointmentCard(appt: a, isDark: isDark, card: card, brd: brd, tp: tp, tm: tm, icon: _typeIcons[a['appointment_type']] ?? '📅', completed: true)),
          ],
          if (_appointments.isEmpty)
            const EmptyState(emoji: '📅', title: 'No appointments', subtitle: 'Tap + to add a doctor visit, lab test, or vaccination'),
          const SizedBox(height: 80),
        ]),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }

  void _showAddSheet(bool isDark) {
    final titleCtrl = TextEditingController(), locationCtrl = TextEditingController(), notesCtrl = TextEditingController();
    String type = 'doctor';
    DateTime apptDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay apptTime = const TimeOfDay(hour: 10, minute: 0);

    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (_, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('📅 New Appointment', style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Dr. Sharma Checkup')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: type, decoration: const InputDecoration(labelText: 'Type'),
            items: const [DropdownMenuItem(value: 'doctor', child: Text('👨‍⚕️ Doctor Visit')), DropdownMenuItem(value: 'lab', child: Text('🧪 Lab Test')), DropdownMenuItem(value: 'vaccination', child: Text('💉 Vaccination')), DropdownMenuItem(value: 'other', child: Text('📅 Other'))],
            onChanged: (v) => setSt(() => type = v ?? 'doctor')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: ListTile(contentPadding: EdgeInsets.zero, title: const Text('Date', style: TextStyle(fontSize: 12)),
              subtitle: Text('${apptDate.day}/${apptDate.month}/${apptDate.year}'),
              onTap: () async { final d = await showDatePicker(context: context, initialDate: apptDate, firstDate: DateTime.now(), lastDate: DateTime(2030)); if (d != null) setSt(() => apptDate = d); })),
            Expanded(child: ListTile(contentPadding: EdgeInsets.zero, title: const Text('Time', style: TextStyle(fontSize: 12)),
              subtitle: Text(apptTime.format(context)),
              onTap: () async { final t = await showTimePicker(context: context, initialTime: apptTime); if (t != null) setSt(() => apptTime = t); })),
          ]),
          TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Location (optional)', hintText: 'Hospital / Clinic name')),
          const SizedBox(height: 10),
          TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)'), maxLines: 2),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
            if (titleCtrl.text.trim().isEmpty) return;
            final resp = await _api.addAppointment({
              'title': titleCtrl.text.trim(), 'appointment_type': type,
              'appointment_date': apptDate.toIso8601String().substring(0, 10),
              'appointment_time': '${apptTime.hour.toString().padLeft(2,'0')}:${apptTime.minute.toString().padLeft(2,'0')}',
              'location': locationCtrl.text.trim(), 'notes': notesCtrl.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            if (resp.success) { _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success)); }
          }, child: const Text('📅 Add Appointment', style: TextStyle(fontWeight: FontWeight.bold)))),
        ])),
      )),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final dynamic appt;
  final bool isDark, completed;
  final Color card, brd, tp, tm;
  final String icon;
  final VoidCallback? onComplete, onDelete;
  const _AppointmentCard({required this.appt, required this.isDark, required this.card, required this.brd,
      required this.tp, required this.tm, required this.icon, this.completed = false, this.onComplete, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16), border: Border.all(color: brd)),
      child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.info.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 20)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(appt['title'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tp, decoration: completed ? TextDecoration.lineThrough : null)),
          const SizedBox(height: 2),
          Text('${appt['appointment_date'] ?? ''} · ${appt['appointment_time'] ?? ''}', style: TextStyle(fontSize: 12, color: tm)),
          if (appt['location'] != null && appt['location'].toString().isNotEmpty) Text(appt['location'], style: TextStyle(fontSize: 11, color: tm)),
        ])),
        if (!completed) Row(children: [
          if (onComplete != null) IconButton(icon: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success), onPressed: onComplete),
          if (onDelete != null) IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger), onPressed: onDelete),
        ]) else const Text('✅', style: TextStyle(fontSize: 18)),
      ])),
    );
  }
}