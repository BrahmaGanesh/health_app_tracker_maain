// lib/screens/emergency_card_screen.dart — Module 14: Emergency Medical Card
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import '../widgets/common_widgets.dart';

class EmergencyCardScreen extends StatefulWidget {
  final bool standalone; // true = accessed without login (lock screen shortcut)
  const EmergencyCardScreen({super.key, this.standalone = false});
  @override State<EmergencyCardScreen> createState() => _EmergencyCardScreenState();
}

class _EmergencyCardScreenState extends State<EmergencyCardScreen> {
  final _api = ApiService();
  final _db  = LocalDb();
  Map<String, dynamic>? _card;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getEmergencyCard();
    if (resp.success) {
      setState(() => _card = resp.data);
      // Cache locally so it works WITHOUT internet — critical for emergencies
      await _db.saveEmergencyCard(0, {
        'blood_group': resp.data['blood_group'],
        'allergies': resp.data['allergies'],
        'conditions': resp.data['conditions']?.join(', '),
        'medicines': resp.data['medicines']?.join(', '),
        'emergency_contacts': resp.data['emergency_contacts'],
      });
    } else {
      final local = await _db.getEmergencyCard(0);
      if (local != null) setState(() => _card = local);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFB91C1C), // Always red theme — instantly recognisable
      appBar: widget.standalone ? null : AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        title: const Text('Emergency Card', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.white), onPressed: _showEditSheet)],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SafeArea(child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                if (widget.standalone) ...[
                  const SizedBox(height: 20),
                  const Text('🚨', style: TextStyle(fontSize: 60)),
                  const SizedBox(height: 8),
                  const Text('EMERGENCY MEDICAL CARD', style: TextStyle(fontFamily: 'Fraunces', fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1)),
                  const SizedBox(height: 30),
                ],

                // Main card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 24, offset: const Offset(0, 12))]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 56, height: 56, decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(16)),
                          child: const Center(child: Text('🩸', style: TextStyle(fontSize: 26)))),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_card?['name'] ?? 'User', style: const TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.navy)),
                        Text('${_card?['age'] ?? '—'} years · ${_card?['gender'] ?? '—'}', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      ])),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: const Color(0xFFB91C1C), borderRadius: BorderRadius.circular(12)),
                          child: Text(_card?['blood_group'] ?? '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))),
                    ]),
                    const Divider(height: 32),

                    _InfoRow(icon: '⚠️', label: 'ALLERGIES', value: _card?['allergies'] ?? 'None reported', color: AppColors.danger),
                    const SizedBox(height: 14),
                    _InfoRow(icon: '🏥', label: 'CONDITIONS', value: (_card?['conditions'] is List ? (_card!['conditions'] as List).join(', ') : _card?['conditions']) ?? 'None reported', color: AppColors.violet),
                    const SizedBox(height: 14),
                    _InfoRow(icon: '💊', label: 'CURRENT MEDICINES', value: (_card?['medicines'] is List ? (_card!['medicines'] as List).join(', ') : _card?['medicines']) ?? 'None reported', color: AppColors.medicine),
                  ]),
                ),
                const SizedBox(height: 20),

                // Emergency contacts
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [Text('📞', style: TextStyle(fontSize: 18)), SizedBox(width: 8),
                      Text('Emergency Contacts', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navy))]),
                    const SizedBox(height: 12),
                    if (_card?['emergency_contacts'] == null || (_card!['emergency_contacts'] as String).isEmpty)
                      const Text('No emergency contacts added', style: TextStyle(fontSize: 13, color: AppColors.textMuted))
                    else
                      Text(_card!['emergency_contacts'], style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.6)),
                  ]),
                ),
                const SizedBox(height: 20),

                if (widget.standalone)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
                    child: const Text('This card is visible without unlocking the app for emergency responders.',
                        style: TextStyle(fontSize: 12, color: Colors.white, height: 1.5), textAlign: TextAlign.center),
                  ),
              ]),
            )),
    );
  }

  void _showEditSheet() {
    final allergiesCtrl = TextEditingController(text: _card?['allergies'] ?? '');
    final contactsCtrl  = TextEditingController(text: _card?['emergency_contacts'] ?? '');
    final bloodGroupCtrl= TextEditingController(text: _card?['blood_group'] ?? '');

    showModalBottomSheet(context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('✏️ Edit Emergency Info', style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          TextField(controller: bloodGroupCtrl, decoration: const InputDecoration(labelText: 'Blood Group', hintText: 'O+')),
          const SizedBox(height: 10),
          TextField(controller: allergiesCtrl, decoration: const InputDecoration(labelText: 'Allergies', hintText: 'e.g. Penicillin, Peanuts'), maxLines: 2),
          const SizedBox(height: 10),
          TextField(controller: contactsCtrl, decoration: const InputDecoration(labelText: 'Emergency Contacts', hintText: 'Name: Phone, Name: Phone'), maxLines: 3),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
            final resp = await _api.updateEmergencyCard({
              'blood_group': bloodGroupCtrl.text.trim(), 'allergies': allergiesCtrl.text.trim(),
              'emergency_contacts': contactsCtrl.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            if (resp.success) { _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Updated'), backgroundColor: AppColors.success)); }
          }, child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)))),
        ])),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String icon, label, value;
  final Color color;
  const _InfoRow({required this.icon, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(icon, style: const TextStyle(fontSize: 18)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: color)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4)),
      ])),
    ]);
  }
}