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

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();

  Map<String, dynamic> _data = <String, dynamic>{};
  bool _loading = true;
  bool _hasError = false;
  String _errorText = 'Unable to load dashboard';

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _hasError = false;
    });

    try {
      final resp = await _api.getDashboard();

      if (!mounted) return;

      final bool success = _readBool(resp, 'success');
      final dynamic rawData = _readField(resp, 'data');

      if (success && rawData != null) {
        setState(() {
          _data = _toMap(rawData);
          _loading = false;
          _hasError = false;
        });
        _animCtrl.forward(from: 0);
      } else {
        setState(() {
          _loading = false;
          _hasError = true;
          _errorText = _extractErrorMessage(resp);
          _data = <String, dynamic>{};
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
        _errorText = 'Server error. Please try again.';
        _data = <String, dynamic>{};
      });
    }
  }

  dynamic _readField(dynamic obj, String field) {
    try {
      return obj
          .toJson()[field];
    } catch (_) {
      try {
        return (obj as dynamic).__getattribute__(field);
      } catch (_) {
        try {
          return (obj as dynamic).data;
        } catch (_) {
          return null;
        }
      }
    }
  }

  bool _readBool(dynamic obj, String field) {
    try {
      final value = _readField(obj, field);
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      if (value is num) return value != 0;
      return false;
    } catch (_) {
      return false;
    }
  }

  String _extractErrorMessage(dynamic resp) {
    final candidates = [
      _readField(resp, 'message'),
      _readField(resp, 'error'),
      _readField(resp, 'detail'),
      _readField(resp, 'statusText'),
    ];

    for (final c in candidates) {
      if (c != null && c.toString().trim().isNotEmpty) {
        return c.toString();
      }
    }

    return 'Dashboard API failed (500)';
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  List<dynamic> _list(dynamic value) {
    return value is List ? value : <dynamic>[];
  }

  String _text(dynamic value, {String fallback = '—'}) {
    if (value == null) return fallback;
    final t = value.toString().trim();
    return t.isEmpty ? fallback : t;
  }

  int _int(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  double _double(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }

@override
Widget build(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final auth = context.watch<AuthService>();

  return Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    body: SafeArea(
      bottom: false,
      child: _loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.sage,
              displacement: 80,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _buildSliverAppBar(auth, isDark),
                  SliverToBoxAdapter(
                    child: _hasError
                        ? _buildErrorBody(isDark)
                        : _buildBody(isDark),
                  ),
                ],
              ),
            ),
    ),
  );
}
  Widget _buildSliverAppBar(AuthService auth, bool isDark) {
    final score = _map(_data['health_score']);
    final String rawName = _text(
      _safeUserName(auth),
      fallback: 'User',
    );
    final String name = rawName.split(' ').first;
    final int hour = DateTime.now().hour;
    final String greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';

    return SliverAppBar(
      expandedHeight: 185,
      pinned: true,
      floating: false,
      elevation: 0,
      automaticallyImplyLeading: false,
      backgroundColor: isDark ? AppColors.cardDark : AppColors.navy,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.navy, Color(0xFF1E3F6E), AppColors.violet],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -20,
                child: Opacity(
                  opacity: 0.07,
                  child: const Text(
                    '💚',
                    style: TextStyle(fontSize: 150),
                  ),
                ),
              ),
              Positioned(
                right: 60,
                top: 22,
                child: Opacity(
                  opacity: 0.05,
                  child: const Text(
                    '❤️',
                    style: TextStyle(fontSize: 80),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$greeting, 👋',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.74),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Fraunces',
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _text(_data['day_name'], fallback: ''),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.62),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (score.isNotEmpty) _buildScoreRing(score),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        Consumer<ThemeService>(
          builder: (_, theme, __) => IconButton(
            tooltip: 'Toggle theme',
            onPressed: theme.toggle,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                theme.isDark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                key: ValueKey(theme.isDark),
                color: Colors.white,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.notifications_rounded, color: Colors.white),
          onPressed: () => Navigator.pushNamed(context, '/reminders'),
        ),
      ],
    );
  }

  String _safeUserName(AuthService auth) {
    try {
      final dynamic name = auth.userName;
      if (name == null) return 'User';
      return name.toString();
    } catch (_) {
      return 'User';
    }
  }

  Widget _buildScoreRing(Map<String, dynamic> score) {
    final double val = _double(score['total_score']).clamp(0, 100);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ProgressRing(
          percent: val / 100,
          centerText: '${val.toInt()}',
          label: _text(score['grade'], fallback: ''),
          color: AppColors.mint,
          radius: 36,
        ),
        const SizedBox(height: 4),
        const Text(
          'Health Score',
          style: TextStyle(
            fontSize: 10,
            color: Colors.white60,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBody(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.danger.withOpacity(0.28),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Dashboard unavailable',
                        style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.textOnDark
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _errorText,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isDark
                        ? AppColors.textMutedDark
                        : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.sage,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _buildSectionTitle('⚡ Quick Actions', isDark),
          const SizedBox(height: 10),
          _buildQuickActions(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    final int alertCount = _int(_data['alert_count']);
    final List<dynamic> insights = _list(_data['insights']);
    final Map<String, dynamic> meals = _map(_data['meals']);
    final Map<String, dynamic> medicines = _map(_data['medicines']);
    final List<dynamic> medList = _list(medicines['list']);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alertCount > 0) ...[
            _buildAlertBanner(isDark),
            const SizedBox(height: 14),
          ],
          _buildStatsGrid(isDark),
          const SizedBox(height: 20),
          _buildSectionTitle('⚡ Quick Actions', isDark),
          const SizedBox(height: 10),
          _buildQuickActions(),
          const SizedBox(height: 20),
          if (insights.isNotEmpty) ...[
            _buildSectionTitle('💡 Today\'s Insights', isDark),
            const SizedBox(height: 10),
            _buildInsights(isDark),
            const SizedBox(height: 20),
          ],
          if (meals.isNotEmpty) ...[
            _buildSectionTitle('🍱 Today\'s Meals', isDark),
            const SizedBox(height: 10),
            _buildMealsCard(isDark),
            const SizedBox(height: 20),
          ],
          if (medList.isNotEmpty) ...[
            _buildSectionTitle('💊 Medicines', isDark),
            const SizedBox(height: 10),
            _buildMedicinesCard(isDark),
            const SizedBox(height: 20),
          ],
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: 'Fraunces',
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
      ),
    );
  }

  Widget _buildAlertBanner(bool isDark) {
    final List<dynamic> alerts = _list(_data['alerts']);
    if (alerts.isEmpty) return const SizedBox.shrink();

    final Map<String, dynamic> first = _map(alerts.first);
    final bool isEmergency = _text(first['alert_type'], fallback: '') == 'emergency';
    final Color color = isEmergency ? AppColors.danger : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                isEmergency ? '🚨' : '⚠️',
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text(first['title'], fallback: 'Alert'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _text(first['message'], fallback: 'No details'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: isDark
                        ? AppColors.textMutedDark
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(bool isDark) {
    final Map<String, dynamic> bp = _map(_data['bp']);
    final Map<String, dynamic> weight = _map(_data['weight']);
    final Map<String, dynamic> water = _map(_data['water']);
    final Map<String, dynamic> sugar = _map(_data['sugar']);
    final Map<String, dynamic> sleep = _map(_data['sleep']);
    final Map<String, dynamic> bpLatest = _map(bp['latest']);
    final Map<String, dynamic> weightLatest = _map(weight['latest']);
    final Map<String, dynamic> sugarLatest = _map(sugar['latest']);
    final Map<String, dynamic> sleepLatest = _map(sleep['last_night']);

    final String bpStr = bpLatest.isNotEmpty
        ? '${_int(bpLatest['value_1'])}/${_int(bpLatest['value_2'])}'
        : '—';
    final String bpStatus = _text(bp['status'], fallback: 'No Reading');

    final stepSvc = context.watch<StepTrackingService>();
    final int liveSteps = stepSvc.todaySteps;
    final int stepGoal = stepSvc.dailyGoal <= 0 ? 1 : stepSvc.dailyGoal;
    final int stepPct = ((liveSteps / stepGoal) * 100).clamp(0, 100).toInt();

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: [
        _StatTile(
          emoji: '❤️',
          label: 'Blood Pressure',
          value: bpStr,
          sub: bpStatus,
          color: AppTheme.bpStatusColor(bpStatus),
          isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/bp').then((_) => _load()),
        ),
        _StatTile(
          emoji: '⚖️',
          label: 'Weight',
          value: weightLatest.isNotEmpty
              ? '${_text(weightLatest['value_1'])} kg'
              : '—',
          sub: _text(weight['bmi_status'], fallback: 'No data'),
          color: AppColors.violet,
          isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/weight').then((_) => _load()),
        ),
        _StatTile(
          emoji: '💧',
          label: 'Water',
          value: '${_text(water['today_total'], fallback: '0')}L',
          sub:
              '${_text(water['pct'], fallback: '0')}% of ${_text(water['target'], fallback: '2.5')}L',
          color: AppColors.water,
          isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/water').then((_) => _load()),
        ),
        _StatTile(
          emoji: '👟',
          label: stepSvc.isTracking ? 'Steps 🔴' : 'Steps',
          value: '$liveSteps',
          sub: '$stepPct% of $stepGoal · ${stepSvc.estimatedDistanceKm}km',
          color: stepSvc.goalAchieved ? AppColors.success : AppColors.info,
          isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/exercise'),
        ),
        _StatTile(
          emoji: '🩺',
          label: 'Blood Sugar',
          value: sugarLatest.isNotEmpty
              ? '${_int(sugarLatest['value_1'])} mg'
              : '—',
          sub: _text(sugar['status'], fallback: 'No reading'),
          color: AppColors.sugar,
          isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/sugar').then((_) => _load()),
        ),
        _StatTile(
          emoji: '😴',
          label: 'Sleep',
          value: sleepLatest.isNotEmpty
              ? '${_text(sleepLatest['duration_hours'])}h'
              : '—',
          sub: _text(sleep['quality_label'], fallback: 'No data'),
          color: AppColors.sleep,
          isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/sleep').then((_) => _load()),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      ('❤️', 'BP', AppColors.danger, '/bp'),
      ('💧', 'Water', AppColors.water, '/water'),
      ('⚖️', 'Weight', AppColors.violet, '/weight'),
      ('😴', 'Sleep', AppColors.sleep, '/sleep'),
      ('🩺', 'Sugar', AppColors.sugar, '/sugar'),
      ('💊', 'Medicines', AppColors.medicine, '/medicines'),
      ('🧪', 'Lab Tests', AppColors.warning, '/lab-tests'),
      ('📅', 'Appointments', AppColors.info, '/appointments'),
      ('🏃', 'Exercise', AppColors.exercise, '/exercise'),
      ('🤖', 'AI Assist', AppColors.sage, '/ai'),
      ('📷', 'AI Camera', AppColors.violet, '/ai-camera'),
      ('📋', 'Timeline', AppColors.navy, '/timeline'),
      ('🚨', 'Emergency', AppColors.danger, '/emergency'),
      ('⏰', 'Reminders', AppColors.gold, '/reminders'),
      ('📊', 'Reports', AppColors.sage, '/reports'),
      ('💎', 'Plans', AppColors.violet, '/plans'),
    ];

    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final a = actions[i];
          return _QuickAction(
            emoji: a.$1,
            label: a.$2,
            color: a.$3,
            onTap: () => Navigator.pushNamed(context, a.$4).then((_) => _load()),
          );
        },
      ),
    );
  }

  Widget _buildInsights(bool isDark) {
    final List<dynamic> insights = _list(_data['insights']);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: insights.asMap().entries.map((e) {
          final int i = e.key;
          final Map<String, dynamic> ins = _map(e.value);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: i < insights.length - 1
                      ? (isDark
                          ? const Color(0xFF1E3250)
                          : Colors.grey.shade100)
                      : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text(ins['icon'], fallback: '💡'),
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _text(ins['text'], fallback: ''),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color:
                          isDark ? AppColors.textOnDark : AppColors.textPrimary,
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

  Widget _buildMealsCard(bool isDark) {
    final Map<String, dynamic> meals = _map(_data['meals']);
    final List<dynamic> items = _list(meals['items']);
    final int done = _int(meals['done']);
    final int total = _int(meals['total']);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$done/$total meals done',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textMutedDark
                          : AppColors.textMuted,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/meals'),
                  child: Text(
                    'View all →',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.sage,
                    ),
                  ),
                ),
              ],
            ),
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
              child: Text(
                'No meal plan yet.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.textMutedDark
                      : AppColors.textMuted,
                ),
              ),
            )
          else
            ...items.map((m) {
              final meal = _map(m);
              final recipe = _map(meal['recipe']);
              final bool isDone = meal['completed'] == true;

              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDone
                        ? AppColors.success.withOpacity(0.12)
                        : AppColors.sage.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Icon(
                      isDone
                          ? Icons.check_rounded
                          : Icons.restaurant_rounded,
                      size: 16,
                      color: isDone ? AppColors.success : AppColors.sage,
                    ),
                  ),
                ),
                title: Text(
                  _text(recipe['name'], fallback: 'Meal'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color:
                        isDark ? AppColors.textOnDark : AppColors.textPrimary,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(
                  _text(meal['meal_slot'], fallback: ''),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.textMutedDark
                        : AppColors.textMuted,
                  ),
                ),
                trailing: Text(
                  '${_text(recipe['calories'], fallback: '0')} kcal',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.textMutedDark
                        : AppColors.textMuted,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildMedicinesCard(bool isDark) {
    final Map<String, dynamic> meds = _map(_data['medicines']);
    final List<dynamic> list = _list(meds['list']);
    if (list.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Text(
                  '${_int(meds['taken'])}/${_int(meds['total'])} taken',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textMutedDark
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          ...list.map((m) {
            final med = _map(m);
            final bool taken = med['taken'] == true;

            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: taken
                      ? AppColors.success.withOpacity(0.12)
                      : AppColors.medicine.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    taken ? '✅' : '💊',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
              title: Text(
                _text(med['name'], fallback: 'Medicine'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                '${_text(med['dosage'], fallback: '')} · ${_text(med['timing'], fallback: '')}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final String sub;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _StatTile({
    required this.emoji,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(isDark ? 0.12 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: isDark
                            ? AppColors.textMutedDark
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 10,
                    color: isDark
                        ? AppColors.textMutedDark
                        : AppColors.textMuted,
                  ),
                ],
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1.1,
                ),
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.emoji,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withOpacity(isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withOpacity(isDark ? 0.30 : 0.20),
              ),
            ),
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 66,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}