// lib/screens/subscription_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../constants/app_theme.dart';
import '../services/api_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final ApiService _api = ApiService();
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  String _currentPlan = 'free';
  String? _expiresAt;
  bool _autoRenew = true;
  bool _loading = true;
  bool _purchasing = false;
  String? _selectedPlan;
  bool _iapAvailable = false;
  bool _showYearly = false;

  static const String _premiumMonthly = 'healthtrack_premium_monthly';
  static const String _familyMonthly = 'healthtrack_family_monthly';
  static const String _premiumYearly = 'healthtrack_premium_yearly';
  static const String _familyYearly = 'healthtrack_family_yearly';

  Map<String, ProductDetails> _products = <String, ProductDetails>{};

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    _purchaseSubscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _purchaseSubscription?.cancel(),
      onError: (_) {
        if (mounted) {
          setState(() => _purchasing = false);
        }
      },
    );

    await _load();
    await _initIAP();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    final resp = await _api.getSubscriptionStatus();
    if (resp.success && mounted) {
      setState(() {
        _currentPlan = resp.data['plan'] ?? 'free';
        _expiresAt = resp.data['expires_at'];
        _autoRenew = resp.data['auto_renew'] ?? true;
        _selectedPlan = _currentPlan;
      });
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _initIAP() async {
    final available = await _iap.isAvailable();
    if (!mounted) return;

    setState(() => _iapAvailable = available);
    if (!available) return;

    const ids = <String>{
      _premiumMonthly,
      _familyMonthly,
      _premiumYearly,
      _familyYearly,
    };

    final response = await _iap.queryProductDetails(ids);

    if (!mounted) return;

    setState(() {
      _products = {
        for (final p in response.productDetails) p.id: p,
      };
    });
  }

  Future<void> _purchase(String productId) async {
    if (_purchasing) return;

    if (!_iapAvailable) {
      _showMsg(
        'Google Play Billing is not available on this device.',
        isError: true,
      );
      return;
    }

    final product = _products[productId];
    if (product == null) {
      _showMsg('Product not found. Please try again later.', isError: true);
      return;
    }

    if (mounted) {
      setState(() => _purchasing = true);
    }

    try {
      final param = PurchaseParam(productDetails: product);
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      if (mounted) {
        setState(() => _purchasing = false);
      }
      _showMsg('Purchase failed: $e', isError: true);
    }
  }

  Future<void> _restorePurchases() async {
    try {
      await _iap.restorePurchases();
      _showMsg('Restore request sent. Please wait...');
    } catch (e) {
      _showMsg('Restore failed: $e', isError: true);
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.pending) {
        if (mounted) {
          setState(() => _purchasing = true);
        }
        continue;
      }

      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        final resp = await _api.verifyPurchase(
          p.purchaseID ?? '',
          p.productID,
        );

        if (resp.success) {
          if (p.pendingCompletePurchase) {
            await _iap.completePurchase(p);
          }

          await _load();

          if (mounted) {
            _showMsg(
              '🎉 Welcome to ${resp.data['plan']?.toString().toUpperCase() ?? 'PREMIUM'}!',
            );
          }
        } else {
          if (mounted) {
            _showMsg(
              resp.message.isNotEmpty
                  ? resp.message
                  : 'Purchase verification failed.',
              isError: true,
            );
          }
        }
      } else if (p.status == PurchaseStatus.error) {
        if (mounted) {
          _showMsg(
            'Purchase error: ${p.error?.message ?? 'Unknown'}',
            isError: true,
          );
        }
      } else if (p.status == PurchaseStatus.canceled) {
        if (mounted) {
          _showMsg('Purchase cancelled.', isError: true);
        }
      }

      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }

    if (mounted) {
      setState(() => _purchasing = false);
    }
  }

  void _showMsg(String msg, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _price(String productId) {
    final product = _products[productId];
    if (product != null) return product.price;

    if (productId.contains('premium') && productId.contains('yearly')) {
      return '₹1,999/yr';
    }
    if (productId.contains('premium')) {
      return '₹199/mo';
    }
    if (productId.contains('family') && productId.contains('yearly')) {
      return '₹3,499/yr';
    }
    if (productId.contains('family')) {
      return '₹349/mo';
    }
    return '';
  }

  String _selectedProductId() {
    if (_selectedPlan == 'premium') {
      return _showYearly ? _premiumYearly : _premiumMonthly;
    }
    return _showYearly ? _familyYearly : _familyMonthly;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;

    if (_loading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('Plans')),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.sage),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Plans & Pricing',
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Restore purchases',
            onPressed: _restorePurchases,
            icon: const Icon(Icons.restore_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CurrentPlanBanner(
              plan: _currentPlan,
              expiresAt: _expiresAt,
              autoRenew: _autoRenew,
              isDark: isDark,
              card: card,
              brd: brd,
              tp: tp,
              tm: tm,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showYearly = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_showYearly ? card : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                          border: !_showYearly ? Border.all(color: brd) : null,
                        ),
                        child: Center(
                          child: Text(
                            'Monthly',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: !_showYearly ? AppColors.sage : tm,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showYearly = true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _showYearly ? card : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                          border: _showYearly ? Border.all(color: brd) : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Yearly',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _showYearly ? AppColors.sage : tm,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: const Text(
                                'Save 17%',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _PlanCard(
              name: 'Free',
              icon: '🆓',
              price: '₹0',
              period: 'forever',
              color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
              isCurrent: _currentPlan == 'free',
              isSelected: _selectedPlan == 'free',
              isDark: isDark,
              card: card,
              brd: brd,
              tp: tp,
              tm: tm,
              features: const [
                'Basic health trackers (BP, weight, water, sleep)',
                '2 medicines, 3 documents, 2 appointments',
                'Health score + emergency card',
                'Health timeline (read-only)',
              ],
              locked: const [
                'AI features',
                'Lab test tracking',
                'Family health',
                'Unlimited appointments',
              ],
              onTap: () => setState(() => _selectedPlan = 'free'),
            ),
            const SizedBox(height: 12),
            _PlanCard(
              name: 'Premium',
              icon: '⭐',
              badge: 'POPULAR',
              price: _price(_showYearly ? _premiumYearly : _premiumMonthly),
              period: _showYearly ? '/year' : '/month',
              color: AppColors.sage,
              isCurrent: _currentPlan == 'premium',
              isSelected: _selectedPlan == 'premium',
              isDark: isDark,
              card: card,
              brd: brd,
              tp: tp,
              tm: tm,
              features: const [
                'Everything in Free',
                '10 medicines + smart escalating reminders',
                '10 documents (all categories)',
                'Unlimited lab tests + AI insights',
                'Unlimited appointments',
                'AI wellness chat + food/medicine camera',
                'Exercise library + recipes with TTS',
                'PDF health reports via email',
              ],
              locked: const [
                'Family health tracking',
                'Family caregiver alerts',
              ],
              onTap: () => setState(() => _selectedPlan = 'premium'),
            ),
            const SizedBox(height: 12),
            _PlanCard(
              name: 'Family',
              icon: '👨‍👩‍👧',
              badge: 'BEST VALUE',
              price: _price(_showYearly ? _familyYearly : _familyMonthly),
              period: _showYearly ? '/year' : '/month',
              color: AppColors.violet,
              isCurrent: _currentPlan == 'family',
              isSelected: _selectedPlan == 'family',
              isDark: isDark,
              card: card,
              brd: brd,
              tp: tp,
              tm: tm,
              features: const [
                'Everything in Premium',
                'Up to 2 family members (admin can increase)',
                'Family BP, sugar, weight tracking',
                'Family medicines + AI verification',
                'Family documents (20 total)',
                'Family appointments + auto reminders',
                'Caregiver alerts (3-day missed medicine)',
                'Family health timeline (colour-coded)',
                'Combined family health reports',
              ],
              locked: const [],
              onTap: () => setState(() => _selectedPlan = 'family'),
            ),
            const SizedBox(height: 20),
            if (_selectedPlan != null && _selectedPlan != _currentPlan)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _purchasing
                      ? null
                      : () {
                          if (_selectedPlan == 'free') return;
                          _purchase(_selectedProductId());
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedPlan == 'premium'
                        ? AppColors.sage
                        : AppColors.violet,
                    foregroundColor: _selectedPlan == 'premium'
                        ? AppColors.navy
                        : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _purchasing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(
                          'Upgrade to ${_selectedPlan![0].toUpperCase()}${_selectedPlan!.substring(1)} — ${_price(_selectedProductId())}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            if (_selectedPlan != null && _selectedPlan != _currentPlan)
              const SizedBox(height: 10),
            Center(
              child: Text(
                'Payments via Google Play Billing · Cancel anytime · Renews automatically',
                style: TextStyle(fontSize: 11, color: tm, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            if (!_iapAvailable)
              Center(
                child: Text(
                  'Google Play Billing is currently unavailable on this device.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.warning,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 24),
            _FeatureTable(
              isDark: isDark,
              card: card,
              brd: brd,
              tp: tp,
              tm: tm,
            ),
            const SizedBox(height: 20),
            _Faq(
              isDark: isDark,
              tp: tp,
              tm: tm,
              card: card,
              brd: brd,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _CurrentPlanBanner extends StatelessWidget {
  final String plan;
  final String? expiresAt;
  final bool autoRenew;
  final bool isDark;
  final Color card;
  final Color brd;
  final Color tp;
  final Color tm;

  const _CurrentPlanBanner({
    required this.plan,
    this.expiresAt,
    required this.autoRenew,
    required this.isDark,
    required this.card,
    required this.brd,
    required this.tp,
    required this.tm,
  });

  @override
  Widget build(BuildContext context) {
    final isFree = plan == 'free';
    final color = plan == 'family'
        ? AppColors.violet
        : plan == 'premium'
            ? AppColors.sage
            : (isDark ? AppColors.textMutedDark : AppColors.textMuted);
    final icon = plan == 'family'
        ? '👨‍👩‍👧'
        : plan == 'premium'
            ? '⭐'
            : '🆓';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current: ${plan[0].toUpperCase()}${plan.substring(1)} Plan',
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                if (expiresAt != null)
                  Text(
                    'Expires: $expiresAt',
                    style: TextStyle(fontSize: 12, color: tm),
                  ),
                if (!isFree)
                  Text(
                    autoRenew ? 'Auto-renews' : 'Will not renew',
                    style: TextStyle(
                      fontSize: 12,
                      color: autoRenew
                          ? AppColors.success
                          : AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (isFree)
                  Text(
                    'Upgrade for advanced health tracking',
                    style: TextStyle(fontSize: 12, color: tm),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(100),
            ),
            child: const Text(
              'Active',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String name;
  final String icon;
  final String price;
  final String period;
  final String? badge;
  final Color color;
  final bool isCurrent;
  final bool isSelected;
  final bool isDark;
  final Color card;
  final Color brd;
  final Color tp;
  final Color tm;
  final List<String> features;
  final List<String> locked;
  final VoidCallback onTap;

  const _PlanCard({
    required this.name,
    required this.icon,
    required this.price,
    required this.period,
    this.badge,
    required this.color,
    required this.isCurrent,
    required this.isSelected,
    required this.isDark,
    required this.card,
    required this.brd,
    required this.tp,
    required this.tm,
    required this.features,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : brd,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: tp,
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                badge!,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                          if (isCurrent) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: const Text(
                                'Current',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.success,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            price,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          Text(
                            period,
                            style: TextStyle(fontSize: 12, color: tm),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Radio<bool>(
                  value: true,
                  groupValue: isSelected,
                  onChanged: (_) => onTap(),
                  activeColor: color,
                ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(height: 14),
              Container(height: 1, color: brd),
              const SizedBox(height: 12),
              ...features.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 16, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f,
                          style: TextStyle(fontSize: 12, color: tp, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (locked.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...locked.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          size: 15,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            f,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureTable extends StatelessWidget {
  final bool isDark;
  final Color card;
  final Color brd;
  final Color tp;
  final Color tm;

  const _FeatureTable({
    required this.isDark,
    required this.card,
    required this.brd,
    required this.tp,
    required this.tm,
  });

  static const _rows = [
    ('BP, Sugar, Weight, Sleep, Water', true, true, true),
    ('Live step tracking', true, true, true),
    ('Health score (0-100)', true, true, true),
    ('Emergency medical card', true, true, true),
    ('Health timeline', true, true, true),
    ('History', '7 days', 'Unlimited', 'Unlimited'),
    ('Medicines', '2', '10', '20'),
    ('Documents', '3', '10', '20'),
    ('Active appointments', '2', 'Unlimited', 'Unlimited'),
    ('Lab test tracker', false, true, true),
    ('AI lab insights (Claude)', false, true, true),
    ('Smart escalating reminders', false, true, true),
    ('AI wellness chat', false, true, true),
    ('AI food camera scan', false, true, true),
    ('AI medicine verification', false, true, true),
    ('PDF health reports', false, true, true),
    ('Exercise library + TTS', false, true, true),
    ('Family members', '0', '0', '2+'),
    ('Family BP/Sugar/Weight', false, false, true),
    ('Family medicines', false, false, true),
    ('Family documents', '0', '0', '20'),
    ('Caregiver alerts (email)', false, false, true),
    ('Family timeline (colour-coded)', false, false, true),
  ];

  Widget _cell(dynamic v, Color c) {
    if (v is bool) {
      return Text(
        v ? '✓' : '—',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: v ? AppColors.success : AppColors.textMuted,
        ),
      );
    }

    return Text(
      '$v',
      style: TextStyle(
        fontSize: 11,
        color: c,
        fontWeight: FontWeight.w600,
      ),
      textAlign: TextAlign.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: brd),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'FEATURE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: tm,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    'FREE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: tm,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(
                  width: 64,
                  child: Text(
                    'PREMIUM',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.sage,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(
                  width: 56,
                  child: Text(
                    'FAMILY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.violet,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          ..._rows.map(
            (r) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: brd, width: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      r.$1,
                      style: TextStyle(fontSize: 12, color: tp),
                    ),
                  ),
                  SizedBox(width: 56, child: Center(child: _cell(r.$2, tm))),
                  SizedBox(
                    width: 64,
                    child: Center(child: _cell(r.$3, AppColors.sage)),
                  ),
                  SizedBox(
                    width: 56,
                    child: Center(child: _cell(r.$4, AppColors.violet)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Faq extends StatefulWidget {
  final bool isDark;
  final Color tp;
  final Color tm;
  final Color card;
  final Color brd;

  const _Faq({
    required this.isDark,
    required this.tp,
    required this.tm,
    required this.card,
    required this.brd,
  });

  @override
  State<_Faq> createState() => _FaqState();
}

class _FaqState extends State<_Faq> {
  int? _open;

  static const _items = [
    (
      'Can I cancel anytime?',
      'Yes. You can cancel auto-renewal anytime from Google Play → Subscriptions. You keep access until the end of your billing period.',
    ),
    (
      'What happens to my data if I downgrade?',
      'All your health data is preserved. You just lose access to premium features. Data is never deleted due to a plan change.',
    ),
    (
      'Can I add more than 2 family members?',
      'The default is 2 on Family plan. Your account admin can increase this limit specifically for your account — contact support.',
    ),
    (
      'Is there a free trial?',
      'You can use the Free plan indefinitely with no time limit. Premium features can be tested during any promotional trial periods offered on Google Play.',
    ),
    (
      'Is my health data secure?',
      'Yes. All data is encrypted in transit (HTTPS). The app blocks screenshots and screen recording. Biometric and PIN lock are available. Data is never sold.',
    ),
    (
      'What payment methods are accepted?',
      'All payment methods supported by Google Play — UPI, credit/debit card, net banking, Google Pay, and carrier billing where available.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Frequently asked questions',
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: widget.tp,
          ),
        ),
        const SizedBox(height: 10),
        ...List.generate(
          _items.length,
          (i) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: widget.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: widget.brd),
            ),
            child: InkWell(
              onTap: () => setState(() => _open = _open == i ? null : i),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _items[i].$1,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: widget.tp,
                            ),
                          ),
                        ),
                        Icon(
                          _open == i
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: widget.tm,
                          size: 20,
                        ),
                      ],
                    ),
                    if (_open == i) ...[
                      const SizedBox(height: 8),
                      Text(
                        _items[i].$2,
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.tm,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}