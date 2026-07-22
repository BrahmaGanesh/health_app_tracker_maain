// lib/screens/appointments_screen.dart — Complete Appointment Module
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});
  @override State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  @override void initState() { super.initState(); _tabs = TabController(length: 5, vsync: this); }
  @override void dispose()   { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Appointments', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        bottom: TabBar(controller: _tabs, isScrollable: true,
          labelColor: AppColors.info, unselectedLabelColor: isDark ? AppColors.textMutedDark : AppColors.textMuted,
          indicatorColor: AppColors.info,
          tabs: const [Tab(text: '📊 Dashboard'), Tab(text: '🟡 Upcoming'), Tab(text: '🔵 Completed'), Tab(text: '🔴 Missed'), Tab(text: '⚪ Cancelled')]),
      ),
      body: TabBarView(controller: _tabs, children: const [
        _DashboardTab(), _ListTab(status: 'upcoming'), _ListTab(status: 'completed'),
        _ListTab(status: 'missed'), _ListTab(status: 'cancelled'),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _AddAppointmentSheet.show(context),
        backgroundColor: AppColors.info, foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Appointment', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// DASHBOARD TAB
// ════════════════════════════════════════════════════════════════
class _DashboardTab extends StatefulWidget {
  const _DashboardTab();
  @override State<_DashboardTab> createState() => _DashboardTabState();
}
class _DashboardTabState extends State<_DashboardTab> {
  final _api = ApiService();
  Map<String,dynamic>? _dash; bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.get('/appointments/dashboard');
    if (r.success) setState(() => _dash = r.data);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp   = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm   = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    if (_loading) return const LoadingView();
    if (_dash == null) return EmptyState(emoji: '📅', title: 'No data', subtitle: '', action: ElevatedButton(onPressed: _load, child: const Text('Retry')));

    final today    = _dash!['today_appointments'] as List? ?? [];
    final nextAppt = _dash!['next_appointment'];
    final plan     = _dash!['plan'] ?? 'free';
    final limit    = _dash!['limit'];
    final canAdd   = _dash!['can_add'] == true;

    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(14), children: [
      // Stats grid
      GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 2.2,
        children: [
          _DashStat('📅', 'Today',     '${_dash!['today_count'] ?? 0}',         AppColors.info,    isDark),
          _DashStat('📆', 'This Week', '${_dash!['upcoming_week_count'] ?? 0}',  AppColors.violet,  isDark),
          _DashStat('🔴', 'Missed',    '${_dash!['missed_count'] ?? 0}',         AppColors.danger,  isDark),
          _DashStat('🔵', 'Completed', '${_dash!['completed_count'] ?? 0}',      AppColors.success, isDark),
        ]),
      const SizedBox(height: 14),

      // Plan limit
      Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12), border: Border.all(color: brd)),
        child: Row(children: [
          Text('${plan.toUpperCase()} plan', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.info)),
          const SizedBox(width: 8),
          Text(limit == null ? 'Unlimited appointments' : '$limit max active', style: TextStyle(fontSize: 12, color: tm)),
          const Spacer(),
          if (!canAdd) GestureDetector(onTap: () => Navigator.pushNamed(context, '/plans'),
            child: const Text('Upgrade →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.violet))),
        ])),
      const SizedBox(height: 14),

      // Next appointment
      if (nextAppt != null) ...[
        Text('🔜 Next Appointment', style: TextStyle(fontFamily: 'Fraunces', fontSize: 15, fontWeight: FontWeight.bold, color: tp)),
        const SizedBox(height: 8),
        _ApptCard(appt: nextAppt, isDark: isDark, card: card, brd: brd, tp: tp, tm: tm, onRefresh: _load, highlight: true),
        const SizedBox(height: 14),
      ],

      // Today's appointments
      if (today.isNotEmpty) ...[
        Text("📅 Today's Appointments", style: TextStyle(fontFamily: 'Fraunces', fontSize: 15, fontWeight: FontWeight.bold, color: tp)),
        const SizedBox(height: 8),
        ...today.map((a) => _ApptCard(appt: a, isDark: isDark, card: card, brd: brd, tp: tp, tm: tm, onRefresh: _load)),
        const SizedBox(height: 14),
      ],

      if (today.isEmpty && nextAppt == null)
        Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
          const Text('📅', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 10),
          Text('No upcoming appointments', style: TextStyle(fontFamily: 'Fraunces', fontSize: 17, fontWeight: FontWeight.bold, color: tp)),
          const SizedBox(height: 6),
          Text('Tap + to schedule a doctor visit, lab test, or vaccination.', style: TextStyle(fontSize: 13, color: tm), textAlign: TextAlign.center),
        ]))),
      const SizedBox(height: 80),
    ]));
  }
}

