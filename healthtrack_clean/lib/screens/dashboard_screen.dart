// ============================================================
// lib/screens/dashboard_screen.dart — Main Dashboard
// Shows BP, weight, water, steps, sleep, meals, alerts, insights
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/common_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() => _loading = true);
    final resp = await _api.getDashboard();
    if (resp.success) {
      setState(() {
        _data = resp.data;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: _loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _loadDashboard,
              color: AppColors.sage,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(auth),
                    const SizedBox(height: 16),
                    if (_data?['alert_count'] != null && _data!['alert_count'] > 0)
                      _buildAlerts(),
                    const SizedBox(height: 16),
                    _buildStatsGrid(),
                    const SizedBox(height: 16),
                    _buildQuickActions(),
                    const SizedBox(height: 16),
                    if (_data?['insights'] != null) _buildInsights(),
                    const SizedBox(height: 16),
                    if (_data?['meals'] != null) _buildMealsCard(),
                    const SizedBox(height: 16),
                    if (_data?['medicines'] != null) _buildMedicinesCard(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────
  Widget _buildHeader(AuthService auth) {
    final greeting = _data?['greeting'] ?? 'Welcome';
    final dayName = _data?['day_name'] ?? '';
    final score = _data?['health_score'];

    return GradientHeader(
      title: greeting,
      subtitle: dayName,
      emoji: '💚',
      trailing: score != null
          ? ProgressRing(
              percent: (score['total_score'] ?? 0) / 100,
              centerText: '${score['total_score']?.toInt() ?? 0}',
              label: score['grade'] ?? '',
              color: AppColors.mint,
              radius: 32,
            )
          : null,
    );
  }

  // ── ALERTS BANNER ─────────────────────────────────────────────
  Widget _buildAlerts() {
    final alerts = _data!['alerts'] as List;
    if (alerts.isEmpty) return const SizedBox.shrink();

    final first = alerts.first;
    final isEmergency = first['alert_type'] == 'emergency';

    final bgColor = isEmergency
        ? const Color(0xFFFDECEC)
        : const Color(0xFFFFF4D6);

    final borderColor = isEmergency
        ? const Color(0xFFE58A8A)
        : const Color(0xFFE8C15A);

    final titleColor = isEmergency
        ? const Color(0xFF8B1E1E)
        : const Color(0xFF7A4B00);

    const messageColor = Color(0xFF2F2F2F);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            isEmergency ? '🚨' : '⚠️',
            style: const TextStyle(fontSize: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  first['title'] ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  first['message'] ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: messageColor,
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── STATS GRID (BP, Weight, Water, Steps) ──────────────────────
  Widget _buildStatsGrid() {
    final bp = _data?['bp'];
    final weight = _data?['weight'];
    final water = _data?['water'];
    final steps = _data?['steps'];

    final bpLatest = bp?['latest'];
    final bpStr = bpLatest != null
        ? '${bpLatest['value_1']?.toInt()}/${bpLatest['value_2']?.toInt()}'
        : '—';
    final bpStatus = bp?['status'] ?? 'No Reading';

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        StatCard(
          label: 'Blood Pressure',
          value: bpStr,
          sublabel: bpStatus,
          emoji: '❤️',
          color: AppTheme.bpStatusColor(bpStatus),
          onTap: () => Navigator.pushNamed(context, '/bp').then((_) => _loadDashboard()),
        ),
        StatCard(
          label: 'Weight',
          value: weight?['latest'] != null
              ? '${weight['latest']['value_1']} kg'
              : '—',
          sublabel: weight?['bmi_status'] ?? '',
          emoji: '⚖️',
          color: AppColors.violet,
          onTap: () => Navigator.pushNamed(context, '/weight').then((_) => _loadDashboard()),
        ),
        StatCard(
          label: 'Water',
          value: '${water?['today_total'] ?? 0}L',
          sublabel: '${water?['pct'] ?? 0}% of ${water?['target'] ?? 2.5}L',
          emoji: '💧',
          color: AppColors.water,
          onTap: () => Navigator.pushNamed(context, '/water').then((_) => _loadDashboard()),
        ),
        StatCard(
          label: 'Steps',
          value: '${steps?['count'] ?? 0}',
          sublabel: '${steps?['pct'] ?? 0}% of ${steps?['target'] ?? 8000}',
          emoji: '👟',
          color: AppColors.info,
          onTap: () => Navigator.pushNamed(context, '/exercise').then((_) => _loadDashboard()),
        ),
      ],
    );
  }

  // ── QUICK ACTIONS ─────────────────────────────────────────────
  Widget _buildQuickActions() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          QuickActionButton(
            emoji: '❤️',
            label: 'Log BP',
            color: AppColors.danger,
            onTap: () => Navigator.pushNamed(context, '/bp').then((_) => _loadDashboard()),
          ),
          const SizedBox(width: 10),
          QuickActionButton(
            emoji: '💧',
            label: 'Water',
            color: AppColors.water,
            onTap: () => Navigator.pushNamed(context, '/water').then((_) => _loadDashboard()),
          ),
          const SizedBox(width: 10),
          QuickActionButton(
            emoji: '⚖️',
            label: 'Weight',
            color: AppColors.violet,
            onTap: () => Navigator.pushNamed(context, '/weight').then((_) => _loadDashboard()),
          ),
          const SizedBox(width: 10),
          QuickActionButton(
            emoji: '🍽️',
            label: 'Meals',
            color: AppColors.danger,
            onTap: () => Navigator.pushNamed(context, '/meals').then((_) => _loadDashboard()),
          ),
          const SizedBox(width: 10),
          QuickActionButton(
            emoji: '😴',
            label: 'Sleep',
            color: AppColors.sleep,
            onTap: () => Navigator.pushNamed(context, '/sleep').then((_) => _loadDashboard()),
          ),
          const SizedBox(width: 10),
          QuickActionButton(
            emoji: '🏃',
            label: 'Exercise',
            color: AppColors.exercise,
            onTap: () => Navigator.pushNamed(context, '/exercise').then((_) => _loadDashboard()),
          ),
          const SizedBox(width: 10),
          QuickActionButton(
            emoji: '⏰',
            label: 'Reminders',
            color: AppColors.gold,
            onTap: () => Navigator.pushNamed(context, '/reminders'),
          ),
        ],
      ),
    );
  }

  // ── INSIGHTS ──────────────────────────────────────────────────
  Widget _buildInsights() {
    final insights = _data!['insights'] as List;
    if (insights.isEmpty) return const SizedBox.shrink();

    return SectionCard(
      title: '💡 Insights',
      child: Column(
        children: insights.map<Widget>((i) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i['icon'] ?? '📊',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    i['text'] ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1F2937),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── MEALS ─────────────────────────────────────────────────────
  Widget _buildMealsCard() {
    final meals = _data!['meals'];
    final items = meals['items'] as List;

    return SectionCard(
      title: "🍱 Today's Meals",
      trailing: PillChip(
        text: '${meals['done']}/${meals['total']}',
        color: AppColors.sage,
      ),
      child: items.isEmpty
          ? const Text(
              'No meal plan yet. Generate one from the Meals tab.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            )
          : Column(
              children: items.map<Widget>((m) {
                final recipe = m['recipe'];
                final done = m['completed'] == true;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        done ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: done ? AppColors.success : const Color(0xFF9CA3AF),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '',
                              style: TextStyle(fontSize: 0),
                            ),
                            Text(
                              m['meal_slot'] ?? '',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              recipe['name'] ?? '',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1F2937),
                                decoration: done ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${recipe['calories']} kcal',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  // ── MEDICINES ─────────────────────────────────────────────────
  Widget _buildMedicinesCard() {
    final meds = _data!['medicines'];
    final list = meds['list'] as List;
    if (list.isEmpty) return const SizedBox.shrink();

    return SectionCard(
      title: '💊 Medicines',
      trailing: PillChip(
        text: '${meds['taken']}/${meds['total']}',
        color: AppColors.medicine,
      ),
      child: Column(
        children: list.map<Widget>((m) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  m['taken'] == true
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: m['taken'] == true
                      ? AppColors.success
                      : const Color(0xFF9CA3AF),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m['name'] ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      Text(
                        '${m['dosage'] ?? ''} · ${m['timing'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}