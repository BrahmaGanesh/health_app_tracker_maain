// lib/screens/family_screen.dart — Complete Family Health Management
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});
  @override State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final _api = ApiService();
  List<dynamic> _members = [];
  Map<String, dynamic>? _meta;
  bool _loading = true;

  static const _gradients = [
    [Color(0xFF142D4C), Color(0xFF1E3F6E)],
    [Color(0xFF4F3B78), Color(0xFF6D28D9)],
    [Color(0xFF065F46), Color(0xFF047857)],
    [Color(0xFF7C2D12), Color(0xFFB45309)],
  ];

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getFamilyMembers();
    if (resp.success) {
      setState(() {
        _members = resp.data['members'] ?? [];
        _meta    = resp.data;
      });
    }
    setState(() => _loading = false);
  }

  // ── Plan restriction banner ──────────────────────────────────────
  Widget _planBanner(bool isDark) {
    final plan  = _meta?['plan'] ?? 'free';
    final limit = _meta?['limit'] ?? 0;
    Color c; String msg; String icon;
    if (plan == 'free') {
      c = AppColors.danger; icon = '🔒';
      msg = 'Upgrade to add family members';
    } else if (plan == 'normal') {
      c = AppColors.warning; icon = '👥';
      msg = 'Normal plan: 1 family member. Upgrade for 2.';
    } else {
      c = AppColors.success; icon = '✅';
      msg = 'Premium: up to $limit family members';
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withOpacity(0.3))),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c))),
        if (plan == 'free' || plan == 'normal')
          GestureDetector(onTap: () => Navigator.pushNamed(context, '/plans'),
            child: Text('Upgrade →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final plan   = _meta?['plan'] ?? 'free';
    final canAdd = _meta?['can_add_more'] == true;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Family Health', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [
          if (canAdd)
            IconButton(icon: const Icon(Icons.person_add_rounded), onPressed: () => _showAddSheet(isDark)),
        ],
      ),
      body: Column(children: [
        _planBanner(isDark),
        const SizedBox(height: 8),
        Expanded(child: _loading ? const LoadingView() : RefreshIndicator(
          onRefresh: _load,
          child: _members.isEmpty
              ? EmptyState(
                  emoji: plan == 'free' ? '🔒' : '👨‍👩‍👧',
                  title: plan == 'free' ? 'Family tracking locked' : 'No family members yet',
                  subtitle: plan == 'free' ? 'Subscribe to track family health' : 'Tap + to add a family member',
                  action: plan == 'free'
                      ? ElevatedButton(onPressed: () => Navigator.pushNamed(context, '/plans'), child: const Text('View Plans'))
                      : ElevatedButton(onPressed: () => _showAddSheet(isDark), child: const Text('+ Add Member')),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: _members.length,
                  itemBuilder: (_, i) => _MemberCard(
                    member: _members[i], gradient: _gradients[i % _gradients.length],
                    isDark: isDark,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => FamilyMemberDetailScreen(member: _members[i]))).then((_) => _load()),
                    onDelete: () => _confirmDelete(_members[i]),
                  ),
                ),
        )),
      ]),
      floatingActionButton: canAdd ? FloatingActionButton.extended(
        onPressed: () => _showAddSheet(isDark),
        backgroundColor: AppColors.sage, foregroundColor: AppColors.navy,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Member', style: TextStyle(fontWeight: FontWeight.bold)),
      ) : null,
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }

  Future<void> _confirmDelete(dynamic member) async {
    final ok = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(children: [Text('⚠️ ', style: TextStyle(fontSize: 22)), Text('Delete Member')]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Are you sure you want to delete ${member['name']}?', style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 10),
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.danger.withOpacity(0.2))),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('This will permanently delete:', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger, fontSize: 13)),
              SizedBox(height: 6),
              Text('• All health readings (BP, Sugar, Weight)', style: TextStyle(fontSize: 12, color: AppColors.danger)),
              Text('• All medicines', style: TextStyle(fontSize: 12, color: AppColors.danger)),
              Text('• All uploaded documents', style: TextStyle(fontSize: 12, color: AppColors.danger)),
              Text('• All appointments & reminders', style: TextStyle(fontSize: 12, color: AppColors.danger)),
              SizedBox(height: 4),
              Text('This action cannot be undone.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.danger)),
            ])),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(_, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            child: const Text('Delete Everything', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true) {
      final resp = await _api.deleteFamilyMember(member['id']);
      if (resp.success) {
        _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('🗑️ ${member['name']} and all data deleted'), backgroundColor: AppColors.success));
      }
    }
  }

  void _showAddSheet(bool isDark) {
    final nameCtrl = TextEditingController();
    final dobCtrl  = TextEditingController();
    String relation = 'parent', gender = 'female';
    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (_, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('👨‍👩‍👧 Add Family Member', style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name *', hintText: 'e.g. Priya Sharma'), textCapitalization: TextCapitalization.words),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: relation, decoration: const InputDecoration(labelText: 'Relation'),
            items: ['parent','spouse','child','sibling','grandparent','other'].map((r) => DropdownMenuItem(value: r, child: Text(r[0].toUpperCase() + r.substring(1)))).toList(),
            onChanged: (v) => setSt(() => relation = v ?? 'parent')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(value: gender, decoration: const InputDecoration(labelText: 'Gender'),
              items: [('female','Female'),('male','Male'),('other','Other')].map((g) => DropdownMenuItem(value: g.$1, child: Text(g.$2))).toList(),
              onChanged: (v) => setSt(() => gender = v ?? 'female'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: dobCtrl, decoration: const InputDecoration(labelText: 'Date of Birth', hintText: 'YYYY-MM-DD'))),
          ]),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final resp = await _api.addFamilyMember({
                'name': nameCtrl.text.trim(), 'relation': relation, 'gender': gender,
                if (dobCtrl.text.trim().isNotEmpty) 'dob': dobCtrl.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
              if (resp.success) {
                _load();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success));
              } else {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ ${resp.message}'), backgroundColor: AppColors.danger));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.sage, foregroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('➕ Add Member', style: TextStyle(fontWeight: FontWeight.bold)),
          )),
        ])),
      )));
  }
}

