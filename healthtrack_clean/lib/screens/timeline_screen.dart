// lib/screens/timeline_screen.dart — Module 20: Health Timeline
import 'package:flutter/material.dart';
import 'package:timeline_tile/timeline_tile.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});
  @override State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final _api = ApiService();
  List<dynamic> _events = [];
  bool _loading = true;
  String _filter = 'all';

  static const _categories = {
    'all': ('📋', 'All'), 'bp': ('❤️', 'BP'), 'weight': ('⚖️', 'Weight'),
    'medicine': ('💊', 'Medicine'), 'lab': ('🧪', 'Lab'), 'visit': ('👨‍⚕️', 'Visits'),
    'document': ('🗂️', 'Docs'), 'score': ('📊', 'Score'),
  };

  static const _categoryColors = {
    'bp': AppColors.danger, 'weight': AppColors.violet, 'medicine': AppColors.medicine,
    'lab': AppColors.sugar, 'visit': AppColors.info, 'document': AppColors.document, 'score': AppColors.sage,
  };

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getTimeline(category: _filter == 'all' ? null : _filter);
    if (resp.success) setState(() => _events = resp.data['events'] ?? []);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Health Timeline', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold))),
      body: Column(children: [
        SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          children: _categories.entries.map((e) {
            final sel = e.key == _filter;
            return Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
              onTap: () { setState(() => _filter = e.key); _load(); },
              child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: sel ? AppColors.navy : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100), borderRadius: BorderRadius.circular(100)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(e.value.$1, style: const TextStyle(fontSize: 13)), const SizedBox(width: 5),
                  Text(e.value.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : tm)),
                ])),
            ));
          }).toList())),
        Expanded(child: _loading ? const LoadingView() : (_events.isEmpty
            ? const EmptyState(emoji: '📋', title: 'No events yet', subtitle: 'Your health activity will appear here as a timeline')
            : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: _events.length,
                itemBuilder: (context, i) {
                  final e = _events[i];
                  final color = _categoryColors[e['event_type']] ?? AppColors.navy;
                  final isFirst = i == 0, isLast = i == _events.length - 1;
                  return TimelineTile(
                    isFirst: isFirst, isLast: isLast,
                    alignment: TimelineAlign.start,
                    indicatorStyle: IndicatorStyle(width: 36, height: 36, color: color, padding: const EdgeInsets.all(4),
                        indicator: Container(decoration: BoxDecoration(color: color.withOpacity(isDark ? 0.25 : 0.12), shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
                            child: Center(child: Text(e['icon'] ?? '📋', style: const TextStyle(fontSize: 14))))),
                    beforeLineStyle: LineStyle(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200, thickness: 2),
                    endChild: Padding(padding: const EdgeInsets.only(left: 14, bottom: 18, top: 4),
                      child: Container(padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: isDark ? AppColors.cardDark : Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(e['title'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tp))),
                            Text(e['event_date'] ?? '', style: TextStyle(fontSize: 11, color: tm)),
                          ]),
                          if (e['description'] != null && e['description'].toString().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(e['description'], style: TextStyle(fontSize: 12, color: tm, height: 1.4)),
                          ],
                        ]))),
                  );
                },
              )))),
      ]),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }
}