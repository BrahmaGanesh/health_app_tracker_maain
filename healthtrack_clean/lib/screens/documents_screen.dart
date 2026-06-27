// lib/screens/documents_screen.dart — Medical Document Vault
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart' hide AppBottomNav;

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});
  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _api = ApiService();
  List<dynamic> _docs = [];
  bool _loading = true;
  String _selectedType = 'all';

  static const _types = {
    'all':         ('📁', 'All'),
    'lab_report':  ('🧪', 'Lab Reports'),
    'prescription':('💊', 'Prescriptions'),
    'insurance':   ('🛡️', 'Insurance'),
    'xray':        ('🦴', 'X-Ray'),
    'ecg':         ('❤️', 'ECG'),
    'mri':         ('🧠', 'MRI'),
    'vaccination': ('💉', 'Vaccination'),
    'other':       ('📄', 'Other'),
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.get('/documents/list',
        query: _selectedType != 'all' ? {'type': _selectedType} : null);
    if (resp.success) setState(() => _docs = resp.data['documents'] ?? []);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.cardDark : Colors.white;
    final border = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final textPrimary = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final textMuted   = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Documents', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(children: [

        // ── Type filter chips ──────────────────────────────────
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: _types.entries.map((e) {
              final sel = e.key == _selectedType;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () { setState(() => _selectedType = e.key); _load(); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.document : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: sel ? AppColors.document : Colors.transparent),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(e.value.$1, style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      Text(e.value.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : textMuted)),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // ── Doc list ──────────────────────────────────────────
        Expanded(
          child: _loading
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.document,
                  child: _docs.isEmpty
                      ? EmptyState(
                          emoji: '🗂️',
                          title: 'No documents yet',
                          subtitle: 'Upload lab reports, prescriptions, and medical documents from the website.',
                          action: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.document.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.document.withOpacity(0.3)),
                            ),
                            child: Text('Upload available on website →',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.document)),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          itemCount: _docs.length,
                          itemBuilder: (context, i) {
                            final doc = _docs[i];
                            final typeInfo = _types[doc['doc_type']] ?? ('📄', 'Document');
                            final isImportant = doc['is_important'] == true;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isImportant ? AppColors.gold.withOpacity(0.5) : border),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: Container(
                                  width: 48, height: 48,
                                  decoration: BoxDecoration(
                                    color: AppColors.document.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Center(child: Text(typeInfo.$1, style: const TextStyle(fontSize: 22))),
                                ),
                                title: Row(children: [
                                  Expanded(child: Text(doc['title'] ?? '', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary))),
                                  if (isImportant) const Text('⭐', style: TextStyle(fontSize: 14)),
                                ]),
                                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  const SizedBox(height: 3),
                                  Text(typeInfo.$2, style: TextStyle(fontSize: 12, color: AppColors.document, fontWeight: FontWeight.w600)),
                                  if (doc['doctor_name'] != null && doc['doctor_name'].toString().isNotEmpty)
                                    Text('Dr. ${doc['doctor_name']}', style: TextStyle(fontSize: 11, color: textMuted)),
                                  Text(doc['uploaded_at']?.toString().substring(0, 10) ?? '', style: TextStyle(fontSize: 11, color: textMuted)),
                                ]),
                                trailing: PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert_rounded, color: textMuted, size: 20),
                                  color: cardBg,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  onSelected: (action) => _handleAction(action, doc),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(value: 'download', child: Row(children: [const Text('⬇️  '), Text('Download', style: TextStyle(color: textPrimary))])),
                                    PopupMenuItem(value: 'important', child: Row(children: [Text(isImportant ? '☆  ' : '⭐  '), Text(isImportant ? 'Unstar' : 'Star', style: TextStyle(color: textPrimary))])),
                                    PopupMenuItem(value: 'delete', child: Row(children: [const Text('🗑️  '), Text('Delete', style: TextStyle(color: AppColors.danger))])),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ]),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }

  void _handleAction(String action, Map<String, dynamic> doc) async {
    if (action == 'download') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📥 Open on website to download')));
    } else if (action == 'important') {
      await _api.post('/documents/${doc['id']}/toggle-important');
      _load();
    } else if (action == 'delete') {
      final confirm = await showConfirmDialog(context, 'Delete Document', 'Remove "${doc['title']}"?');
      if (confirm) { await _api.delete('/documents/${doc['id']}'); _load(); }
    }
  }
}