// lib/screens/meal_screen.dart — Premium Meals + Recipes + Grocery + Nutrition
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tts_speaker_button.dart';

class MealScreen extends StatefulWidget {
  const MealScreen({super.key});

  @override
  State<MealScreen> createState() => _MealScreenState();
}

class _MealScreenState extends State<MealScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Meals',
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.sage,
          unselectedLabelColor:
              isDark ? AppColors.textMutedDark : AppColors.textMuted,
          indicatorColor: AppColors.sage,
          isScrollable: true,
          tabs: const [
            Tab(text: '📅 Plan'),
            Tab(text: '🍲 Recipes'),
            Tab(text: '📊 Nutrition'),
            Tab(text: '🛒 Grocery'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _PlanTab(),
          _RecipesTab(),
          _NutritionTab(),
          _GroceryTab(),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// PLAN TAB — mark meals done, regenerate options
// ════════════════════════════════════════════════════════════════
class _PlanTab extends StatefulWidget {
  @override
  State<_PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<_PlanTab> {
  final _api = ApiService();
  Map<String, dynamic>? _data;
  bool _loading = true, _gen = false;
  String _day = '';
  final _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];

  @override
  void initState() {
    super.initState();
    _day = _days[DateTime.now().weekday - 1];
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.getMealPlan();
    if (r.success) setState(() => _data = r.data);
    setState(() => _loading = false);
  }

  Future<void> _generate({String? slot}) async {
    setState(() => _gen = true);
    final r = await _api.post(
      '/meals/plan/generate',
      data: {'day': _day, 'slot': slot, 'regenerate': true},
    );
    setState(() => _gen = false);
    if (r.success) {
      _load();
      _snack('🍱 ${slot ?? 'Plan'} regenerated!');
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    if (_loading) return const LoadingView();

    if (_data == null || _data!['has_plan'] != true) {
      return EmptyState(
        emoji: '🍱',
        title: 'No meal plan yet',
        subtitle:
            'Generate a personalised plan based on your health goals.',
        action: ElevatedButton(
          onPressed: _gen ? null : () => _generate(),
          child: _gen
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('🍱 Generate Plan'),
        ),
      );
    }

    final today = _data!['today'];
    final days = _data!['days'] as Map<String, dynamic>;
    final items = (days[_day] ?? []) as List;

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          if (today != null)
            Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.sage, Color(0xFF047857)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Today\'s Progress',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${today['meals_done']}/${today['meals_total']} meals done',
                          style: const TextStyle(
                            fontFamily: 'Fraunces',
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(100),
                          child: LinearProgressIndicator(
                            value: today['meals_total'] > 0
                                ? today['meals_done'] / today['meals_total']
                                : 0,
                            minHeight: 6,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${today['today_calories_consumed'] ?? 0}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'kcal',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: _days.map((d) {
                final sel = d == _day;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _day = d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppColors.sage
                            : (isDark
                                ? const Color(0xFF1A2E45)
                                : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: sel ? AppColors.sage : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        d.substring(0, 3),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : tm,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$_day\'s meals',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: tp,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.sage,
                    size: 20,
                  ),
                  tooltip: 'Regenerate',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (s) {
                    if (s == 'day') {
                      _generate();
                    } else {
                      _generate(slot: s);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'day',
                      child: Text('🔄 Regenerate Entire Day'),
                    ),
                    const PopupMenuItem(
                      value: 'breakfast',
                      child: Text('🌅 Regenerate Breakfast'),
                    ),
                    const PopupMenuItem(
                      value: 'lunch',
                      child: Text('☀️ Regenerate Lunch'),
                    ),
                    const PopupMenuItem(
                      value: 'dinner',
                      child: Text('🌙 Regenerate Dinner'),
                    ),
                    const PopupMenuItem(
                      value: 'snack',
                      child: Text('🍎 Regenerate Snacks'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'week',
                      child: Text('📅 Regenerate Entire Week'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: _gen
                ? const LoadingView()
                : items.isEmpty
                    ? Center(
                        child: Text(
                          'No meals for $_day.',
                          style: TextStyle(color: tm),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 80),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final m = items[i];
                          final r = m['recipe'];
                          final done = m['completed'] == true;

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: done
                                  ? AppColors.success.withOpacity(
                                      isDark ? 0.15 : 0.06,
                                    )
                                  : (isDark
                                      ? AppColors.cardDark
                                      : Colors.white),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: done
                                    ? AppColors.success.withOpacity(0.4)
                                    : (isDark
                                        ? const Color(0xFF1E3250)
                                        : Colors.grey.shade200),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                )
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              leading: GestureDetector(
                                onTap: () async {
                                  await _api.markMealDone(m['id']);
                                  _load();
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: done
                                        ? AppColors.success.withOpacity(0.15)
                                        : AppColors.sage.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    done
                                        ? Icons.check_rounded
                                        : Icons.restaurant_rounded,
                                    size: 20,
                                    color: done
                                        ? AppColors.success
                                        : AppColors.sage,
                                  ),
                                ),
                              ),
                              title: Text(
                                r['name'] ?? '',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: done ? AppColors.success : tp,
                                  decoration: done
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m['meal_slot'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                      color: AppColors.sage,
                                    ),
                                  ),
                                  Text(
                                    '${r['calories']} kcal · ${r['protein']}g protein · ${r['cooking_time'] ?? '—'}',
                                    style: TextStyle(fontSize: 11, color: tm),
                                  ),
                                ],
                              ),
                              trailing: done
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.success.withOpacity(0.1),
                                        borderRadius:
                                            BorderRadius.circular(100),
                                      ),
                                      child: const Text(
                                        '✓ Done',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.success,
                                        ),
                                      ),
                                    )
                                  : ElevatedButton(
                                      onPressed: () async {
                                        await _api.markMealDone(m['id']);
                                        _load();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.sage,
                                        foregroundColor: AppColors.navy,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      child: const Text(
                                        'Done',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _gen ? null : () => _generate(slot: 'week'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: AppColors.sage),
                ),
                child: const Text(
                  '📅 Regenerate Entire Week',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.sage,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// RECIPES TAB — filters + search + bottom sheet
// ════════════════════════════════════════════════════════════════
class _RecipesTab extends StatefulWidget {
  @override
  State<_RecipesTab> createState() => _RecipesTabState();
}

class _RecipesTabState extends State<_RecipesTab> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  List<dynamic> _recipes = [];
  bool _loading = true;
  String _category = 'all', _goal = 'all', _diet = 'all';

  static const _categories = [
    'all',
    'breakfast',
    'lunch',
    'dinner',
    'snacks',
    'drinks'
  ];

  static const _categoryIcons = {
    'all': '🍽️',
    'breakfast': '🌅',
    'lunch': '☀️',
    'dinner': '🌙',
    'snacks': '🍎',
    'drinks': '🥤'
  };

  static const _goals = [
    ('all', 'All'),
    ('bp', '❤️ BP Friendly'),
    ('weight_loss', '⚖️ Weight Loss'),
    ('muscle', '💪 Muscle Gain'),
    ('heart', '💗 Heart Healthy'),
    ('diabetes', '🩺 Diabetes Friendly')
  ];

  static const _diets = [
    ('all', 'All'),
    ('vegetarian', '🥦 Vegetarian'),
    ('non_veg', '🍗 Non-Veg'),
    ('vegan', '🌱 Vegan'),
    ('high_protein', '🏋️ High Protein')
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final resp = await _api.getRecipes(
      search: _searchCtrl.text.trim().isEmpty ? '' : _searchCtrl.text.trim(),
      category: _category == 'all' ? '' : _category,
      goal: _goal == 'all' ? '' : _goal,
      diet: _diet == 'all' ? '' : _diet,
    );

    if (resp.success) {
      setState(() => _recipes = resp.data['recipes'] ?? []);
    }

    setState(() => _loading = false);
  }

  void _openRecipe(Map<String, dynamic> r) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, ctrl) => _RecipeBottomSheet(recipe: r, scrollCtrl: ctrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search recipes...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        _load();
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (_) {
              setState(() {});
            },
            onSubmitted: (_) => _load(),
          ),
        ),

        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            children: _categories.map((c) {
              final sel = c == _category;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _category = c);
                    _load();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: sel
                          ? AppColors.sage
                          : (isDark
                              ? const Color(0xFF1A2E45)
                              : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _categoryIcons[c] ?? '🍽️',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          c == 'all'
                              ? 'All'
                              : c[0].toUpperCase() + c.substring(1),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : tm,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        SizedBox(
          height: 38,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 14, right: 4),
                  children: _goals.map((g) {
                    final sel = g.$1 == _goal;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _goal = g.$1);
                          _load();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: sel
                                ? AppColors.danger.withOpacity(0.15)
                                : (isDark
                                    ? const Color(0xFF1A2E45)
                                    : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: sel
                                  ? AppColors.danger
                                  : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            g.$2,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: sel ? AppColors.danger : tm,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 14, right: 4, bottom: 6),
            children: _diets.map((d) {
              final sel = d.$1 == _diet;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _diet = d.$1);
                    _load();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: sel
                          ? AppColors.violet.withOpacity(0.15)
                          : (isDark
                              ? const Color(0xFF1A2E45)
                              : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: sel ? AppColors.violet : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      d.$2,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: sel ? AppColors.violet : tm,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        Expanded(
          child: _loading
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _recipes.isEmpty
                      ? const EmptyState(
                          emoji: '🍲',
                          title: 'No recipes found',
                          subtitle: 'Try different filters.',
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 80),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: _recipes.length,
                          itemBuilder: (_, i) => _RecipeCard(
                            recipe: _recipes[i],
                            onTap: () =>
                                _openRecipe(_recipes[i] as Map<String, dynamic>),
                          ),
                        ),
                ),
        ),
      ],
    );
  }
}

// ── Recipe Card ───────────────────────────────────────────────────
class _RecipeCard extends StatelessWidget {
  final dynamic recipe;
  final VoidCallback onTap;

  const _RecipeCard({required this.recipe, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFav = recipe['is_favourite'] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              child: recipe['image'] != null
                  ? Image.network(
                      recipe['image'],
                      height: 110,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(recipe),
                    )
                  : _placeholder(recipe),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          recipe['name'] ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF142D4C),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isFav) const Text('❤️', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${recipe['calories']} kcal',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.info.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${recipe['protein']}g protein',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.info,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        recipe['cooking_time'] ?? '—',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white54 : Colors.grey,
                        ),
                      ),
                      const Spacer(),
                      if (recipe['bp_friendly'] == true)
                        const Text('❤️', style: TextStyle(fontSize: 11)),
                      if (recipe['is_veg'] == true)
                        const Text('🥦', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(dynamic r) => Container(
        height: 110,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF142D4C), Color(0xFF4F3B78)],
          ),
        ),
        child: Center(
          child: Text(
            r['is_veg'] == true ? '🥦' : '🍗',
            style: const TextStyle(fontSize: 36),
          ),
        ),
      );
}

// ── Recipe Bottom Sheet ────────────────────────────────────────────
class _RecipeBottomSheet extends StatelessWidget {
  final Map<String, dynamic> recipe;
  final ScrollController scrollCtrl;

  const _RecipeBottomSheet({
    required this.recipe,
    required this.scrollCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final instructions = recipe['steps']?.toString() ??
        recipe['instructions']?.toString() ??
        'No instructions available.';

    return Stack(
      children: [
        ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            BsHeader(
              imageUrl: recipe['image'],
              emoji: recipe['is_veg'] == true ? '🥦' : '🍗',
              title: recipe['name'] ?? '',
              badge: Row(
                children: [
                  DifficultyChip(difficulty: recipe['difficulty'] ?? 'easy'),
                  const SizedBox(width: 8),
                  if (recipe['is_veg'] == true)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Text(
                        '🥦 Veg',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  MacroChip(
                    label: 'Calories',
                    value: '${recipe['calories']}',
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  MacroChip(
                    label: 'Protein',
                    value: '${recipe['protein']}g',
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 8),
                  MacroChip(
                    label: 'Carbs',
                    value: '${recipe['carbs'] ?? 0}g',
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  MacroChip(
                    label: 'Fat',
                    value: '${recipe['fats'] ?? recipe['fat'] ?? 0}g',
                    color: AppColors.violet,
                  ),
                  const SizedBox(width: 8),
                  MacroChip(
                    label: 'Fiber',
                    value: '${recipe['fiber'] ?? 0}g',
                    color: AppColors.sage,
                  ),
                  const SizedBox(width: 8),
                  MacroChip(
                    label: 'Sodium',
                    value: '${recipe['sodium'] ?? 0}mg',
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
            BsSection(
              title: '📋 Details',
              child: Column(
                children: [
                  InfoRow(
                    icon: '⏱️',
                    label: 'Cooking Time',
                    value: recipe['cooking_time'] ?? '—',
                  ),
                  InfoRow(
                    icon: '🍽️',
                    label: 'Servings',
                    value: '${recipe['servings'] ?? 1}',
                  ),
                  InfoRow(
                    icon: '📊',
                    label: 'Difficulty',
                    value: recipe['difficulty'] ?? '—',
                  ),
                  if (recipe['health_benefits'] != null)
                    InfoRow(
                      icon: '💚',
                      label: 'Benefits',
                      value: recipe['health_benefits'],
                    ),
                ],
              ),
            ),
            if (recipe['bp_friendly'] == true ||
                recipe['diabetes_friendly'] == true ||
                recipe['weight_loss_friendly'] == true)
              BsSection(
                title: '✅ Suitable For',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (recipe['bp_friendly'] == true)
                      _Tag('❤️ BP Friendly', AppColors.danger),
                    if (recipe['diabetes_friendly'] == true)
                      _Tag('🩺 Diabetes', AppColors.warning),
                    if (recipe['weight_loss_friendly'] == true)
                      _Tag('⚖️ Weight Loss', AppColors.success),
                    if (recipe['heart_friendly'] == true)
                      _Tag('💗 Heart Healthy', AppColors.danger),
                    if (recipe['high_protein'] == true)
                      _Tag('💪 High Protein', AppColors.info),
                  ],
                ),
              ),
            if (recipe['ingredients'] != null)
              BsSection(
                title: '🥕 Ingredients',
                child: Text(
                  recipe['ingredients'].toString(),
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF142D4C),
                    height: 1.7,
                  ),
                ),
              ),
            BsSection(
              title: '👨‍🍳 Cooking Instructions',
              child: Text(
                instructions,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : const Color(0xFF142D4C),
                  height: 1.8,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
        Positioned(
          bottom: 24,
          right: 20,
          child: TtsSpeakerButton(text: instructions),
        ),
      ],
    );
  }

  Widget _Tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: c.withOpacity(0.1),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: c.withOpacity(0.3)),
        ),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: c,
          ),
        ),
      );
}

// ════════════════════════════════════════════════════════════════
// NUTRITION TAB — animated progress bars from completed meals
// ════════════════════════════════════════════════════════════════
class _NutritionTab extends StatefulWidget {
  @override
  State<_NutritionTab> createState() => _NutritionTabState();
}

class _NutritionTabState extends State<_NutritionTab> {
  final _api = ApiService();
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.get('/nutrition/today');
    if (r.success) setState(() => _data = r.data);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp = isDark ? Colors.white : const Color(0xFF142D4C);
    final tm = isDark ? Colors.white60 : Colors.black54;

    if (_loading) return const LoadingView();

    if (_data == null) {
      return EmptyState(
        emoji: '📊',
        title: 'No data',
        subtitle: 'Complete meals to see nutrition.',
        action: ElevatedButton(
          onPressed: _load,
          child: const Text('Refresh'),
        ),
      );
    }

    final consumed = _data!['consumed'] ?? {};
    final targets = _data!['targets'] ?? {};
    final exercise = _data!['exercise_calories_burned'] ?? 0;
    final water = _data!['water_litres'] ?? 0;
    final cal = (consumed['calories'] ?? 0).toDouble();
    final targetCal = (targets['calories'] ?? 2000).toDouble();
    final netCal = cal - (exercise as num).toDouble();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _NetCard('🔥 Consumed', '${cal.toInt()} kcal', AppColors.danger, isDark),
              const SizedBox(width: 12),
              _NetCard('🏃 Burned', '$exercise kcal', AppColors.success, isDark),
              const SizedBox(width: 12),
              _NetCard(
                '⚡ Net',
                '${netCal.toInt()} kcal',
                netCal > targetCal ? AppColors.danger : AppColors.info,
                isDark,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: brd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📊 Macros Progress',
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: tp,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Based on ${_data!['meals_completed'] ?? 0} completed meals',
                  style: TextStyle(fontSize: 11, color: tm),
                ),
                const SizedBox(height: 14),
                AnimatedNutritionBar(
                  label: 'Calories',
                  value: cal,
                  max: targetCal,
                  color: AppColors.danger,
                  unit: 'kcal',
                ),
                AnimatedNutritionBar(
                  label: 'Protein',
                  value: (consumed['protein'] ?? 0).toDouble(),
                  max: (targets['protein'] ?? 80).toDouble(),
                  color: AppColors.info,
                  unit: 'g',
                ),
                AnimatedNutritionBar(
                  label: 'Carbs',
                  value: (consumed['carbs'] ?? 0).toDouble(),
                  max: (targets['carbs'] ?? 250).toDouble(),
                  color: AppColors.warning,
                  unit: 'g',
                ),
                AnimatedNutritionBar(
                  label: 'Fat',
                  value: (consumed['fats'] ?? 0).toDouble(),
                  max: (targets['fat'] ?? 65).toDouble(),
                  color: AppColors.violet,
                  unit: 'g',
                ),
                AnimatedNutritionBar(
                  label: 'Fiber',
                  value: (consumed['fiber'] ?? 0).toDouble(),
                  max: 25,
                  color: AppColors.sage,
                  unit: 'g',
                ),
                AnimatedNutritionBar(
                  label: 'Sodium',
                  value: (consumed['sodium'] ?? 0).toDouble(),
                  max: 2300,
                  color: AppColors.textMuted,
                  unit: 'mg',
                ),
                AnimatedNutritionBar(
                  label: 'Water',
                  value: (water as num).toDouble(),
                  max: 2.5,
                  color: AppColors.water,
                  unit: 'L',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: brd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📋 Today\'s Summary',
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: tp,
                  ),
                ),
                const SizedBox(height: 12),
                _SumRow(
                  'Meals completed',
                  '${_data!['meals_completed'] ?? 0} / ${_data!['meals_total'] ?? 0}',
                  tp,
                  tm,
                ),
                _SumRow(
                  'Exercises done',
                  '${_data!['exercises_completed'] ?? 0}',
                  tp,
                  tm,
                ),
                _SumRow('Calories consumed', '${cal.toInt()} kcal', tp, tm),
                _SumRow('Calories burned', '$exercise kcal', tp, tm),
                _SumRow(
                  'Net calories',
                  '${netCal.toInt()} kcal',
                  netCal > targetCal ? AppColors.danger : AppColors.success,
                  tm,
                ),
                _SumRow('Water intake', '$water L', tp, tm),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _NetCard(String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: color.withOpacity(0.8),
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _SumRow(String l, String v, Color vc, Color tm) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l, style: TextStyle(fontSize: 13, color: tm)),
          Text(
            v,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: vc,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// GROCERY TAB
// ════════════════════════════════════════════════════════════════
class _GroceryTab extends StatefulWidget {
  @override
  State<_GroceryTab> createState() => _GroceryTabState();
}

class _GroceryTabState extends State<_GroceryTab> {
  final _api = ApiService();
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.getGroceryList();
    if (r.success) setState(() => _data = r.data);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp = isDark ? Colors.white : const Color(0xFF142D4C);
    final tm = isDark ? Colors.white60 : Colors.black54;

    if (_loading) return const LoadingView();

    final items = (_data?['items'] as List?) ?? [];
    if (_data == null || items.isEmpty) {
      return const EmptyState(
        emoji: '🛒',
        title: 'No grocery list',
        subtitle: 'Generate a meal plan first.',
      );
    }

    final grouped = _data!['grouped'] as Map<String, dynamic>? ?? {};
    final pct = _data!['pct'] ?? 0;
    final bought = _data!['purchased'] ?? 0;
    final total = _data!['total'] ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: brd),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$bought/$total items',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: tp,
                      ),
                    ),
                    Text(
                      '$pct% done',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.sage,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct / 100),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 8,
                      color: AppColors.sage,
                      backgroundColor: AppColors.sage.withOpacity(0.12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...grouped.entries.map(
            (e) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    e.key,
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: tp,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: brd),
                  ),
                  child: Column(
                    children: (e.value as List).map((item) {
                      final purchased = item['purchased'] == true;
                      return CheckboxListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        value: purchased,
                        onChanged: (_) async {
                          await _api.toggleGroceryItem(item['id']);
                          _load();
                        },
                        activeColor: AppColors.sage,
                        title: Text(
                          item['name'] ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: purchased ? tm : tp,
                            decoration: purchased
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: item['quantity'] != null
                            ? Text(
                                item['quantity'],
                                style: TextStyle(fontSize: 11, color: tm),
                              )
                            : null,
                        side: BorderSide(color: brd),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}