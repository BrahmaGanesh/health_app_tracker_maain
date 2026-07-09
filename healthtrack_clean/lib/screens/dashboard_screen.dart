// lib/screens/dashboard_screen.dart — Advanced Dashboard UI + Dark Mode
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../main.dart' show ThemeService;
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/step_tracking_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  Map<String, dynamic>? _data;
  bool _loading = true;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() { _animCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getDashboard();
    if (resp.success) {
      setState(() { _data = resp.data; _loading = false; });
      _animCtrl.forward(from: 0);
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth   = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _loading
          ? const LoadingView()
          : FadeTransition(
              opacity: _fadeAnim,
              child: RefreshIndicator(
                onRefresh: _load,
                color: AppColors.sage,
                displacement: 80,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    _buildSliverAppBar(auth, isDark),
                    SliverToBoxAdapter(child: _buildBody(isDark)),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SLIVER APP BAR (collapsible header)
  // ══════════════════════════════════════════════════════════════
  Widget _buildSliverAppBar(AuthService auth, bool isDark) {
    final score = _data?['health_score'];
    final name  = auth.userName.split(' ').first;
    final hour  = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good Morning' : hour < 17 ? 'Good Afternoon' : 'Good Evening';

    return SliverAppBar(
      expandedHeight: 180,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: isDark ? AppColors.cardDark : AppColors.navy,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.navy, Color(0xFF1E3F6E), AppColors.violet],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(children: [
            // Background pattern
            Positioned(right: -20, bottom: -20,
              child: Opacity(opacity: 0.07,
                child: Text('💚', style: TextStyle(fontSize: 150)))),
            Positioned(right: 60, top: 20,
              child: Opacity(opacity: 0.05,
                child: Text('❤️', style: TextStyle(fontSize: 80)))),
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('$greeting, 👋', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(name, style: const TextStyle(fontFamily: 'Fraunces', fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(_data?['day_name'] ?? '', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
                ])),
                if (score != null) _buildScoreRing(score),
              ]),
            ),
          ]),
        ),
      ),
      actions: [
        // Dark mode toggle
        Consumer<ThemeService>(
          builder: (_, theme, __) => IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                theme.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                key: ValueKey(theme.isDark),
                color: Colors.white,
              ),
            ),
            onPressed: theme.toggle,
            tooltip: 'Toggle theme',
          ),
        ),
        IconButton(
          icon: const Icon(Icons.notifications_rounded, color: Colors.white),
          onPressed: () => Navigator.pushNamed(context, '/reminders'),
        ),
      ],
    );
  }

  Widget _buildScoreRing(Map<String, dynamic> score) {
    final val = (score['total_score'] ?? 0).toDouble();
    return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      ProgressRing(percent: val / 100, centerText: '${val.toInt()}', label: score['grade'] ?? '', color: AppColors.mint, radius: 36),
      const SizedBox(height: 4),
      const Text('Health Score', style: TextStyle(fontSize: 10, color: Colors.white60, fontWeight: FontWeight.w600)),
    ]);
  }

  // ══════════════════════════════════════════════════════════════
  // BODY
  // ══════════════════════════════════════════════════════════════
  Widget _buildBody(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Alert banner
        if (_data?['alert_count'] != null && _data!['alert_count'] > 0) ...[
          _buildAlertBanner(isDark),
          const SizedBox(height: 14),
        ],

        // Stats grid (2x3)
        _buildStatsGrid(isDark),
        const SizedBox(height: 20),

        // Quick actions
        _buildSectionTitle('⚡ Quick Actions', isDark),
        const SizedBox(height: 10),
        _buildQuickActions(),
        const SizedBox(height: 20),

        // Insights
        if (_data?['insights'] != null && (_data!['insights'] as List).isNotEmpty) ...[
          _buildSectionTitle('💡 Today\'s Insights', isDark),
          const SizedBox(height: 10),
          _buildInsights(isDark),
          const SizedBox(height: 20),
        ],

        // Meals
        if (_data?['meals'] != null) ...[
          _buildSectionTitle("🍱 Today's Meals", isDark),
          const SizedBox(height: 10),
          _buildMealsCard(isDark),
          const SizedBox(height: 20),
        ],

        // Medicines
        if (_data?['medicines'] != null && (_data!['medicines']['list'] as List).isNotEmpty) ...[
          _buildSectionTitle('💊 Medicines', isDark),
          const SizedBox(height: 10),
          _buildMedicinesCard(isDark),
          const SizedBox(height: 20),
        ],

        const SizedBox(height: 60),
      ]),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(title, style: TextStyle(
      fontFamily: 'Fraunces', fontSize: 17, fontWeight: FontWeight.bold,
      color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
    ));
  }

  // ══════════════════════════════════════════════════════════════
  // ALERT BANNER
  // ══════════════════════════════════════════════════════════════
  Widget _buildAlertBanner(bool isDark) {
    final alerts = (_data!['alerts'] as List?) ?? [];
    if (alerts.isEmpty) return const SizedBox.shrink();
    final first = alerts.first;
    final isEmergency = first['alert_type'] == 'emergency';
    final color = isEmergency ? AppColors.danger : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
            child: Center(child: Text(isEmergency ? '🚨' : '⚠️', style: const TextStyle(fontSize: 20)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(first['title'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
          const SizedBox(height: 3),
          Text(first['message'] ?? '', style: TextStyle(fontSize: 12, color: isDark ? AppColors.textMutedDark : AppColors.textMuted, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // STATS GRID — 2 cols x 3 rows (BP, Weight, Water, Steps, Sugar, Sleep)
  // ══════════════════════════════════════════════════════════════
  Widget _buildStatsGrid(bool isDark) {
    final bp     = _data?['bp'];
    final weight = _data?['weight'];
    final water  = _data?['water'];
    final steps  = _data?['steps'];
    final sleep  = _data?['sleep'];
    final sugar  = _data?['sugar'];

    final bpLatest = bp?['latest'];
    final bpStr    = bpLatest != null ? '${bpLatest['value_1']?.toInt()}/${bpLatest['value_2']?.toInt()}' : '—';
    final bpStatus = bp?['status'] ?? 'No Reading';

    // Live steps from sensor
    final stepSvc = context.watch<StepTrackingService>();
    final liveSteps = stepSvc.todaySteps;
    final stepGoal  = stepSvc.dailyGoal;
    final stepPct   = ((liveSteps / stepGoal) * 100).clamp(0, 100).toInt();

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: [
        _StatTile(
          emoji: '❤️', label: 'Blood Pressure',
          value: bpStr, sub: bpStatus,
          color: AppTheme.bpStatusColor(bpStatus),
          isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/bp').then((_) => _load()),
        ),
        _StatTile(
          emoji: '⚖️', label: 'Weight',
          value: weight?['latest'] != null ? '${weight!['latest']['value_1']} kg' : '—',
          sub: weight?['bmi_status'] ?? 'No data',
          color: AppColors.violet, isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/weight').then((_) => _load()),
        ),
        _StatTile(
          emoji: '💧', label: 'Water',
          value: '${water?['today_total'] ?? 0}L',
          sub: '${water?['pct'] ?? 0}% of ${water?['target'] ?? 2.5}L',
          color: AppColors.water, isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/water').then((_) => _load()),
        ),
        _StatTile(
          emoji: '👟', label: stepSvc.isTracking ? 'Steps 🔴' : 'Steps',
          value: '$liveSteps',
          sub: '$stepPct% of $stepGoal · ${stepSvc.estimatedDistanceKm}km',
          color: stepSvc.goalAchieved ? AppColors.success : AppColors.info,
          isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/exercise'),
        ),
        _StatTile(
          emoji: '🩺', label: 'Blood Sugar',
          value: sugar?['latest']?['value_1'] != null ? '${(sugar!['latest']['value_1'] as num).toInt()} mg' : '—',
          sub: sugar?['status'] ?? 'No reading',
          color: AppColors.sugar, isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/sugar').then((_) => _load()),
        ),
        _StatTile(
          emoji: '😴', label: 'Sleep',
          value: sleep?['last_night'] != null ? '${sleep!['last_night']['duration_hours']}h' : '—',
          sub: sleep?['quality_label'] ?? 'No data',
          color: AppColors.sleep, isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/sleep').then((_) => _load()),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // QUICK ACTIONS ROW
  // ══════════════════════════════════════════════════════════════
  Widget _buildQuickActions() {
    final actions = [
      ('❤️', 'BP',          AppColors.danger,    '/bp'),
      ('💧', 'Water',        AppColors.water,     '/water'),
      ('⚖️', 'Weight',       AppColors.violet,    '/weight'),
      ('😴', 'Sleep',        AppColors.sleep,     '/sleep'),
      ('🩺', 'Sugar',        AppColors.sugar,     '/sugar'),
      ('💊', 'Medicines',    AppColors.medicine,  '/medicines'),
      ('🧪', 'Lab Tests',    AppColors.warning,   '/lab-tests'),
      ('📅', 'Appointments', AppColors.info,      '/appointments'),
      ('🏃', 'Exercise',     AppColors.exercise,  '/exercise'),
      ('🤖', 'AI Assist',    AppColors.sage,      '/ai'),
      ('📋', 'Timeline',     AppColors.navy,      '/timeline'),
      ('🚨', 'Emergency',    AppColors.danger,    '/emergency'),
      ('⏰', 'Reminders',    AppColors.gold,      '/reminders'),
      ('📊', 'Reports',      AppColors.sage,      '/reports'),
      ('💎', 'Plans',        AppColors.violet,    '/plans'),
    ];
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final a = actions[i];
          return _QuickAction(emoji: a.$1, label: a.$2, color: a.$3,
              onTap: () => Navigator.pushNamed(context, a.$4).then((_) => _load()));
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // INSIGHTS
  // ══════════════════════════════════════════════════════════════
  Widget _buildInsights(bool isDark) {
    final insights = (_data!['insights'] as List?) ?? [];
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200),
      ),
      child: Column(
        children: insights.asMap().entries.map((e) {
          final i = e.key; final ins = e.value;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(
                color: i < insights.length - 1 ? (isDark ? const Color(0xFF1E3250) : Colors.grey.shade100) : Colors.transparent))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ins['icon'] ?? '💡', style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 12),
              Expanded(child: Text(ins['text'] ?? '',
                  style: TextStyle(fontSize: 13, height: 1.5, color: isDark ? AppColors.textOnDark : AppColors.textPrimary))),
            ]),
          );
        }).toList(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // MEALS CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildMealsCard(bool isDark) {
    final meals = _data!['meals'];
    final items = meals['items'] as List;
    final done  = meals['done'] ?? 0;
    final total = meals['total'] ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200),
      ),
      child: Column(children: [
        // Progress header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            Expanded(child: Row(children: [
              Text('$done/$total meals done', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
            ])),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/meals'),
              child: Text('View all →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.sage)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: total > 0 ? done / total : 0,
              minHeight: 6,
              backgroundColor: AppColors.sage.withOpacity(0.15),
              color: AppColors.sage,
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No meal plan yet.', style: TextStyle(fontSize: 13, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
          )
        else
          ...items.map((m) {
            final recipe = m['recipe'];
            final isDone = m['completed'] == true;
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: isDone ? AppColors.success.withOpacity(0.12) : AppColors.sage.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Icon(isDone ? Icons.check_rounded : Icons.restaurant_rounded,
                    size: 16, color: isDone ? AppColors.success : AppColors.sage)),
              ),
              title: Text(recipe['name'] ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  decoration: isDone ? TextDecoration.lineThrough : null)),
              subtitle: Text(m['meal_slot'] ?? '', style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
              trailing: Text('${recipe['calories']} kcal', style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
            );
          }),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // MEDICINES CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildMedicinesCard(bool isDark) {
    final meds = _data!['medicines'];
    final list = (meds['list'] as List?) ?? [];
    if (list.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(children: [
            Text('${meds['taken']}/${meds['total']} taken', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
          ]),
        ),
        ...list.map((m) => ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: m['taken'] == true ? AppColors.success.withOpacity(0.12) : AppColors.medicine.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Text(m['taken'] == true ? '✅' : '💊', style: const TextStyle(fontSize: 14))),
          ),
          title: Text(m['name'] ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
          subtitle: Text('${m['dosage'] ?? ''} · ${m['timing'] ?? ''}', style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
        )),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// STAT TILE WIDGET
// ════════════════════════════════════════════════════════════════
class _StatTile extends StatelessWidget {
  final String emoji, label, value, sub;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  const _StatTile({required this.emoji, required this.label, required this.value,
      required this.sub, required this.color, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200),
          boxShadow: [BoxShadow(color: color.withOpacity(isDark ? 0.12 : 0.08), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                letterSpacing: 0.5, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            Icon(Icons.arrow_forward_ios_rounded, size: 10, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
          ]),
          Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 24, fontWeight: FontWeight.w700, color: color, height: 1.1)),
          Text(sub, style: TextStyle(fontSize: 10, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// QUICK ACTION PILL
// ════════════════════════════════════════════════════════════════
class _QuickAction extends StatelessWidget {
  final String emoji, label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({required this.emoji, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(isDark ? 0.18 : 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(isDark ? 0.3 : 0.2)),
          ),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
        ),
        const SizedBox(height: 5),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textMutedDark : AppColors.textMuted)),
      ]),
    );
  }
}