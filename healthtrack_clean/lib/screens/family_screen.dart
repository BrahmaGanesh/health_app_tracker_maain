// ============================================================
// lib/screens/family_screen.dart — Family Health Manager
// ============================================================

import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final _api = ApiService();
  List<dynamic> _members = [];
  bool _loading = true;
  final List<Color> _avatarColors = [const Color(0xFF142D4C), const Color(0xFF4F3B78), const Color(0xFF065F46), const Color(0xFF7C2D12)];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getFamilyMembers();
    if (resp.success) setState(() => _members = resp.data['members'] ?? []);
    setState(() => _loading = false);
  }

  Future<void> _showAddSheet() async {
    final nameCtrl = TextEditingController();
    String relation = 'spouse';
    await showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('👨‍👩‍👧 Add Family Member', style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.navy)),
              const SizedBox(height: 16),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name', hintText: 'e.g. Priya Sharma')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: relation, decoration: const InputDecoration(labelText: 'Relation'),
                items: ['spouse', 'parent', 'child', 'sibling', 'grandparent', 'other']
                    .map((r) => DropdownMenuItem(value: r, child: Text(r[0].toUpperCase() + r.substring(1)))).toList(),
                onChanged: (v) => setSt(() => relation = v ?? 'spouse'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    final resp = await _api.addFamilyMember({'name': nameCtrl.text.trim(), 'relation': relation});
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (resp.success) { _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success)); }
                  },
                  child: const Text('➕ Add Member'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Family Health', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showAddSheet)],
      ),
      body: _loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              child: _members.isEmpty
                  ? EmptyState(
                      emoji: '👨‍👩‍👧', title: 'No family members yet',
                      subtitle: 'Add family members to track their health alongside yours.',
                      action: ElevatedButton(onPressed: _showAddSheet, child: const Text('+ Add Member')),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _members.length,
                      itemBuilder: (context, i) {
                        final m = _members[i];
                        final bp = m['latest_bp'];
                        final bpStr = bp != null ? '${bp['value_1']?.toInt()}/${bp['value_2']?.toInt()} mmHg' : 'No BP reading';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FamilyMemberDetailScreen(memberId: m['id'], memberName: m['name']))).then((_) => _load()),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: _avatarColors[i % _avatarColors.length],
                                    radius: 28,
                                    child: Text(m['name'][0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 22, fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(m['name'], style: const TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navy)),
                                        Row(children: [
                                          if (m['relation'] != null) Text('${m['relation'][0].toUpperCase()}${m['relation'].substring(1)}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                          if (m['age'] != null) Text(' · ${m['age']} yrs', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                        ]),
                                        const SizedBox(height: 6),
                                        Row(children: [
                                          const Icon(Icons.favorite, size: 13, color: AppColors.danger),
                                          const SizedBox(width: 4),
                                          Text(bpStr, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                                        ]),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(onPressed: _showAddSheet, backgroundColor: AppColors.sage, child: const Icon(Icons.add, color: AppColors.navy)),
    );
  }
}

// ════════════════════════════════════════════════════════════
// FAMILY MEMBER DETAIL SCREEN
// ════════════════════════════════════════════════════════════
class FamilyMemberDetailScreen extends StatefulWidget {
  final int memberId;
  final String memberName;
  const FamilyMemberDetailScreen({super.key, required this.memberId, required this.memberName});

  @override
  State<FamilyMemberDetailScreen> createState() => _FamilyMemberDetailScreenState();
}

class _FamilyMemberDetailScreenState extends State<FamilyMemberDetailScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _member;
  bool _loading = true;
  final _v1Ctrl = TextEditingController(), _v2Ctrl = TextEditingController();
  String _metricType = 'bp';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getFamilyMember(widget.memberId);
    if (resp.success) setState(() => _member = resp.data);
    setState(() => _loading = false);
  }

  Future<void> _logMetric() async {
    final v1 = double.tryParse(_v1Ctrl.text);
    if (v1 == null) return;
    final data = {'metric_type': _metricType, 'value_1': v1};
    final v2 = double.tryParse(_v2Ctrl.text);
    if (v2 != null) data['value_2'] = v2;
    final resp = await _api.logFamilyMetric(widget.memberId, data);
    if (resp.success) { _v1Ctrl.clear(); _v2Ctrl.clear(); _load(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: Text(widget.memberName, style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold))),
      body: _loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_member != null) ...[
                      Row(children: [
                        Expanded(child: StatCard(label: 'Age', value: '${_member!['age'] ?? '—'}', emoji: '👤', color: AppColors.navy, sublabel: _member!['gender'] ?? '')),
                        const SizedBox(width: 12),
                        Expanded(child: StatCard(label: 'BMI', value: '${_member!['bmi'] ?? '—'}', emoji: '⚖️', color: AppColors.violet, sublabel: '')),
                      ]),
                      const SizedBox(height: 16),
                    ],
                    SectionCard(
                      title: '➕ Log Reading',
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            value: _metricType, decoration: const InputDecoration(labelText: 'Metric'),
                            items: const [
                              DropdownMenuItem(value: 'bp', child: Text('❤️ Blood Pressure')),
                              DropdownMenuItem(value: 'weight', child: Text('⚖️ Weight')),
                              DropdownMenuItem(value: 'sugar', child: Text('🩺 Blood Sugar')),
                            ],
                            onChanged: (v) => setState(() => _metricType = v ?? 'bp'),
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: TextField(controller: _v1Ctrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _metricType == 'bp' ? 'Systolic' : 'Value', hintText: _metricType == 'bp' ? '120' : '70'))),
                            if (_metricType == 'bp') ...[
                              const SizedBox(width: 10),
                              Expanded(child: TextField(controller: _v2Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Diastolic', hintText: '80'))),
                            ],
                          ]),
                          const SizedBox(height: 12),
                          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _logMetric, child: const Text('Save Reading'))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_member?['recent_metrics'] != null && (_member!['recent_metrics'] as List).isNotEmpty)
                      SectionCard(
                        title: '📋 Recent Readings', padding: EdgeInsets.zero,
                        child: Column(
                          children: (_member!['recent_metrics'] as List).take(10).map<Widget>((m) => ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            title: Text(m['metric_type'].toString().toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: AppColors.textMuted)),
                            subtitle: Text('${m['value_1'] ?? '—'}${m['value_2'] != null ? '/${m['value_2']}' : ''}', style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy)),
                            trailing: Text(m['recorded_time'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          )).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}