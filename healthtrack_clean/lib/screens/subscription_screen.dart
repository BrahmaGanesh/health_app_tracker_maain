// lib/screens/subscription_screen.dart — Premium / Family Plans
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _api = ApiService();
  String _currentPlan = 'free';
  bool _loading = true, _purchasing = false;
  String _selectedPlan = 'premium';

  @override void initState() { super.initState(); _loadStatus(); }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    final resp = await _api.getSubscriptionStatus();
    if (resp.success) setState(() => _currentPlan = resp.data['plan'] ?? 'free');
    setState(() => _loading = false);
  }

  static const _features = [
    ('Core tracking (BP, weight, water, etc.)', true, true, true),
    ('Basic reminders', true, true, true),
    ('Health score', true, true, true),
    ('Emergency card', true, true, true),
    ('History', '7 days', 'Unlimited', 'Unlimited'),
    ('Smart reminder escalation', false, true, true),
    ('Health reports (PDF/Email)', false, true, true),
    ('AI camera (meal/medicine scan)', false, true, true),
    ('AI wellness assistant', false, true, true),
    ('Lab test tracker', false, true, true),
    ('Document vault', false, true, true),
    ('Exercise & yoga library', false, true, true),
    ('Healthy recipes', false, true, true),
    ('Emergency alerts to contacts', false, true, true),
    ('Family members (up to 3)', false, false, true),
    ('Family combined reports', false, false, true),
    ('Caregiver alerts', false, false, true),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Plans', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold))),
      body: _loading ? const Center(child: CircularProgressIndicator(color: AppColors.sage))
          : SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [

              // Hero
              Container(padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.navy, AppColors.violet]), borderRadius: BorderRadius.circular(24)),
                child: Column(children: [
                  const Text('💎', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 10),
                  const Text('Unlock Your Full Health Journey', style: TextStyle(fontFamily: 'Fraunces', fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white), textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Text('Currently on: ${_currentPlan[0].toUpperCase()}${_currentPlan.substring(1)} plan', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
                ])),
              const SizedBox(height: 20),

              // Plan cards
              _PlanCard(name: 'Free', price: '₹0', period: 'forever', icon: '🆓',
                  color: AppColors.textMuted, current: _currentPlan == 'free', selected: _selectedPlan == 'free',
                  onTap: () => setState(() => _selectedPlan = 'free'), isDark: isDark),
              const SizedBox(height: 12),
              _PlanCard(name: 'Premium', price: '₹199', period: '/month', icon: '⭐', badge: 'POPULAR',
                  color: AppColors.sage, current: _currentPlan == 'premium', selected: _selectedPlan == 'premium',
                  onTap: () => setState(() => _selectedPlan = 'premium'), isDark: isDark),
              const SizedBox(height: 12),
              _PlanCard(name: 'Family', price: '₹349', period: '/month', icon: '👨‍👩‍👧', badge: 'BEST VALUE',
                  color: AppColors.violet, current: _currentPlan == 'family', selected: _selectedPlan == 'family',
                  onTap: () => setState(() => _selectedPlan = 'family'), isDark: isDark),
              const SizedBox(height: 24),

              if (_currentPlan != _selectedPlan)
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: _purchasing ? null : _purchase,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.sage, foregroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _purchasing ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(_selectedPlan == 'free' ? 'Downgrade to Free' : 'Upgrade to ${_selectedPlan[0].toUpperCase()}${_selectedPlan.substring(1)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                )),
              const SizedBox(height: 8),
              Text('Payments via Google Play · Auto-renews · Cancel anytime', style: TextStyle(fontSize: 11, color: tm), textAlign: TextAlign.center),
              const SizedBox(height: 24),

              // Feature comparison table
              Container(decoration: BoxDecoration(color: isDark ? AppColors.cardDark : Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200)),
                child: Column(children: [
                  Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                    Expanded(flex: 3, child: Text('FEATURE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: tm, letterSpacing: 0.5))),
                    Expanded(child: Text('FREE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: tm), textAlign: TextAlign.center)),
                    Expanded(child: Text('PREM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.sage), textAlign: TextAlign.center)),
                    Expanded(child: Text('FAM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.violet), textAlign: TextAlign.center)),
                  ])),
                  ..._features.map((f) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade100))),
                    child: Row(children: [
                      Expanded(flex: 3, child: Text(f.$1, style: TextStyle(fontSize: 12, color: tp))),
                      Expanded(child: Center(child: _FeatureCell(f.$2))),
                      Expanded(child: Center(child: _FeatureCell(f.$3))),
                      Expanded(child: Center(child: _FeatureCell(f.$4))),
                    ]),
                  )),
                ])),
              const SizedBox(height: 40),
            ])),
    );
  }

  Future<void> _purchase() async {
    setState(() => _purchasing = true);
    // NOTE: integrate google_play_billing here via in_app_purchase package
    // This is the verification call after Play Store purchase completes
    await Future.delayed(const Duration(seconds: 1));
    setState(() { _purchasing = false; _currentPlan = _selectedPlan; });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🎉 Welcome to ${_selectedPlan[0].toUpperCase()}${_selectedPlan.substring(1)}!'), backgroundColor: AppColors.success));
  }
}

class _FeatureCell extends StatelessWidget {
  final dynamic value;
  const _FeatureCell(this.value);
  @override
  Widget build(BuildContext context) {
    if (value is bool) {
      return Text(value ? '✓' : '—', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: value ? AppColors.success : AppColors.textMuted));
    }
    return Text('$value', style: const TextStyle(fontSize: 10, color: AppColors.textMuted), textAlign: TextAlign.center);
  }
}

class _PlanCard extends StatelessWidget {
  final String name, price, period, icon;
  final String? badge;
  final Color color;
  final bool current, selected, isDark;
  final VoidCallback onTap;
  const _PlanCard({required this.name, required this.price, required this.period, required this.icon,
      this.badge, required this.color, required this.current, required this.selected, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? color : (isDark ? const Color(0xFF1E3250) : Colors.grey.shade200), width: selected ? 2 : 1),
      ),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 32)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(name, style: TextStyle(fontFamily: 'Fraunces', fontSize: 17, fontWeight: FontWeight.bold, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
            if (badge != null) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(100)),
                child: Text(badge!, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)))],
            if (current) ...[const SizedBox(width: 8), const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 16)],
          ]),
          Row(children: [
            Text(price, style: TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(period, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ])),
        Radio<bool>(value: true, groupValue: selected, onChanged: (_) => onTap(), activeColor: color),
      ]),
    ));
  }
}