// ── Member card ───────────────────────────────────────────────────
class _MemberCard extends StatelessWidget {
  final dynamic member; final List<Color> gradient; final bool isDark;
  final VoidCallback onTap, onDelete;
  const _MemberCard({required this.member, required this.gradient, required this.isDark, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final bpLatest  = member['latest_bp'];
    final bpStr     = bpLatest != null ? '${(bpLatest['value_1'] ?? 0).toInt()}/${(bpLatest['value_2'] ?? 0).toInt()}' : '—';
    final nextAppt  = member['next_appointment'];

    return Dismissible(
      key: Key('member_${member['id']}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async { onDelete(); return false; },
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.centerRight,
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.delete_rounded, color: AppColors.danger), Text('Delete', style: TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700))]),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: gradient[0].withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 46, height: 46, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                child: Center(child: Text((member['name'] as String? ?? 'U').substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontSize: 22, fontFamily: 'Fraunces', fontWeight: FontWeight.bold, color: Colors.white)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(member['name'] ?? '', style: const TextStyle(fontFamily: 'Fraunces', fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white)),
                Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(100)),
                    child: Text(member['relation'] ?? '', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
                  if (member['age'] != null) ...[const SizedBox(width: 6), Text('${member['age']} yrs', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7)))],
                ]),
              ])),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 20),
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (a) { if (a == 'delete') onDelete(); else onTap(); },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'view', child: Text('👁 View Details')),
                  const PopupMenuItem(value: 'delete', child: Text('🗑️ Delete', style: TextStyle(color: AppColors.danger))),
                ],
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              _StatPill('❤️', 'BP', bpStr),
              const SizedBox(width: 8),
              _StatPill('⚖️', 'Weight', member['latest_weight'] != null ? '${(member['latest_weight']['value_1'] ?? 0).toStringAsFixed(1)}kg' : '—'),
              const SizedBox(width: 8),
              _StatPill('💊', 'Meds', '${member['medicine_count'] ?? 0}'),
              const SizedBox(width: 8),
              _StatPill('🗂️', 'Docs', '${member['doc_count'] ?? 0}'),
            ]),
            if (nextAppt != null) ...[
              const SizedBox(height: 10),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Text('📅', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Next: ${nextAppt['title']} · ${nextAppt['appointment_date']}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ])),
            ],
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(100)),
                child: const Text('View Details →', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
            ]),
          ])),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String icon, label, value;
  const _StatPill(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 7),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
    child: Column(children: [
      Text(icon, style: const TextStyle(fontSize: 14)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
      Text(label, style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w600)),
    ])));
}

