// ============================================================
// lib/screens/meal_screen.dart — Meal Plan, Recipes, Grocery
// ============================================================

import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

class MealScreen extends StatefulWidget {
  const MealScreen({super.key});

  @override
  State<MealScreen> createState() => _MealScreenState();
}

class _MealScreenState extends State<MealScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Meals', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.sage,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.sage,
          tabs: const [Tab(text: '📅 Plan'), Tab(text: '🍲 Recipes'), Tab(text: '🛒 Grocery')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_PlanTab(), _RecipesTab(), _GroceryTab()],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}

// ════════════════════════════════════════════════════════════
// MEAL PLAN TAB
// ════════════════════════════════════════════════════════════
class _PlanTab extends StatefulWidget {
  const _PlanTab();
  @override
  State<_PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<_PlanTab> {
  final _api = ApiService();
  Map<String, dynamic>? _data;
  bool _loading = true, _generating = false;
  String _selectedDay = '';

  final _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  void initState() {
    super.initState();
    _selectedDay = _days[DateTime.now().weekday - 1];
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getMealPlan();
    if (resp.success) setState(() => _data = resp.data);
    setState(() => _loading = false);
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    final resp = await _api.generateMealPlan();
    setState(() => _generating = false);
    if (resp.success) {
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🍱 Meal plan generated!'), backgroundColor: AppColors.success));
    }
  }

  Future<void> _toggleDone(int itemId) async {
    await _api.markMealDone(itemId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();

    if (_data == null || _data!['has_plan'] != true) {
      return EmptyState(
        emoji: '🍱', title: 'No meal plan yet',
        subtitle: 'Generate a personalized weekly meal plan based on your health conditions and goals.',
        action: ElevatedButton(
          onPressed: _generating ? null : _generate,
          child: _generating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('🍱 Generate Meal Plan'),
        ),
      );
    }

    final days = _data!['days'] as Map<String, dynamic>;
    final items = (days[_selectedDay] ?? []) as List;
    final today = _data!['today'];

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          if (today != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: StatCard(
                label: "Today's Progress", value: '${today['meals_done']}/${today['meals_total']}',
                sublabel: '${today['today_calories_consumed']} kcal consumed', emoji: '🍽️', color: AppColors.sage,
              ),
            ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _days.map((d) {
                final selected = d == _selectedDay;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(d.substring(0, 3)),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedDay = d),
                    selectedColor: AppColors.sage.withOpacity(0.2),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final recipe = item['recipe'];
                final done = item['completed'] == true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: GestureDetector(
                      onTap: () => _toggleDone(item['id']),
                      child: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? AppColors.success : AppColors.textMuted, size: 28),
                    ),
                    title: Text(recipe['name'], style: TextStyle(fontWeight: FontWeight.w600, decoration: done ? TextDecoration.lineThrough : null)),
                    subtitle: Text('${item['meal_slot']} · ${recipe['calories']} kcal · ${recipe['protein']}g protein', style: const TextStyle(fontSize: 12)),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: _generating ? null : _generate, child: const Text('🔄 Regenerate Plan')),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// RECIPES TAB
// ════════════════════════════════════════════════════════════
class _RecipesTab extends StatefulWidget {
  const _RecipesTab();
  @override
  State<_RecipesTab> createState() => _RecipesTabState();
}

class _RecipesTabState extends State<_RecipesTab> {
  final _api = ApiService();
  List<dynamic> _recipes = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getRecipes(search: _searchCtrl.text);
    if (resp.success) setState(() => _recipes = resp.data['recipes'] ?? []);
    setState(() => _loading = false);
  }

  Future<void> _toggleFav(int id, int index) async {
    final resp = await _api.toggleFavourite(id);
    if (resp.success) {
      setState(() => _recipes[index]['is_favourite'] = resp.data['is_favourite']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(hintText: 'Search recipes...', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); _load(); })),
            onSubmitted: (_) => _load(),
          ),
        ),
        Expanded(
          child: _loading
              ? const LoadingView()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _recipes.length,
                  itemBuilder: (context, i) {
                    final r = _recipes[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: AppColors.sage.withOpacity(0.1), child: const Text('🍲')),
                        title: Text(r['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text('${r['calories']} kcal · ${r['protein']}g protein · ${r['category'] ?? ''}', style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: Icon(r['is_favourite'] == true ? Icons.favorite : Icons.favorite_border, color: r['is_favourite'] == true ? AppColors.danger : AppColors.textMuted),
                          onPressed: () => _toggleFav(r['id'], i),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// GROCERY TAB
// ════════════════════════════════════════════════════════════
class _GroceryTab extends StatefulWidget {
  const _GroceryTab();
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
    final resp = await _api.getGroceryList();
    if (resp.success) setState(() => _data = resp.data);
    setState(() => _loading = false);
  }

  Future<void> _toggle(int id) async {
    await _api.toggleGroceryItem(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_data == null || (_data!['items'] as List).isEmpty) {
      return const EmptyState(emoji: '🛒', title: 'No grocery list yet', subtitle: 'Generate a meal plan first to create your grocery list.');
    }

    final grouped = _data!['grouped'] as Map<String, dynamic>;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LinearProgressIndicator(value: (_data!['pct'] ?? 0) / 100, minHeight: 8, borderRadius: BorderRadius.circular(100), color: AppColors.sage, backgroundColor: AppColors.sage.withOpacity(0.12)),
          const SizedBox(height: 6),
          Text('${_data!['purchased']}/${_data!['total']} items purchased', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 16),
          ...grouped.entries.map((entry) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(entry.key, style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold, fontSize: 14))),
                  ...(entry.value as List).map((item) => CheckboxListTile(
                        value: item['purchased'] == true,
                        onChanged: (_) => _toggle(item['id']),
                        title: Text(item['name'], style: TextStyle(fontSize: 13, decoration: item['purchased'] == true ? TextDecoration.lineThrough : null)),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppColors.sage,
                        dense: true,
                      )),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}