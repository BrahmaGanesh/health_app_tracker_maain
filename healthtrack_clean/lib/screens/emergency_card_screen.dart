// lib/screens/emergency_card_screen.dart — FIXED Emergency Medical Card
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';

class EmergencyCardScreen extends StatefulWidget {
  final bool standalone;
  const EmergencyCardScreen({super.key, this.standalone = false});
  @override State<EmergencyCardScreen> createState() => _EmergencyCardScreenState();
}

class _EmergencyCardScreenState extends State<EmergencyCardScreen> {
  final _api = ApiService();
  final _db  = LocalDb();
  Map<String, dynamic>? _card;
  bool _loading = true, _error = false;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    try {
      // Always load from local cache first (works offline)
      final local = await _db.getEmergencyCard(0);
      if (local != null) setState(() => _card = local);

      // Then try server for latest data
      final resp = await _api.getEmergencyCard();
      if (resp.success && resp.data != null) {
        // Cache locally for offline use
        await _db.saveEmergencyCard(0, {
          'blood_group': resp.data['blood_group'] ?? '',
          'allergies':   resp.data['allergies'] ?? '',
          'conditions':  (resp.data['conditions'] as List?)?.join(', ') ?? '',
          'medicines':   (resp.data['medicines']  as List?)?.join(', ') ?? '',
          'emergency_contacts': resp.data['emergency_contacts'] ?? '',
        });
        setState(() => _card = resp.data);
      }
    } catch (e) {
      if (_card == null) setState(() => _error = true);
    }
    setState(() => _loading = false);
  }

  List<String> _asList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.cast<String>();
    if (val is String && val.isNotEmpty) return val.split(', ').where((s) => s.isNotEmpty).toList();
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFB91C1C),
      appBar: widget.standalone ? null : AppBar(
        backgroundColor: const Color(0xFF991B1B),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Emergency Card', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold, color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.white), onPressed: () => _showEditSheet()),
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error && _card == null
          ? _buildError()
          : SafeArea(child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                if (widget.standalone) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(100)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('🚨', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 8),
                      Text('EMERGENCY MEDICAL CARD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
                    ]),
                  ),
                  const SizedBox(height: 20),
                ],

                // Main white card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 12))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Header: name + blood group
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(16)),
                        child: const Center(child: Text('🩸', style: TextStyle(fontSize: 26))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_card?['name'] ?? 'Not set', style: const TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.navy)),
                        if (_card?['age'] != null)
                          Text('${_card!['age']} years · ${_card?['gender'] ?? ''}', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0xFFB91C1C), borderRadius: BorderRadius.circular(12)),
                        child: Text(_card?['blood_group'] ?? '?', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
                    ]),
                    const Divider(height: 28),

                    // Allergies
                    _InfoSection('⚠️', 'ALLERGIES',
                        _asList(_card?['allergies']).isEmpty ? ['None reported'] : _asList(_card?['allergies']),
                        color: const Color(0xFFDC2626)),

                    const SizedBox(height: 16),

                    // Conditions
                    _InfoSection('🏥', 'MEDICAL CONDITIONS',
                        _asList(_card?['conditions']).isEmpty ? ['None reported'] : _asList(_card?['conditions']),
                        color: AppColors.violet),

                    const SizedBox(height: 16),

                    // Medicines
                    _InfoSection('💊', 'CURRENT MEDICINES',
                        _asList(_card?['medicines']).isEmpty ? ['None reported'] : _asList(_card?['medicines']),
                        color: AppColors.medicine),
                  ]),
                ),
                const SizedBox(height: 16),

                // Emergency contacts
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12)]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Text('📞', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 8),
                      Text('EMERGENCY CONTACTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: AppColors.textMuted)),
                    ]),
                    const SizedBox(height: 12),
                    Text(
                      (_card?['emergency_contacts']?.toString().isNotEmpty == true)
                          ? _card!['emergency_contacts']
                          : 'No emergency contacts added.\nTap ✏️ to add.',
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.6),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // Quick-copy button
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: () {
                    final text = 'EMERGENCY MEDICAL INFO\n'
                        'Name: ${_card?['name'] ?? 'Unknown'}\n'
                        'Blood Group: ${_card?['blood_group'] ?? 'Unknown'}\n'
                        'Allergies: ${_card?['allergies'] ?? 'None'}\n'
                        'Conditions: ${_asList(_card?['conditions']).join(', ')}\n'
                        'Medicines: ${_asList(_card?['medicines']).join(', ')}\n'
                        'Contacts: ${_card?['emergency_contacts'] ?? 'None'}';
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📋 Copied to clipboard'), backgroundColor: AppColors.success));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2), foregroundColor: Colors.white, elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.white.withOpacity(0.4))),
                  ),
                  child: const Text('📋 Copy to Clipboard', style: TextStyle(fontWeight: FontWeight.bold)),
                )),

                if (!widget.standalone) ...[
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: ElevatedButton(
                    onPressed: _showEditSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white, foregroundColor: const Color(0xFFB91C1C),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('✏️ Edit Emergency Info', style: TextStyle(fontWeight: FontWeight.bold)),
                  )),
                ],
                const SizedBox(height: 20),
              ]),
            )),
    );
  }

  Widget _buildError() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Text('😕', style: TextStyle(fontSize: 48)),
    const SizedBox(height: 12),
    const Text('Could not load emergency card', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
    const SizedBox(height: 8),
    ElevatedButton(onPressed: _load, style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFFB91C1C)), child: const Text('Retry')),
  ]));

  void _showEditSheet() {
    final bloodCtrl = TextEditingController(text: _card?['blood_group'] ?? '');
    final allergyCtrl = TextEditingController(text: _asList(_card?['allergies']).join(', '));
    final contactCtrl = TextEditingController(text: _card?['emergency_contacts'] ?? '');

    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('✏️ Edit Emergency Card', style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.navy)),
          const SizedBox(height: 16),
          TextField(controller: bloodCtrl, decoration: const InputDecoration(labelText: 'Blood Group', hintText: 'O+ / A+ / B+ / AB+')),
          const SizedBox(height: 12),
          TextField(controller: allergyCtrl, decoration: const InputDecoration(labelText: 'Allergies', hintText: 'Penicillin, Peanuts (comma separated)'), maxLines: 2),
          const SizedBox(height: 12),
          TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Emergency Contacts', hintText: 'Priya: +91 98765 43210\nRama: +91 98765 00000'), maxLines: 3),
          const SizedBox(height: 16),
          const Text('Conditions and medicines are pulled from your health profile and medicine list automatically.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.4)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final resp = await _api.updateEmergencyCard({
                'blood_group': bloodCtrl.text.trim(),
                'allergies':   allergyCtrl.text.trim(),
                'emergency_contacts': contactCtrl.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
              if (resp.success) { _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Emergency card updated'), backgroundColor: AppColors.success)); }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB91C1C), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Save Emergency Card', style: TextStyle(fontWeight: FontWeight.bold)),
          )),
        ])),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String icon, label; final List<String> items; final Color color;
  const _InfoSection(this.icon, this.label, this.items, {required this.color});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Text(icon, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: color)),
    ]),
    const SizedBox(height: 6),
    ...items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(margin: const EdgeInsets.only(top: 6), width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Expanded(child: Text(item, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4))),
    ]))),
  ]);
}