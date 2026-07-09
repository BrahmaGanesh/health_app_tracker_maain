// lib/screens/onboarding_screen.dart — Smooth 5-step onboarding
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/security_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with TickerProviderStateMixin {
  final _api      = ApiService();
  final _security = SecurityService();
  final _pageCtrl = PageController();
  int _page = 0;
  bool _saving = false;

  // Step 1 — Basic info
  final _nameCtrl   = TextEditingController();
  String _gender    = 'female';

  // Step 2 — Health profile
  final _ageCtrl    = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String _activity  = 'moderate';

  // Step 3 — Conditions
  final List<String> _allConditions = [
    'High Blood Pressure', 'Type 2 Diabetes', 'Pre-Diabetes',
    'High Cholesterol', 'Weight Loss Goal', 'Healthy Lifestyle',
    'Heart Disease', 'Thyroid', 'PCOS / PCOD', 'Kidney Disease',
  ];
  final Set<String> _selectedConditions = {};

  // Step 4 — Goals
  final _targetWeightCtrl = TextEditingController();
  final _targetStepsCtrl  = TextEditingController(text: '8000');
  final _targetWaterCtrl  = TextEditingController(text: '2.5');

  // Step 5 — Security
  bool _setupPin        = false;
  bool _setupBiometric  = false;
  bool _biometricAvail  = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    _biometricAvail = await _security.isBiometricAvailable();
    setState(() {});
  }

  @override
  void dispose() {
    _pageCtrl.dispose(); _nameCtrl.dispose(); _ageCtrl.dispose();
    _heightCtrl.dispose(); _weightCtrl.dispose(); _targetWeightCtrl.dispose();
    _targetStepsCtrl.dispose(); _targetWaterCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < 4) {
      _pageCtrl.animateToPage(_page + 1, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
      setState(() => _page++);
    } else {
      _finish();
    }
  }

  void _prev() {
    if (_page > 0) {
      _pageCtrl.animateToPage(_page - 1, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
      setState(() => _page--);
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);

    // Save health profile
    await _api.post('/auth/onboarding', data: {
      'gender':        _gender,
      'age':           int.tryParse(_ageCtrl.text) ?? 30,
      'height_cm':     double.tryParse(_heightCtrl.text),
      'weight_kg':     double.tryParse(_weightCtrl.text),
      'activity_level':_activity,
      'conditions':    _selectedConditions.toList(),
      'target_weight': double.tryParse(_targetWeightCtrl.text),
      'target_steps':  int.tryParse(_targetStepsCtrl.text) ?? 8000,
      'target_water':  double.tryParse(_targetWaterCtrl.text) ?? 2.5,
    });

    // Security setup
    if (_setupBiometric) await _security.enableBiometric();

    setState(() => _saving = false);

    if (mounted) {
      Navigator.of(context).pushReplacementNamed(_setupPin ? '/pin-setup' : '/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: Column(children: [
        // Progress bar
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              if (_page > 0)
                GestureDetector(onTap: _prev, child: Icon(Icons.arrow_back_rounded, color: isDark ? AppColors.textMutedDark : AppColors.textMuted))
              else
                const SizedBox(width: 24),
              Text('${_page + 1} of 5', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
              const SizedBox(width: 24),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(
                value: (_page + 1) / 5, minHeight: 5,
                backgroundColor: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200,
                color: AppColors.sage,
              ),
            ),
          ]),
        ),

        // Pages
        Expanded(child: PageView(
          controller: _pageCtrl,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildStep1(isDark),
            _buildStep2(isDark),
            _buildStep3(isDark),
            _buildStep4(isDark),
            _buildStep5(isDark),
          ],
        )),

        // Next button
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _next,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.sage, foregroundColor: AppColors.navy,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.navy))
                  : Text(_page == 4 ? '🚀 Get Started' : 'Continue →', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ])),
    );
  }

  Widget _buildStep1(bool isDark) => _StepWrapper(
    emoji: '👋', title: 'Welcome to HealthTrack', subtitle: 'Tell us your name so we can personalise your experience.',
    isDark: isDark,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Your name', hintText: 'e.g. Priya Sharma'), textCapitalization: TextCapitalization.words),
      const SizedBox(height: 20),
      Text('Gender', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
      const SizedBox(height: 10),
      Row(children: [
        for (final g in [('female', '👩', 'Female'), ('male', '👨', 'Male'), ('other', '🧑', 'Other')])
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: GestureDetector(
            onTap: () => setState(() => _gender = g.$1),
            child: AnimatedContainer(duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _gender == g.$1 ? AppColors.sage.withOpacity(0.15) : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _gender == g.$1 ? AppColors.sage : Colors.transparent, width: 2),
              ),
              child: Column(children: [
                Text(g.$2, style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 4),
                Text(g.$3, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _gender == g.$1 ? AppColors.sage : (isDark ? AppColors.textMutedDark : AppColors.textMuted))),
              ]),
            ),
          ))),
      ]),
    ]),
  );

  Widget _buildStep2(bool isDark) => _StepWrapper(
    emoji: '📏', title: 'Your body info', subtitle: 'Helps us calculate BMI, calories, and personalise your plan.',
    isDark: isDark,
    child: Column(children: [
      Row(children: [
        Expanded(child: TextField(controller: _ageCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Age', hintText: '35', suffixText: 'years'))),
        const SizedBox(width: 12),
        Expanded(child: TextField(controller: _heightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Height', hintText: '165', suffixText: 'cm'))),
      ]),
      const SizedBox(height: 12),
      TextField(controller: _weightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Current weight', hintText: '70', suffixText: 'kg')),
      const SizedBox(height: 20),
      Text('Activity level', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
      const SizedBox(height: 10),
      for (final a in [('sedentary','🪑','Sedentary — mostly sitting'),('light','🚶','Light — walk occasionally'),('moderate','🏃','Moderate — exercise 3x/week'),('active','🏋️','Active — exercise daily')])
        GestureDetector(
          onTap: () => setState(() => _activity = a.$1),
          child: AnimatedContainer(duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _activity == a.$1 ? AppColors.sage.withOpacity(0.1) : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _activity == a.$1 ? AppColors.sage : Colors.transparent, width: 2),
            ),
            child: Row(children: [
              Text(a.$2, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Text(a.$3, style: TextStyle(fontSize: 13, fontWeight: _activity == a.$1 ? FontWeight.w700 : FontWeight.normal, color: _activity == a.$1 ? AppColors.sage : (isDark ? AppColors.textOnDark : AppColors.textPrimary))),
            ]),
          ),
        ),
    ]),
  );

  Widget _buildStep3(bool isDark) => _StepWrapper(
    emoji: '🏥', title: 'Your health conditions', subtitle: 'Select all that apply. We\'ll customise your plan accordingly.',
    isDark: isDark,
    child: Wrap(spacing: 8, runSpacing: 8, children: _allConditions.map((c) {
      final sel = _selectedConditions.contains(c);
      return GestureDetector(
        onTap: () => setState(() => sel ? _selectedConditions.remove(c) : _selectedConditions.add(c)),
        child: AnimatedContainer(duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: sel ? AppColors.violet.withOpacity(0.15) : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: sel ? AppColors.violet : Colors.transparent, width: 2),
          ),
          child: Text(c, style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.normal, color: sel ? AppColors.violet : (isDark ? AppColors.textMutedDark : AppColors.textMuted))),
        ),
      );
    }).toList()),
  );

  Widget _buildStep4(bool isDark) => _StepWrapper(
    emoji: '🎯', title: 'Set your goals', subtitle: 'These help us track your progress and send the right reminders.',
    isDark: isDark,
    child: Column(children: [
      TextField(controller: _targetWeightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Target weight (optional)', hintText: '65', suffixText: 'kg')),
      const SizedBox(height: 12),
      TextField(controller: _targetStepsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Daily steps goal', hintText: '8000', suffixText: 'steps')),
      const SizedBox(height: 12),
      TextField(controller: _targetWaterCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Daily water goal', hintText: '2.5', suffixText: 'litres')),
    ]),
  );

  Widget _buildStep5(bool isDark) => _StepWrapper(
    emoji: '🔒', title: 'Secure your data', subtitle: 'Your health data is private. Add an extra layer of protection.',
    isDark: isDark,
    child: Column(children: [
      _SecurityOption(
        icon: '🔢', title: 'PIN lock', subtitle: 'Set a 6-digit PIN to lock the app',
        value: _setupPin, isDark: isDark,
        onChanged: (v) => setState(() => _setupPin = v),
      ),
      const SizedBox(height: 12),
      _SecurityOption(
        icon: '👆', title: 'Fingerprint / Face ID',
        subtitle: _biometricAvail ? 'Use biometric to unlock' : 'Not available on this device',
        value: _setupBiometric, isDark: isDark,
        enabled: _biometricAvail,
        onChanged: _biometricAvail ? (v) => setState(() => _setupBiometric = v) : null,
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.info.withOpacity(isDark ? 0.1 : 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.info.withOpacity(0.2))),
        child: Row(children: [
          const Text('💡', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Text('You can always change security settings later in Profile → Security', style: TextStyle(fontSize: 12, color: isDark ? AppColors.textMutedDark : AppColors.textMuted, height: 1.4))),
        ]),
      ),
    ]),
  );
}

class _StepWrapper extends StatelessWidget {
  final String emoji, title, subtitle;
  final Widget child;
  final bool isDark;
  const _StepWrapper({required this.emoji, required this.title, required this.subtitle, required this.child, required this.isDark});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(emoji, style: const TextStyle(fontSize: 48)),
      const SizedBox(height: 16),
      Text(title, style: TextStyle(fontFamily: 'Fraunces', fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
      const SizedBox(height: 8),
      Text(subtitle, style: TextStyle(fontSize: 14, color: isDark ? AppColors.textMutedDark : AppColors.textMuted, height: 1.5)),
      const SizedBox(height: 28),
      child,
    ]),
  );
}

class _SecurityOption extends StatelessWidget {
  final String icon, title, subtitle;
  final bool value, isDark;
  final bool enabled;
  final ValueChanged<bool>? onChanged;
  const _SecurityOption({required this.icon, required this.title, required this.subtitle, required this.value, required this.isDark, this.enabled = true, this.onChanged});
  @override
  Widget build(BuildContext context) => Opacity(opacity: enabled ? 1 : 0.45, child: Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isDark ? AppColors.cardDark : Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: value ? AppColors.sage : (isDark ? const Color(0xFF1E3250) : Colors.grey.shade200), width: value ? 2 : 1),
    ),
    child: Row(children: [
      Text(icon, style: const TextStyle(fontSize: 24)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
        Text(subtitle, style: TextStyle(fontSize: 12, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
      ])),
      Switch(value: value, onChanged: onChanged, activeColor: AppColors.sage),
    ]),
  ));
}