// ════════════════════════════════════════════════════════════════
// LIST TAB (Upcoming / Completed / Missed / Cancelled)
// ════════════════════════════════════════════════════════════════
class _ListTab extends StatefulWidget {
  final String status;
  const _ListTab({required this.status});
  @override State<_ListTab> createState() => _ListTabState();
}
class _ListTabState extends State<_ListTab> {
  final _api        = ApiService();
  final _searchCtrl = TextEditingController();
  List<dynamic> _appts = []; bool _loading = true;
  String _typeFilter = 'all';

  static const _types = {
    'all':'All','doctor':'👨‍⚕️ Doctor','lab':'🧪 Lab','vaccination':'💉 Vaccine',
    'physiotherapy':'🦴 Physio','dental':'🦷 Dental','eye':'👁️ Eye',
    'health_checkup':'🏥 Checkup','other':'📅 Other',
  };

  @override void initState() { super.initState(); _load(); }
  @override void dispose()   { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final params = <String, dynamic>{'status': widget.status};
    if (_typeFilter != 'all') params['appt_type'] = _typeFilter;
    if (_searchCtrl.text.trim().isNotEmpty) params['search'] = _searchCtrl.text.trim();
    final r = await _api.get('/appointments/', query: params);
    if (r.success) setState(() => _appts = r.data[widget.status] ?? []);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp   = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm   = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Column(children: [
      // Search
      Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: TextField(controller: _searchCtrl, onSubmitted: (_) => _load(),
          onChanged: (_) { if (_searchCtrl.text.isEmpty) _load(); setState(() {}); },
          decoration: InputDecoration(hintText: 'Search appointments...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () { _searchCtrl.clear(); _load(); setState(() {}); }) : null))),

      // Type filter chips
      SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14),
        children: _types.entries.map((e) {
          final sel = e.key == _typeFilter;
          return Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
            onTap: () { setState(() => _typeFilter = e.key); _load(); },
            child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(color: sel ? AppColors.info : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100), borderRadius: BorderRadius.circular(100)),
              child: Text(e.value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sel ? Colors.white : tm)))));
        }).toList())),

      // List
      Expanded(child: _loading ? const LoadingView() : RefreshIndicator(onRefresh: _load,
        child: _appts.isEmpty
            ? EmptyState(
                emoji: {'upcoming':'🟡','completed':'🔵','missed':'🔴','cancelled':'⚪'}[widget.status] ?? '📅',
                title: 'No ${widget.status} appointments',
                subtitle: widget.status == 'upcoming' ? 'Tap + to schedule one' : 'Nothing here yet')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 100),
                itemCount: _appts.length,
                itemBuilder: (_, i) => _ApptCard(appt: _appts[i], isDark: isDark, card: card, brd: brd, tp: tp, tm: tm, onRefresh: _load)))),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════
// APPOINTMENT CARD
// ════════════════════════════════════════════════════════════════
class _ApptCard extends StatelessWidget {
  final dynamic appt; final bool isDark, highlight;
  final Color card, brd, tp, tm; final VoidCallback onRefresh;
  const _ApptCard({required this.appt, required this.isDark, required this.card, required this.brd, required this.tp, required this.tm, required this.onRefresh, this.highlight = false});

  static const _statusColors = {
    'upcoming':  Color(0xFFF59E0B),
    'completed': Color(0xFF3B82F6),
    'missed':    Color(0xFFEF4444),
    'cancelled': Color(0xFF9CA3AF),
  };