// ════════════════════════════════════════════════════════════════
// FAMILY MEMBER DETAIL SCREEN
// ════════════════════════════════════════════════════════════════
class FamilyMemberDetailScreen extends StatefulWidget {
  final Map<String, dynamic> member;
  const FamilyMemberDetailScreen({super.key, required this.member});

  @override
  State<FamilyMemberDetailScreen> createState() => _FamilyMemberDetailState();
}

class _FamilyMemberDetailState extends State<FamilyMemberDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _api = ApiService();
  final _picker = ImagePicker();

  late Map<String, dynamic> _member;
  Map<String, dynamic>? _features;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _member = Map.from(widget.member);
    _tabs = TabController(length: 5, vsync: this);
    _loadFeatures();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadFeatures() async {
    final resp = await _api.get('/family/members/${_member['id']}');
    if (resp.success && mounted) {
      setState(() {
        _member = resp.data;
        _features = resp.data['plan_features'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canMed = _features?['can_add_medicine'] == true;
    final canAppt = _features?['can_add_appointment'] == true;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          _member['name'] ?? '',
          style: const TextStyle(
            fontFamily: 'Fraunces',
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => _showEditSheet(isDark),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: AppColors.sage,
          unselectedLabelColor:
              isDark ? AppColors.textMutedDark : AppColors.textMuted,
          indicatorColor: AppColors.sage,
          tabs: [
            const Tab(text: '📊 Overview'),
            const Tab(text: '❤️ BP'),
            const Tab(text: '⚖️ Weight/Sugar'),
            Tab(text: canMed ? '💊 Medicines' : '💊 Meds 🔒'),
            Tab(text: canAppt ? '📅 Appointments' : '📅 Appts 🔒'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(
            member: _member,
            features: _features,
            isDark: isDark,
            onRefresh: _loadFeatures,
          ),
          _MetricTab(
            memberId: _member['id'],
            metricType: 'bp',
            label: 'Blood Pressure',
            isDark: isDark,
            unit1: 'Systolic',
            unit2: 'Diastolic',
            suffix: 'mmHg',
          ),
          _MetricTab(
            memberId: _member['id'],
            metricType: 'sugar',
            label: 'Blood Sugar',
            isDark: isDark,
            unit1: 'Fasting mg/dL',
            unit2: 'Post-meal mg/dL',
            suffix: 'mg/dL',
            showWeightTab: true,
          ),
          canMed
              ? _MedicinesTab(memberId: _member['id'], isDark: isDark)
              : _LockedTab(
                  '💊 Medicines',
                  'Premium plan required to track family medicines',
                  isDark,
                ),
          canAppt
              ? _AppointmentsTab(
                  memberId: _member['id'],
                  memberName: _member['name'],
                  isDark: isDark,
                )
              : _LockedTab(
                  '📅 Appointments',
                  'Premium plan required to manage family appointments',
                  isDark,
                ),
        ],
      ),
    );
  }

  void _showEditSheet(bool isDark) {
    final nameCtrl = TextEditingController(text: _member['name'] ?? '');
    String relation = _member['relation'] ?? 'parent';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setSt) => Padding(
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
              const Text(
                '✏️ Edit Member',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: relation,
                decoration: const InputDecoration(labelText: 'Relation'),
                items: ['parent', 'spouse', 'child', 'sibling', 'grandparent', 'other']
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(r[0].toUpperCase() + r.substring(1)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setSt(() => relation = v ?? 'parent'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final resp = await _api.updateFamilyMember(
                      _member['id'],
                      {'name': nameCtrl.text.trim(), 'relation': relation},
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (resp.success) {
                      _loadFeatures();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Updated'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatefulWidget {
  final Map<String, dynamic> member;
  final Map<String, dynamic>? features;
  final bool isDark;
  final VoidCallback onRefresh;

  const _OverviewTab({
    required this.member,
    this.features,
    required this.isDark,
    required this.onRefresh,
  });

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  final _api = ApiService();
  final _picker = ImagePicker();
  List<dynamic> _docs = [];
  bool _loadingDocs = true;
  int _docLimit = 0;

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    setState(() => _loadingDocs = true);
    final resp = await _api.get('/family/members/${widget.member['id']}/documents');
    if (resp.success && mounted) {
      setState(() {
        _docs = resp.data['documents'] ?? [];
        _docLimit = resp.data['limit'] ?? 0;
      });
    }
    if (mounted) setState(() => _loadingDocs = false);
  }

  Future<void> _uploadDoc() async {
    if (_docLimit != 0 && _docs.length >= _docLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _docLimit == 1
                ? '🔒 Normal plan: 1 document per member. Upgrade for unlimited.'
                : '🔒 Document limit reached',
          ),
          backgroundColor: AppColors.warning,
          action: SnackBarAction(
            label: 'Upgrade',
            onPressed: () => Navigator.pushNamed(context, '/plans'),
            textColor: Colors.white,
          ),
        ),
      );
      return;
    }

    final titleCtrl = TextEditingController();
    String docType = 'lab_report';
    File? selectedFile;
    String? fileName;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setSt) => Padding(
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
              const Text(
                '📎 Upload Document',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Document Title'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: docType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'lab_report', child: Text('🧪 Lab Report')),
                  DropdownMenuItem(value: 'prescription', child: Text('💊 Prescription')),
                  DropdownMenuItem(value: 'xray', child: Text('🦴 X-Ray')),
                  DropdownMenuItem(value: 'other', child: Text('📄 Other')),
                ],
                onChanged: (v) => setSt(() => docType = v ?? 'lab_report'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.attach_file_rounded, size: 18),
                      label: const Text('Pick File'),
                      onPressed: () async {
                        final r = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                        );
                        if (r != null && r.files.single.path != null) {
                          setSt(() {
                            selectedFile = File(r.files.single.path!);
                            fileName = r.files.single.name;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.camera_alt_rounded, size: 18),
                      label: const Text('Camera'),
                      onPressed: () async {
                        final img = await _picker.pickImage(
                          source: ImageSource.camera,
                          imageQuality: 80,
                        );
                        if (img != null) {
                          setSt(() {
                            selectedFile = File(img.path);
                            fileName = 'doc_${DateTime.now().millisecondsSinceEpoch}.jpg';
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              if (selectedFile != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            fileName ?? '',
                            style: const TextStyle(fontSize: 12, color: AppColors.success),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (titleCtrl.text.trim().isEmpty || selectedFile == null)
                      ? null
                      : () async {
                          final bytes = await selectedFile!.readAsBytes();
                          final b64 = base64Encode(bytes);
                          final resp = await _api.post(
                            '/family/members/${widget.member['id']}/documents',
                            data: {
                              'title': titleCtrl.text.trim(),
                              'doc_type': docType,
                              'file_data': b64,
                              'file_name': fileName,
                            },
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (resp.success) {
                            _loadDocs();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ Document uploaded'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            }
                          }
                        },
                  child: const Text('Upload'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteDoc(dynamic doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Document'),
        content: Text('Remove "${doc['title']}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(_, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final resp = await _api.delete('/family/members/${widget.member['id']}/documents/${doc['id']}');
      if (resp.success) {
        _loadDocs();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🗑️ ${doc['title']} deleted'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final m = widget.member;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    final bpL = m['latest_bp'];
    final sugL = m['latest_sugar'];
    final wtL = m['latest_weight'];

    return RefreshIndicator(
      onRefresh: () async {
        widget.onRefresh();
        _loadDocs();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _VitalCard(
                '❤️',
                'Blood Pressure',
                bpL != null
                    ? '${(bpL['value_1'] ?? 0).toInt()}/${(bpL['value_2'] ?? 0).toInt()}'
                    : '—',
                'mmHg',
                AppColors.danger,
                isDark,
              ),
              const SizedBox(width: 12),
              _VitalCard(
                '🩺',
                'Blood Sugar',
                sugL != null ? '${(sugL['value_1'] ?? 0).toInt()}' : '—',
                'mg/dL',
                AppColors.sugar,
                isDark,
              ),
              const SizedBox(width: 12),
              _VitalCard(
                '⚖️',
                'Weight',
                wtL != null ? '${(wtL['value_1'] ?? 0).toStringAsFixed(1)}' : '—',
                'kg',
                AppColors.violet,
                isDark,
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                  '👤 Profile',
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: tp,
                  ),
                ),
                const SizedBox(height: 12),
                if (m['age'] != null) _InfoRow('🎂', 'Age', '${m['age']} years', tp, tm),
                if (m['gender'] != null) _InfoRow('⚧', 'Gender', m['gender'] ?? '', tp, tm),
                if (m['blood_group'] != null) _InfoRow('🩸', 'Blood Group', m['blood_group'] ?? '', tp, tm),
                if (m['bmi'] != null) _InfoRow('📊', 'BMI', '${m['bmi']}', tp, tm),
                if (m['emergency_contact'] != null) _InfoRow('📞', 'Emergency', m['emergency_contact'] ?? '', tp, tm),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '🗂️ Documents',
                        style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: tp,
                        ),
                      ),
                    ),
                    Text(
                      '${_docs.length}/${_docLimit == 999 ? '∞' : _docLimit}',
                      style: TextStyle(fontSize: 12, color: tm, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _uploadDoc,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.document.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: AppColors.document.withOpacity(0.3)),
                        ),
                        child: const Text(
                          '+ Upload',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.document),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_loadingDocs)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2))
                else if (_docs.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No documents yet. Tap + Upload.',
                        style: TextStyle(color: tm, fontSize: 13),
                      ),
                    ),
                  )
                else
                  ..._docs.map(
                    (d) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Text(
                        {
                              'lab_report': '🧪',
                              'prescription': '💊',
                              'xray': '🦴',
                              'other': '📄',
                            }[d['doc_type']] ??
                            '📄',
                        style: const TextStyle(fontSize: 22),
                      ),
                      title: Text(
                        d['title'] ?? '',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tp),
                      ),
                      subtitle: Text(
                        d['doc_type']?.toString().replaceAll('_', ' ').toUpperCase() ?? '',
                        style: TextStyle(fontSize: 10, color: AppColors.document, fontWeight: FontWeight.w700),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                        onPressed: () => _deleteDoc(d),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String icon, label, value;
  final Color tp, tm;

  const _InfoRow(this.icon, this.label, this.value, this.tp, this.tm);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text('$label:', style: TextStyle(fontSize: 12, color: tm, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: tp, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

class _VitalCard extends StatelessWidget {
  final String icon, label, value, unit;
  final Color color;
  final bool isDark;

  const _VitalCard(this.icon, this.label, this.value, this.unit, this.color, this.isDark);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(isDark ? 0.15 : 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w700, color: color),
                textAlign: TextAlign.center,
              ),
              Text(unit, style: TextStyle(fontSize: 9, color: color.withOpacity(0.8), fontWeight: FontWeight.w600)),
              Text(label, style: TextStyle(fontSize: 9, color: color.withOpacity(0.7)), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _MetricTab extends StatefulWidget {
  final int memberId;
  final String metricType, label, unit1, unit2, suffix;
  final bool isDark, showWeightTab;

  const _MetricTab({
    required this.memberId,
    required this.metricType,
    required this.label,
    required this.isDark,
    required this.unit1,
    required this.unit2,
    required this.suffix,
    this.showWeightTab = false,
  });

  @override
  State<_MetricTab> createState() => _MetricTabState();
}

class _MetricTabState extends State<_MetricTab> {
  final _api = ApiService();
  final _v1 = TextEditingController();
  final _v2 = TextEditingController();
  List<dynamic> _records = [];
  bool _loading = true, _saving = false;
  String _currentType = '';

  @override
  void initState() {
    super.initState();
    _currentType = widget.metricType;
    _load();
  }

  @override
  void dispose() {
    _v1.dispose();
    _v2.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.get('/family/members/${widget.memberId}/metrics', query: {'type': _currentType});
    if (r.success && mounted) setState(() => _records = r.data['records'] ?? []);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final v1 = double.tryParse(_v1.text);
    if (v1 == null) return;
    final v2 = double.tryParse(_v2.text);
    setState(() => _saving = true);
    final r = await _api.post('/family/members/${widget.memberId}/metrics', data: {
      'metric_type': _currentType,
      'value_1': v1,
      'value_2': v2,
    });
    setState(() => _saving = false);
    if (r.success) {
      _v1.clear();
      _v2.clear();
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Saved'), backgroundColor: AppColors.success),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.showWeightTab)
            Row(
              children: [
                for (final t in const [
                  ('sugar', '🩺 Sugar'),
                  ('weight', '⚖️ Weight'),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _currentType = t.$1);
                          _load();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _currentType == t.$1
                                ? AppColors.sage
                                : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _currentType == t.$1 ? AppColors.sage : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            t.$2,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _currentType == t.$1 ? AppColors.navy : tm,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
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
                  '➕ Log ${_currentType == 'weight' ? 'Weight' : _currentType == 'sugar' ? 'Blood Sugar' : 'Blood Pressure'}',
                  style: TextStyle(fontFamily: 'Fraunces', fontSize: 15, fontWeight: FontWeight.bold, color: tp),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _v1,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _currentType == 'bp'
                              ? 'Systolic'
                              : _currentType == 'sugar'
                                  ? 'Fasting'
                                  : 'Weight (kg)',
                        ),
                      ),
                    ),
                    if (_currentType == 'bp' || _currentType == 'sugar') ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _v2,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: _currentType == 'bp' ? 'Diastolic' : 'Post-meal',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.sage,
                      foregroundColor: AppColors.navy,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Reading', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const LoadingView()
          else
            ..._records.map(
              (r) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: brd),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${(r['value_1'] ?? 0).toStringAsFixed(1)}${r['value_2'] != null ? '/${(r['value_2'] ?? 0).toStringAsFixed(1)}' : ''} ${_currentType == 'bp' ? 'mmHg' : _currentType == 'weight' ? 'kg' : 'mg/dL'}',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w700, color: tp),
                      ),
                    ),
                    Text(r['recorded_time'] ?? '', style: TextStyle(fontSize: 11, color: tm)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final ok = await showConfirmDialog(context, 'Delete', 'Remove this reading?');
                        if (ok) {
                          await _api.delete('/family/members/${widget.memberId}/metrics/${r['id']}');
                          _load();
                        }
                      },
                      child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _MedicinesTab extends StatefulWidget {
  final int memberId;
  final bool isDark;
  const _MedicinesTab({required this.memberId, required this.isDark});

  @override
  State<_MedicinesTab> createState() => _MedicinesTabState();
}

class _MedicinesTabState extends State<_MedicinesTab> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _doseCtrl = TextEditingController();
  List<dynamic> _meds = [];
  bool _loading = true, _saving = false;
  String _timing = 'morning';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _doseCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.get('/family/members/${widget.memberId}/medicines');
    if (r.success && mounted) setState(() => _meds = r.data['medicines'] ?? []);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final r = await _api.post('/family/members/${widget.memberId}/medicines', data: {
      'name': _nameCtrl.text.trim(),
      'dosage': _doseCtrl.text.trim(),
      'timing': _timing,
    });
    setState(() => _saving = false);
    if (r.success) {
      _nameCtrl.clear();
      _doseCtrl.clear();
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Medicine added'), backgroundColor: AppColors.success),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: brd)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('➕ Add Medicine', style: TextStyle(fontFamily: 'Fraunces', fontSize: 15, fontWeight: FontWeight.bold, color: tp)),
                const SizedBox(height: 12),
                TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Medicine Name')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: TextField(controller: _doseCtrl, decoration: const InputDecoration(labelText: 'Dosage', hintText: '500mg'))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _timing,
                        decoration: const InputDecoration(labelText: 'Timing'),
                        items: const [
                          DropdownMenuItem(value: 'morning', child: Text('🌅 Morning')),
                          DropdownMenuItem(value: 'afternoon', child: Text('☀️ Afternoon')),
                          DropdownMenuItem(value: 'evening', child: Text('🌆 Evening')),
                          DropdownMenuItem(value: 'night', child: Text('🌙 Night')),
                        ],
                        onChanged: (v) => setState(() => _timing = v ?? 'morning'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _add,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.medicine,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('💊 Add Medicine', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const LoadingView()
          else
            ..._meds.map(
              (m) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14), border: Border.all(color: brd)),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: AppColors.medicine.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Text('💊', style: TextStyle(fontSize: 18))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m['name'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tp)),
                          Text('${m['dosage'] ?? ''} · ${m['timing'] ?? ''}', style: TextStyle(fontSize: 12, color: tm)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                      onPressed: () async {
                        final ok = await showConfirmDialog(context, 'Delete Medicine', 'Remove ${m['name']}?');
                        if (ok) {
                          await _api.delete('/family/members/${widget.memberId}/medicines/${m['id']}');
                          _load();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _AppointmentsTab extends StatefulWidget {
  final int memberId;
  final String? memberName;
  final bool isDark;

  const _AppointmentsTab({
    required this.memberId,
    this.memberName,
    required this.isDark,
  });

  @override
  State<_AppointmentsTab> createState() => _AppointmentsTabState();
}

class _AppointmentsTabState extends State<_AppointmentsTab> {
  final _api = ApiService();
  final _titleCtrl = TextEditingController();
  final _locCtrl = TextEditingController();

  List<dynamic> _appts = [];
  bool _loading = true, _saving = false;

  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  String _type = 'doctor';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.get('/family/members/${widget.memberId}/appointments');
    if (r.success && mounted) setState(() => _appts = r.data['appointments'] ?? []);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final r = await _api.post('/family/members/${widget.memberId}/appointments', data: {
      'title': _titleCtrl.text.trim(),
      'appointment_type': _type,
      'appointment_date': _date.toIso8601String().substring(0, 10),
      'appointment_time': '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      'location': _locCtrl.text.trim(),
    });
    setState(() => _saving = false);
    if (r.success) {
      _titleCtrl.clear();
      _locCtrl.clear();
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ ${r.message} (reminder set)'), backgroundColor: AppColors.success),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: brd)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📅 Add Appointment', style: TextStyle(fontFamily: 'Fraunces', fontSize: 15, fontWeight: FontWeight.bold, color: tp)),
                const SizedBox(height: 4),
                Text('A notification reminder will be sent automatically', style: TextStyle(fontSize: 11, color: AppColors.success)),
                const SizedBox(height: 12),
                TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Dr. Sharma Checkup')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'doctor', child: Text('👨‍⚕️ Doctor')),
                    DropdownMenuItem(value: 'lab', child: Text('🧪 Lab Test')),
                    DropdownMenuItem(value: 'vaccination', child: Text('💉 Vaccination')),
                    DropdownMenuItem(value: 'other', child: Text('📅 Other')),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? 'doctor'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2030),
                          );
                          if (d != null) setState(() => _date = d);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(border: Border.all(color: brd), borderRadius: BorderRadius.circular(14)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Date', style: TextStyle(fontSize: 11, color: tm)),
                              Text('${_date.day}/${_date.month}/${_date.year}', style: TextStyle(fontWeight: FontWeight.w700, color: tp)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final t = await showTimePicker(context: context, initialTime: _time);
                          if (t != null) setState(() => _time = t);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(border: Border.all(color: brd), borderRadius: BorderRadius.circular(14)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Time', style: TextStyle(fontSize: 11, color: tm)),
                              Text(_time.format(context), style: TextStyle(fontWeight: FontWeight.w700, color: tp)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(controller: _locCtrl, decoration: const InputDecoration(labelText: 'Location (optional)', hintText: 'Hospital / Clinic')),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _add,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.info,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('📅 Add + Set Reminder', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const LoadingView()
          else if (_appts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No appointments yet.', style: TextStyle(color: tm)),
              ),
            )
          else
            ..._appts.map(
              (a) {
                final done = a['completed'] == true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: done ? AppColors.success.withOpacity(0.3) : brd),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: AppColors.info.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: Center(
                          child: Text(
                            {
                              'doctor': '👨‍⚕️',
                              'lab': '🧪',
                              'vaccination': '💉',
                              'other': '📅',
                            }[a['appointment_type']] ?? '📅',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a['title'] ?? '',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: tp,
                                decoration: done ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            Text(
                              '${a['appointment_date']} · ${a['appointment_time'] ?? ''}',
                              style: TextStyle(fontSize: 12, color: tm),
                            ),
                            if (a['location'] != null)
                              Text(a['location'], style: TextStyle(fontSize: 11, color: tm)),
                          ],
                        ),
                      ),
                      if (!done)
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 18),
                          onPressed: () async {
                            final ok = await showConfirmDialog(context, 'Delete', 'Remove this appointment?');
                            if (ok) {
                              await _api.delete('/family/members/${widget.memberId}/appointments/${a['id']}');
                              _load();
                            }
                          },
                        )
                      else
                        const Text('✅', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _LockedTab extends StatelessWidget {
  final String title, subtitle;
  final bool isDark;

  const _LockedTab(this.title, this.subtitle, this.isDark);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔒', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/plans'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.violet,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('💎 Upgrade Plan', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
}