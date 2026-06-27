// lib/screens/meal_screen.dart — Meals + Dark Mode + Offline cache
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart' hide AppBottomNav;
import 'bp_tracker_screen.dart' show _CardBox, _SyncBadge;

class MealScreen extends StatefulWidget {
  const MealScreen({super.key});
  @override State<MealScreen> createState() => _MealScreenState();
}

class _MealScreenState extends State<MealScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  @override void initState() { super.initState(); _tabs = TabController(length: 3, vsync: this); }
  @override void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Meals', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [SyncBadge(SyncService().isOnline)],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.sage, unselectedLabelColor: isDark ? AppColors.textMutedDark : AppColors.textMuted, indicatorColor: AppColors.sage,
          tabs: const [Tab(text: '📅 Plan'), Tab(text: '🍲 Recipes'), Tab(text: '🛒 Grocery')],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _PlanTab(isDark: isDark),
        _RecipesTab(isDark: isDark),
        _GroceryTab(isDark: isDark),
      ]),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// PLAN TAB
// ════════════════════════════════════════════════════════════════
class _PlanTab extends StatefulWidget {
  final bool isDark;
  const _PlanTab({required this.isDark});
  @override State<_PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<_PlanTab> {
  final _api  = ApiService();
  Map<String,dynamic>? _data;
  bool _loading = true, _generating = false;
  String _day = '';
  final _days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];

  @override
  void initState() {
    super.initState();
    _day = _days[DateTime.now().weekday - 1];
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
    if (resp.success) { await _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🍱 ${resp.message}'), backgroundColor: AppColors.success)); }
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = widget.isDark;
    final card    = isDark ? AppColors.cardDark : Colors.white;
    final brd     = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp      = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm      = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    if (_loading) return const LoadingView();
    if (_data == null || _data!['has_plan'] != true) {
      return EmptyState(
        emoji: '🍱', title: 'No meal plan yet',
        subtitle: 'Generate a personalised weekly meal plan based on your health goals.',
        action: ElevatedButton(
          onPressed: _generating ? null : _generate,
          child: _generating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('🍱 Generate Meal Plan'),
        ),
      );
    }

    final today  = _data!['today'];
    final days   = _data!['days'] as Map<String,dynamic>;
    final items  = (days[_day] ?? []) as List;

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(children: [
        // Today summary
        if (today != null)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.sage, Color(0xFF047857)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Today\'s Progress', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white70)),
                const SizedBox(height: 6),
                Text('${today['meals_done']}/${today['meals_total']} meals done', style: const TextStyle(fontFamily: 'Fraunces', fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 6),
                ClipRRect(borderRadius: BorderRadius.circular(100), child: LinearProgressIndicator(
                  value: today['meals_total'] > 0 ? today['meals_done'] / today['meals_total'] : 0,
                  minHeight: 6, backgroundColor: Colors.white.withOpacity(0.2), color: Colors.white)),
              ])),
              Text('${today['today_calories_consumed'] ?? 0} kcal', style: const TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),

        // Day selector
        SizedBox(height: 40, child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: _days.map((d) {
            final sel = d == _day;
            return Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
              onTap: () => setState(() => _day = d),
              child: AnimatedContainer(duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: sel ? AppColors.sage : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: sel ? AppColors.sage : Colors.transparent)),
                child: Text(d.substring(0, 3), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : tm))),
            ));
          }).toList(),
        )),
        const SizedBox(height: 8),

        // Meal items
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.isEmpty ? 1 : items.length,
          itemBuilder: (_, i) {
            if (items.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('No meals for $_day.', style: TextStyle(color: tm))));
            final m      = items[i];
            final recipe = m['recipe'];
            final done   = m['completed'] == true;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16), border: Border.all(color: brd),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6)]),
              child: Row(children: [
                GestureDetector(
                  onTap: () async { await _api.markMealDone(m['id']); _load(); },
                  child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: 36, height: 36,
                    decoration: BoxDecoration(color: done ? AppColors.success.withOpacity(0.12) : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100), borderRadius: BorderRadius.circular(10)),
                    child: Icon(done ? Icons.check_rounded : Icons.restaurant_rounded, size: 18, color: done ? AppColors.success : tm)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m['meal_slot'] ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.sage, letterSpacing: 0.5)),
                  Text(recipe['name'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tp, decoration: done ? TextDecoration.lineThrough : null)),
                  Text('${recipe['calories']} kcal · ${recipe['protein']}g protein', style: TextStyle(fontSize: 11, color: tm)),
                ])),
                if (done) const Text('✅', style: TextStyle(fontSize: 18)),
              ]),
            );
          },
        )),
        Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: OutlinedButton(
          onPressed: _generating ? null : _generate,
          child: Text(_generating ? '⏳ Generating...' : '🔄 Regenerate Plan'),
        ))),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// RECIPES TAB