  @override
  Widget build(BuildContext context) {
    final api    = ApiService();
    final status = appt['status'] ?? 'upcoming';
    final color  = _statusColors[status] ?? const Color(0xFFF59E0B);
    final isDone = status != 'upcoming';
    final isToday= appt['is_today'] == true;
    final daysUntil = appt['days_until'] as int?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: card, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: (highlight || isToday) ? AppColors.info.withOpacity(0.5) : (isDone ? color.withOpacity(0.2) : brd), width: (highlight || isToday) ? 2 : 1),
        boxShadow: highlight ? [BoxShadow(color: AppColors.info.withOpacity(0.12), blurRadius: 16, offset: const Offset(0,4))] : [],
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Type icon
          Container(width: 46, height: 46, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text(appt['type_icon'] ?? '📅', style: const TextStyle(fontSize: 22)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(appt['title'] ?? '', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: tp, decoration: status == 'cancelled' ? TextDecoration.lineThrough : null))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(100)),
                child: Text('${appt['status_emoji']} ${(appt['status'] ?? '').toString().toUpperCase()}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color))),
            ]),
            const SizedBox(height: 3),
            Text(appt['type_label'] ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.info)),
          ])),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: tm, size: 20),
            color: card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (a) async {
              if (a == 'complete') { await api.markAppointmentDone(appt['id']); onRefresh(); }
              else if (a == 'cancel') { await api.post('/appointments/${appt['id']}/status', data: {'action':'cancel'}); onRefresh(); }
              else if (a == 'missed') { await api.post('/appointments/${appt['id']}/status', data: {'action':'missed'}); onRefresh(); }
              else if (a == 'edit')   { _ApptEditSheet.show(context, appt, onRefresh); }
              else if (a == 'delete') { _confirmDelete(context, appt, api, onRefresh); }
            },
            itemBuilder: (_) => [
              if (status == 'upcoming') ...[
                PopupMenuItem(value: 'complete', child: Text('✅  Mark Completed', style: TextStyle(color: tp))),
                PopupMenuItem(value: 'cancel',   child: Text('⚪  Cancel',          style: TextStyle(color: tp))),
                PopupMenuItem(value: 'missed',   child: Text('🔴  Mark Missed',     style: TextStyle(color: tp))),
                const PopupMenuDivider(),
              ],
              PopupMenuItem(value: 'edit',   child: Text('✏️  Edit',   style: TextStyle(color: tp))),
              PopupMenuItem(value: 'delete', child: const Text('🗑️  Delete', style: TextStyle(color: AppColors.danger))),
            ],
          ),
        ]),
        const SizedBox(height: 10),

        // Date / time / location row
        Wrap(spacing: 10, runSpacing: 6, children: [
          _InfoChip(Icons.calendar_today_rounded, appt['appointment_date'] ?? '', AppColors.info, isDark),
          if (appt['appointment_time'] != null) _InfoChip(Icons.access_time_rounded, appt['appointment_time'], AppColors.info, isDark),
          if (appt['hospital_name'] != null) _InfoChip(Icons.local_hospital_rounded, appt['hospital_name'], AppColors.violet, isDark),
          if (appt['location'] != null) _InfoChip(Icons.location_on_rounded, appt['location'], AppColors.textMuted, isDark),
        ]),

        // Days badge
        if (status == 'upcoming' && daysUntil != null) ...[
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: (isToday ? AppColors.danger : daysUntil <= 3 ? AppColors.warning : AppColors.info).withOpacity(0.1), borderRadius: BorderRadius.circular(100)),
            child: Text(isToday ? '🔴 TODAY' : daysUntil == 1 ? '⏰ Tomorrow' : daysUntil < 0 ? '🔴 Overdue' : '📅 In $daysUntil days',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isToday ? AppColors.danger : daysUntil <= 3 ? AppColors.warning : AppColors.info))),
        ],

        // Quick mark done button for upcoming
        if (status == 'upcoming') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: ElevatedButton(
              onPressed: () async { await api.markAppointmentDone(appt['id']); onRefresh(); },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
              child: const Text('✅ Mark Completed', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(
              onPressed: () async { await api.post('/appointments/${appt['id']}/status', data: {'action':'cancel'}); onRefresh(); },
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), side: BorderSide(color: Colors.grey.withOpacity(0.3))),
              child: const Text('⚪ Cancel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted)))),
          ]),
        ],
      ])),
    );
  }

  void _confirmDelete(BuildContext context, dynamic appt, ApiService api, VoidCallback onRefresh) async {
    final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(children: [Text('📅 ', style: TextStyle(fontSize: 22)), Text('Delete Appointment?')]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Are you sure you want to permanently delete "${appt['title']}"?', style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 10),
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
          child: const Text('This action cannot be undone.', style: TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w600))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white), child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
    ));
    if (ok == true) {
      await api.deleteAppointment(appt['id']); onRefresh();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🗑️ ${appt['title']} deleted'), backgroundColor: AppColors.success));
    }
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon; final String label; final Color color; final bool isDark;
  const _InfoChip(this.icon, this.label, this.color, this.isDark);
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(isDark ? 0.15 : 0.08), borderRadius: BorderRadius.circular(100)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color), const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis),
    ]));
}

