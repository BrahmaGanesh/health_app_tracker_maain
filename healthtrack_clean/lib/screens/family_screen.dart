// lib/screens/family_screen.dart — Family Health Manager + Dark Mode
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart' hide AppBottomNav;
import 'bp_tracker_screen.dart' show _CardBox, _SyncBadge;

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});
  @override State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final _api  = ApiService();
  final _sync = SyncService();
  List<dynamic> _members = [];
  bool _loading = true;

  static const _avatarGradients = [
    [Color(0xFF142D4C), Color(0xFF1E3F6E)],
    [Color(0xFF4F3B78), Color(0xFF6D28D9)],
    [Color(0xFF065F46), Color(0xFF047857)],
    [Color(0xFF7C2D12), Color(0xFFB45309)],
    [Color(0xFF1E3A5F), Color(0xFF0EA5E9)],
  ];

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getFamilyMembers();
    if (resp.success) setState(() => _members = resp.data['members'] ?? []);
    setState(() => _loading = false);
  }

  Future<void> _showAddSheet(bool isDark, Color card, Color brd, Color tp) async {
    final nameCtrl = TextEditingController();
    String relation = 'spouse';
    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: brd, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('👨‍👩‍👧 Add Family Member', style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900, color: tp)),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name', hintText: 'e.g. Priya Sharma')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: relation,
              decoration: const InputDecoration(labelText: 'Relation'),
              items: ['spouse','parent','child','sibling','grandparent','other']
                  .map((r) => DropdownMenuItem(value: r, child: Text(r[0].toUpperCase() + r.substring(1)))).toList(),
              onChanged: (v) => setSt(() => relation = v ?? 'spouse'),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final resp = await _api.addFamilyMember({'name': nameCtrl.text.trim(), 'relation': relation});
                if (ctx.mounted) Navigator.pop(ctx);
                if (resp.success) { _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success)); }
              },
              child: const Text('➕ Add Member', style: TextStyle(fontWeight: FontWeight.bold)),
            )),
          ]),
        ),
      ),
    );
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
        title: const Text('Family Health', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [
          _SyncBadge(_sync.isOnline),
          IconButton(icon: const Icon(Icons.person_add_rounded), onPressed: () => _showAddSheet(isDark, card, brd, tp)),
        ],
      ),
      body: _loading ? const LoadingView() : RefreshIndicator(
        onRefresh: _load,
        child: _members.isEmpty
            ? EmptyState(
                emoji: '👨‍👩‍👧', title: 'No family members yet',
                subtitle: 'Add family members to track their health alongside yours.',
                action: ElevatedButton(
                  onPressed: () => _showAddSheet(isDark, card, brd, tp),
                  child: const Text('+ Add Member'),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _members.length + 1,
                itemBuilder: (_, i) {
                  if (i == _members.length) {
                    return Padding(padding: const EdgeInsets.only(top: 4, bottom: 80), child: OutlinedButton.icon(
                      onPressed: () => _showAddSheet(isDark, card, brd, tp),
                      icon: const Icon(Icons.person_add_rounded, size: 18),
                      label: const Text('Add Another Member'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: BorderSide(color: brd)),
                    ));
                  }

                  final m       = _members[i];
                  final bp      = m['latest_bp'];
                  final bpStr   = bp != null ? '${bp['value_1']?.toInt()}/${bp['value_2']?.toInt()} mmHg' : 'No BP';
                  final gradient= _avatarGradients[i % _avatarGradients.length];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20), border: Border.all(color: brd),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))]),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                          FamilyMemberDetailScreen(memberId: m['id'] as int, memberName: m['name'] ?? '', isDark: isDark))).then((_) => _load()),
                      child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                        // Avatar
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(gradient: LinearGradient(colors: gradient), borderRadius: BorderRadius.circular(18)),
                          child: Center(child: Text((m['name'] as String? ?? 'U').substring(0, 1).toUpperCase(),
                              style: const TextStyle(fontSize: 24, fontFamily: 'Fraunces', fontWeight: FontWeight.bold, color: Colors.white))),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text(m['name'] ?? '', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
                            const SizedBox(width: 6),
                            if (m['relation'] != null)
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.violet.withOpacity(0.1), borderRadius: BorderRadius.circular(100)),
                                child: Text(m['relation'][0].toUpperCase() + m['relation'].substring(1),
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.violet))),
                          ]),
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.favorite_rounded, size: 13, color: AppColors.danger),
                            const SizedBox(width: 4),
                            Text(bpStr, style: TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600, color: tp)),
                          ]),
                          if (m['age'] != null) ...[
                            const SizedBox(height: 2),
                            Text('${m['age']} years · ${m['gender'] ?? ''}', style: TextStyle(fontSize: 11, color: tm)),
                          ],
                        ])),
                        Icon(Icons.chevron_right_rounded, color: tm),
                      ])),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(isDark, card, brd, tp),
        backgroundColor: AppColors.sage,
        foregroundColor: AppColors.navy,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Member', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// FAMILY MEMBER DETAIL SCREEN