// ════════════════════════════════════════════════════════════════
class _RecipesTab extends StatefulWidget {
  final bool isDark;
  const _RecipesTab({required this.isDark});
  @override State<_RecipesTab> createState() => _RecipesTabState();
}

class _RecipesTabState extends State<_RecipesTab> {
  final _api         = ApiService();
  final _searchCtrl  = TextEditingController();
  List<dynamic> _recipes = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getRecipes(search: _searchCtrl.text);
    if (resp.success) setState(() => _recipes = resp.data['recipes'] ?? []);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final card   = isDark ? AppColors.cardDark : Colors.white;
    final brd    = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp     = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm     = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search recipes...',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _searchCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () { _searchCtrl.clear(); _load(); }) : null,
        ),
        onSubmitted: (_) => _load(),
        onChanged: (v) { if (v.isEmpty) _load(); setState(() {}); },
      )),
      Expanded(child: _loading ? const LoadingView() : RefreshIndicator(
        onRefresh: _load,
        child: _recipes.isEmpty
            ? const EmptyState(emoji: '🍲', title: 'No recipes found', subtitle: 'Try a different search term.')
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _recipes.length,
                itemBuilder: (_, i) {
                  final r    = _recipes[i];
                  final isFav= r['is_favourite'] == true;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16), border: Border.all(color: brd)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.sage.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: const Center(child: Text('🍲', style: TextStyle(fontSize: 22)))),
                      title: Text(r['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: tp)),
                      subtitle: Text('${r['calories']} kcal · ${r['protein']}g protein · ${r['category'] ?? ''}', style: TextStyle(fontSize: 11, color: tm)),
                      trailing: IconButton(
                        icon: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: isFav ? AppColors.danger : tm, size: 20),
                        onPressed: () async { await _api.toggleFavourite(r['id']); _load(); },
                      ),
                    ),
                  );
                },
              ),
      )),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════
// GROCERY TAB
// ════════════════════════════════════════════════════════════════
class _GroceryTab extends StatefulWidget {
  final bool isDark;
  const _GroceryTab({required this.isDark});
  @override State<_GroceryTab> createState() => _GroceryTabState();
}

class _GroceryTabState extends State<_GroceryTab> {
  final _api = ApiService();
  Map<String,dynamic>? _data;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getGroceryList();
    if (resp.success) setState(() => _data = resp.data);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final card   = isDark ? AppColors.cardDark : Colors.white;
    final brd    = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp     = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm     = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    if (_loading) return const LoadingView();
    if (_data == null || (_data!['items'] as List? ?? []).isEmpty) {
      return const EmptyState(emoji: '🛒', title: 'No grocery list', subtitle: 'Generate a meal plan first.');
    }

    final grouped = _data!['grouped'] as Map<String,dynamic>? ?? {};
    final pct     = _data!['pct'] ?? 0;
    final bought  = _data!['purchased'] ?? 0;
    final total   = _data!['total'] ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Progress
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14), border: Border.all(color: brd)), child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('$bought/$total items', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tp)),
              Text('$pct% done', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.sage)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(100), child: LinearProgressIndicator(value: pct / 100, minHeight: 8, color: AppColors.sage, backgroundColor: AppColors.sage.withOpacity(0.12))),
          ])),
          const SizedBox(height: 12),

          ...grouped.entries.map((e) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(e.key, style: TextStyle(fontFamily: 'Fraunces', fontSize: 14, fontWeight: FontWeight.bold, color: tp))),
            Container(decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14), border: Border.all(color: brd)), child: Column(
              children: (e.value as List).map((item) {
                final purchased = item['purchased'] == true;
                return CheckboxListTile(
                  dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  value: purchased,
                  onChanged: (_) async { await _api.toggleGroceryItem(item['id']); _load(); },
                  activeColor: AppColors.sage,
                  title: Text(item['name'] ?? '', style: TextStyle(fontSize: 13, color: purchased ? tm : tp,
                      decoration: purchased ? TextDecoration.lineThrough : null)),
                  side: BorderSide(color: brd),
                );
              }).toList(),
            )),
            const SizedBox(height: 8),
          ])),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}