// ════════════════════════════════════════════════════════════════
// ADD APPOINTMENT SHEET
// ════════════════════════════════════════════════════════════════
class _AddAppointmentSheet {
  static void show(BuildContext context, {VoidCallback? onDone}) {
    final api       = ApiService();
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final titleCtrl = TextEditingController();
    final docCtrl   = TextEditingController();
    final hospCtrl  = TextEditingController();
    final locCtrl   = TextEditingController();
    final notesCtrl = TextEditingController();
    String apptType = 'doctor';
    DateTime date   = DateTime.now().add(const Duration(days: 1));
    TimeOfDay time  = const TimeOfDay(hour: 10, minute: 0);
    bool rem1d = true, rem1h = true, remAt = true, remEmail = false;
    int? customMins;

    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (_, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          const Text('📅 Add Appointment', style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),

          TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Appointment Title *', hintText: 'e.g. Dr. Sharma Annual Checkup')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: apptType, decoration: const InputDecoration(labelText: 'Type'),
            items: {'doctor':'👨‍⚕️ Doctor Visit','lab':'🧪 Lab Test','vaccination':'💉 Vaccination','physiotherapy':'🦴 Physiotherapy','dental':'🦷 Dental','eye':'👁️ Eye Checkup','health_checkup':'🏥 Health Checkup','other':'📅 Other'}
              .entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setSt(() => apptType = v ?? 'doctor')),
          const SizedBox(height: 10),
          TextField(controller: docCtrl, decoration: const InputDecoration(labelText: 'Doctor / Lab Name', hintText: 'Dr. Sharma')),
          const SizedBox(height: 10),
          TextField(controller: hospCtrl, decoration: const InputDecoration(labelText: 'Hospital / Clinic', hintText: 'Apollo Hospital')),
          const SizedBox(height: 10),

          // Date + Time
          Row(children: [
            Expanded(child: GestureDetector(onTap: () async {
              final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime.now(), lastDate: DateTime(2030));
              if (d != null) setSt(() => date = d);
            }, child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Date', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                Text('${date.day}/${date.month}/${date.year}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))])))),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(onTap: () async {
              final t = await showTimePicker(context: ctx, initialTime: time);
              if (t != null) setSt(() => time = t);
            }, child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Time', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                Text(time.format(ctx), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))])))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'Location (optional)', hintText: 'Building, Floor, Room')),
          const SizedBox(height: 10),
          TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)'), maxLines: 2),
          const SizedBox(height: 14),

          // Reminders
          const Text('🔔 Reminders', style: TextStyle(fontFamily: 'Fraunces', fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.info.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.info.withOpacity(0.2))),
            child: Column(children: [
              _ReminderToggle('1 day before', rem1d, (v) => setSt(() => rem1d = v)),
              _ReminderToggle('1 hour before', rem1h, (v) => setSt(() => rem1h = v)),
              _ReminderToggle('At appointment time', remAt, (v) => setSt(() => remAt = v)),
              _ReminderToggle('📧 Email reminder', remEmail, (v) => setSt(() => remEmail = v)),
              const SizedBox(height: 6),
              DropdownButtonFormField<int?>(value: customMins, decoration: const InputDecoration(labelText: 'Custom reminder (optional)', isDense: true),
                items: const [DropdownMenuItem(value:null,child:Text('No custom')),DropdownMenuItem(value:15,child:Text('15 min before')),DropdownMenuItem(value:30,child:Text('30 min before')),DropdownMenuItem(value:60,child:Text('60 min before')),DropdownMenuItem(value:120,child:Text('2 hours before'))],
                onChanged: (v) => setSt(() => customMins = v)),
            ])),
          const SizedBox(height: 16),

          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty) return;
              final resp = await api.post('/appointments/', data: {
                'title': titleCtrl.text.trim(), 'appointment_type': apptType,
                'doctor_name': docCtrl.text.trim(), 'hospital_name': hospCtrl.text.trim(),
                'appointment_date': date.toIso8601String().substring(0,10),
                'appointment_time': '${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}',
                'location': locCtrl.text.trim(), 'notes': notesCtrl.text.trim(),
                'reminder_1day': rem1d, 'reminder_1hour': rem1h, 'reminder_at_time': remAt,
                'reminder_email': remEmail, if (customMins != null) 'reminder_custom_mins': customMins,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              if (resp.success) {
                onDone?.call();
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success));
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ ${resp.message}'), backgroundColor: AppColors.danger));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.info, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('📅 Add Appointment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          )),
        ])),
      )));
  }
}