// ════════════════════════════════════════════════════════════════
class FamilyMemberDetailScreen extends StatefulWidget {
  final int memberId;
  final String memberName;
  final bool isDark;
  const FamilyMemberDetailScreen({super.key, required this.memberId, required this.memberName, required this.isDark});
  @override State<FamilyMemberDetailScreen> createState() => _FamilyMemberDetailState();
}

class _FamilyMemberDetailState extends State<FamilyMemberDetailScreen> {
  final _api = ApiService();
  Map<String,dynamic>? _member;
  bool _loading = true, _saving = false;

  final _v1Ctrl = TextEditingController();
  final _v2Ctrl = TextEditingController();
  String _metricType = 'bp';

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _v1Ctrl.dispose(); _v2Ctrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getFamilyMember(widget.memberId);
    if (resp.success) setState(() => _member = resp.data);
    setState(() => _loading = false);
  }

  Future<void> _logMetric() async {
    final v1 = double.tryParse(_v1Ctrl.text);
    if (v1 == null) return;
    setState(() => _saving = true);
    final data = {'metric_type': _metricType, 'value_1': v1};
    final v2 = double.tryParse(_v2Ctrl.text);
    if (v2 != null) data['value_2'] = v2;
    final resp = await _api.logFamilyMetric(widget.memberId, data);
    setState(() => _saving = false);
    if (resp.success) { _v1Ctrl.clear(); _v2Ctrl.clear(); _load(); }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final card   = isDark ? AppColors.cardDark : Colors.white;
    final brd    = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp     = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm     = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(widget.memberName, style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold))),
      body: _loading ? const LoadingView() : RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Stats
            if (_member != null)
              Row(children: [
                _MCard('⚖️', 'BMI', '${_member!['bmi'] ?? '—'}', AppColors.violet, isDark, card, brd, tp),
                const SizedBox(width: 12),
                _MCard('👤', 'Age', '${_member!['age'] ?? '—'}', AppColors.sage, isDark, card, brd, tp),
                const SizedBox(width: 12),
                _MCard('⚧', 'Gender', '${_member!['gender'] ?? '—'}', AppColors.info, isDark, card, brd, tp),
              ]),
            const SizedBox(height: 16),

            // Log reading
            _CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('➕ Log Reading', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _metricType,
                decoration: const InputDecoration(labelText: 'Metric Type'),
                items: const [
                  DropdownMenuItem(value: 'bp',     child: Text('❤️ Blood Pressure')),
                  DropdownMenuItem(value: 'weight', child: Text('⚖️ Weight')),
                  DropdownMenuItem(value: 'sugar',  child: Text('🩺 Blood Sugar')),
                ],
                onChanged: (v) => setState(() => _metricType = v ?? 'bp'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: _v1Ctrl, keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: _metricType == 'bp' ? 'Systolic' : 'Value', hintText: _metricType == 'bp' ? '120' : '70'))),
                if (_metricType == 'bp') ...[
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _v2Ctrl, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Diastolic', hintText: '80'))),
                ],
              ]),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: _saving ? null : _logMetric,
                child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save Reading', style: TextStyle(fontWeight: FontWeight.bold)),
              )),
            ])),
            const SizedBox(height: 16),

            // Recent readings
            if (_member?['recent_metrics'] != null && (_member!['recent_metrics'] as List).isNotEmpty)
              _CardBox(isDark: isDark, cardBg: card, border: brd, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('📋 Recent Readings', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: tp)),
                const SizedBox(height: 10),
                ...(_member!['recent_metrics'] as List).take(10).map((m) {
                  final type = m['metric_type']?.toString().toUpperCase() ?? '';
                  final icon = {'BP':'❤️','WEIGHT':'⚖️','SUGAR':'🩺'}[type] ?? '📊';
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: brd, width: 0.5))),
                    child: Row(children: [
                      Text(icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(type, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: tm, letterSpacing: 0.5)),
                        Text('${m['value_1'] ?? '—'}${m['value_2'] != null ? '/${m['value_2']}' : ''}',
                            style: TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w600, color: tp)),
                      ])),
                      Text(m['recorded_time'] ?? '', style: TextStyle(fontSize: 11, color: tm)),
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
}

class _CardBox extends StatelessWidget {
  final bool isDark; final Color cardBg, border; final Widget child;
  const _CardBox({required this.isDark, required this.cardBg, required this.border, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))]),
    child: child,
  );
}

class _MCard extends StatelessWidget {
  final String emoji, label, value; final Color color, cardBg, border, tp; final bool isDark;
  const _MCard(this.emoji, this.label, this.value, this.color, this.isDark, this.cardBg, this.border, this.tp);
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
    child: Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w700, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
      Text(label, style: TextStyle(fontSize: 10, color: tp, fontWeight: FontWeight.w600)),
    ]),
  ));
}