// ════════════════════════════════════════════════════════════════
// EDIT SHEET
// ════════════════════════════════════════════════════════════════
class _ApptEditSheet {
  static void show(BuildContext context, dynamic appt, VoidCallback onRefresh) {
    final api       = ApiService();
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final titleCtrl = TextEditingController(text: appt['title'] ?? '');
    final docCtrl   = TextEditingController(text: appt['doctor_name'] ?? '');
    final hospCtrl  = TextEditingController(text: appt['hospital_name'] ?? '');
    final locCtrl   = TextEditingController(text: appt['location'] ?? '');
    final notesCtrl = TextEditingController(text: appt['notes'] ?? '');
    String apptType = appt['appointment_type'] ?? 'doctor';
    DateTime date   = DateTime.tryParse(appt['appointment_date'] ?? '') ?? DateTime.now();
    TimeOfDay time  = appt['appointment_time'] != null
        ? TimeOfDay(hour: int.parse(appt['appointment_time'].split(':')[0]), minute: int.parse(appt['appointment_time'].split(':')[1]))
        : const TimeOfDay(hour: 10, minute: 0);

    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (_, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('✏️ Edit Appointment', style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title *')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: apptType, decoration: const InputDecoration(labelText: 'Type'),
            items: {'doctor':'👨‍⚕️ Doctor','lab':'🧪 Lab','vaccination':'💉 Vaccination','physiotherapy':'🦴 Physio','dental':'🦷 Dental','eye':'👁️ Eye','health_checkup':'🏥 Checkup','other':'📅 Other'}
              .entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setSt(() => apptType = v ?? 'doctor')),
          const SizedBox(height: 10),
          TextField(controller: docCtrl, decoration: const InputDecoration(labelText: 'Doctor / Lab')),
          const SizedBox(height: 10),
          TextField(controller: hospCtrl, decoration: const InputDecoration(labelText: 'Hospital')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: GestureDetector(onTap: () async { final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2030)); if (d != null) setSt(() => date = d); },
              child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Date', style: TextStyle(fontSize: 11, color: AppColors.textMuted)), Text('${date.day}/${date.month}/${date.year}', style: const TextStyle(fontWeight: FontWeight.w700))])))),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(onTap: () async { final t = await showTimePicker(context: ctx, initialTime: time); if (t != null) setSt(() => time = t); },
              child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Time', style: TextStyle(fontSize: 11, color: AppColors.textMuted)), Text(time.format(ctx), style: const TextStyle(fontWeight: FontWeight.w700))])))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'Location')),
          const SizedBox(height: 10),
          TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final resp = await api.updateAppointment(appt['id'], {
                'title': titleCtrl.text.trim(), 'appointment_type': apptType,
                'doctor_name': docCtrl.text.trim(), 'hospital_name': hospCtrl.text.trim(),
                'appointment_date': date.toIso8601String().substring(0,10),
                'appointment_time': '${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}',
                'location': locCtrl.text.trim(), 'notes': notesCtrl.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
              onRefresh();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.info, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('✅ Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
          )),
        ])),
      )));
  }
}

// ── Helper widgets ─────────────────────────────────────────────────
class _DashStat extends StatelessWidget {
  final String emoji, label, value; final Color color; final bool isDark;
  const _DashStat(this.emoji, this.label, this.value, this.color, this.isDark);
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(isDark ? 0.15 : 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.2))),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 20)), const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.8), fontWeight: FontWeight.w700)),
      ]),
    ]));
}

Widget _ReminderToggle(String label, bool value, ValueChanged<bool> onChanged) =>
  Row(children: [
    Text(label, style: const TextStyle(fontSize: 13)),
    const Spacer(),
    Switch.adaptive(value: value, onChanged: onChanged, activeColor: AppColors.info,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
  ]);