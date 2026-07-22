// lib/screens/documents_screen.dart — Complete Document Vault
// Free: 3 docs | Premium: 10 + search/filter/sort/rename/favourite/preview | Family: 20
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});
  @override State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _api        = ApiService();
  final _searchCtrl = TextEditingController();
  final _picker     = ImagePicker();

  List<dynamic> _docs      = [];
  Map<String, dynamic>? _meta;
  bool _loading    = true;
  bool _uploading  = false;
  String _selType  = 'all';
  String _sortBy   = 'date';
  bool   _favOnly  = false;

  // ── Plan helpers ──────────────────────────────────────────────
  bool get _isPremium => _meta?['plan_info']?['is_premium'] == true;
  int  get _limit     => (_meta?['plan_info']?['limit'] ?? 3) as int;
  int  get _used      => (_meta?['used'] ?? 0) as int;
  bool get _canUpload => _meta?['can_upload'] == true;

  static const _categories = {
    'all':                 ('📁', 'All'),
    'prescription':        ('💊', 'Prescription'),
    'lab_report':          ('🧪', 'Lab Report'),
    'blood_test':          ('🩸', 'Blood Test'),
    'xray':                ('🦴', 'X-Ray'),
    'mri_ct':              ('🧠', 'MRI / CT'),
    'vaccination':         ('💉', 'Vaccination'),
    'insurance':           ('🛡️', 'Insurance'),
    'doctor_notes':        ('📝', 'Doctor Notes'),
    'medical_certificate': ('📜', 'Certificate'),
    'other':               ('📄', 'Other'),
  };

  @override void initState() { super.initState(); _load(); }
  @override void dispose()   { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final params = <String, dynamic>{};
    if (_isPremium) {
      if (_selType != 'all') params['type']        = _selType;
      if (_searchCtrl.text.trim().isNotEmpty) params['search'] = _searchCtrl.text.trim();
      if (_favOnly)          params['favourites']  = 'true';
      params['sort'] = _sortBy;
    }
    final resp = await _api.getDocuments(
      docType: (!_isPremium || _selType == 'all') ? null : _selType,
    );
    if (resp.success) {
      setState(() { _docs = resp.data['documents'] ?? []; _meta = resp.data; });
    }
    setState(() => _loading = false);
  }

  // ════════════════════════════════════════════════════════════
  // UPLOAD SHEET
  // ════════════════════════════════════════════════════════════
  Future<void> _showUploadSheet() async {
    if (!_canUpload) {
      _showUpgradeSnack();
      return;
    }
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final titleCtrl = TextEditingController();
    final docCtrl   = TextEditingController();
    final hospCtrl  = TextEditingController();
    final notesCtrl = TextEditingController();
    String docType  = 'lab_report';
    String? dateStr;
    List<_SelectedFile> selectedFiles = [];
    bool uploading = false;

    await showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (_, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          const Text('📎 Upload Document', style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),

          // File picker buttons
          Row(children: [
            Expanded(child: _PickBtn('📂 File', Icons.attach_file_rounded, () async {
              final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf','jpg','jpeg','png']);
              if (r != null) setSt(() => selectedFiles = r.files.where((f) => f.path != null).map((f) => _SelectedFile(File(f.path!), f.name)).toList());
            })),
            const SizedBox(width: 8),
            Expanded(child: _PickBtn('📷 Camera', Icons.camera_alt_rounded, () async {
              final img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
              if (img != null) setSt(() => selectedFiles = [_SelectedFile(File(img.path), 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg')]);
            })),
            const SizedBox(width: 8),
            Expanded(child: _PickBtn('🖼️ Gallery', Icons.photo_library_rounded, () async {
              final img = await _picker.pickMultiImage(imageQuality: 85);
              if (img.isNotEmpty) setSt(() => selectedFiles = img.map((x) => _SelectedFile(File(x.path), x.name)).toList());
            })),
          ]),

          // Selected files preview
          if (selectedFiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.success.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.success.withOpacity(0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 16), const SizedBox(width: 6),
                  Text('${selectedFiles.length} file(s) selected', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
                  const Spacer(), GestureDetector(onTap: () => setSt(() => selectedFiles = []), child: const Icon(Icons.close_rounded, size: 16, color: AppColors.success))],
                ),
                ...selectedFiles.map((f) => Padding(padding: const EdgeInsets.only(top: 4), child: Text('• ${f.name}', style: const TextStyle(fontSize: 11, color: AppColors.success), overflow: TextOverflow.ellipsis))),
              ])),
          ],
          const SizedBox(height: 12),

          // Metadata fields
          TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Document Title', hintText: 'e.g. Blood Test Report Jan 2026')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: docType, decoration: const InputDecoration(labelText: 'Category'),
            items: _categories.entries.where((e) => e.key != 'all').map((e) => DropdownMenuItem(value: e.key, child: Text('${e.value.$1} ${e.value.$2}', style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) => setSt(() => docType = v ?? 'lab_report'),
          ),
          const SizedBox(height: 10),
          TextField(controller: docCtrl, decoration: const InputDecoration(labelText: 'Doctor Name (optional)', hintText: 'Dr. Sharma')),
          const SizedBox(height: 10),
          TextField(controller: hospCtrl, decoration: const InputDecoration(labelText: 'Hospital / Clinic (optional)')),
          const SizedBox(height: 10),
          ListTile(contentPadding: EdgeInsets.zero, dense: true,
            title: const Text('Document Date (optional)', style: TextStyle(fontSize: 12)),
            subtitle: Text(dateStr ?? 'Tap to select', style: TextStyle(fontSize: 13, color: dateStr != null ? AppColors.navy : AppColors.textMuted)),
            trailing: const Icon(Icons.calendar_today_rounded, size: 18),
            onTap: () async {
              final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2010), lastDate: DateTime.now());
              if (d != null) setSt(() => dateStr = d.toIso8601String().substring(0, 10));
            }),
          TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)'), maxLines: 2),
          const SizedBox(height: 16),

          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: (selectedFiles.isEmpty || uploading) ? null : () async {
              setSt(() => uploading = true);
              Navigator.pop(ctx);
              await _uploadFiles(
                files: selectedFiles,
                title: titleCtrl.text.trim(),
                docType: docType,
                doctorName: docCtrl.text.trim(),
                hospitalName: hospCtrl.text.trim(),
                reportDate: dateStr,
                notes: notesCtrl.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.document, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: uploading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('📤 Upload ${selectedFiles.length > 1 ? '${selectedFiles.length} Files' : 'Document'}', style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
        ])),
      )),
    );
  }

  Future<void> _uploadFiles({
    required List<_SelectedFile> files,
    required String title, required String docType,
    String? doctorName, String? hospitalName, String? reportDate, String? notes,
  }) async {
    setState(() => _uploading = true);
    int uploaded = 0, failed = 0;
    for (final f in files) {
      try {
        final bytes   = await f.file.readAsBytes();
        if (bytes.lengthInBytes > 10 * 1024 * 1024) { failed++; continue; }
        final b64     = base64Encode(bytes);
        final ext     = f.name.split('.').last.toLowerCase();
        final mimes   = {'pdf':'application/pdf','jpg':'image/jpeg','jpeg':'image/jpeg','png':'image/png'};
        final resp    = await _api.post('/documents/upload', data: {
          'title':         files.length > 1 ? '${title.isEmpty ? docType : title} ${uploaded + 1}' : (title.isEmpty ? f.name : title),
          'doc_type':      docType,
          'file_data':     b64,
          'file_name':     f.name,
          'mime_type':     mimes[ext] ?? 'application/pdf',
          if ((doctorName ?? '').isNotEmpty)   'doctor_name':    doctorName,
          if ((hospitalName ?? '').isNotEmpty) 'hospital_name':  hospitalName,
          if (reportDate != null)              'report_date':    reportDate,
          if ((notes ?? '').isNotEmpty)        'notes':          notes,
        });
        if (resp.success) uploaded++; else failed++;
      } catch (_) { failed++; }
    }
    setState(() => _uploading = false);
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failed == 0 ? '✅ $uploaded document(s) uploaded' : '⚠️ $uploaded uploaded, $failed failed'),
        backgroundColor: failed == 0 ? AppColors.success : AppColors.warning,
      ));
    }
  }

  void _showUpgradeSnack() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('🔒 ${_used}/$_limit documents used. Upgrade for more storage.'),
      backgroundColor: AppColors.warning,
      action: SnackBarAction(label: 'Upgrade', textColor: Colors.white, onPressed: () => Navigator.pushNamed(context, '/plans')),
    ));
  }

  // ════════════════════════════════════════════════════════════
  // DOCUMENT ACTIONS
  // ════════════════════════════════════════════════════════════
  void _onAction(String action, dynamic doc) async {
    switch (action) {
      case 'rename':
        if (!_isPremium) { _showUpgradeSnack(); return; }
        final ctrl = TextEditingController(text: doc['title']);
        await showDialog(context: context, builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('✏️ Rename Document'),
          content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'New title')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () async { Navigator.pop(context); await _api.put('/documents/${doc['id']}/rename', data: {'title': ctrl.text.trim()}); _load(); }, child: const Text('Save')),
          ],
        ));
        break;
      case 'favourite':
        if (!_isPremium) { _showUpgradeSnack(); return; }
        await _api.post('/documents/${doc['id']}/favourite');
        _load();
        break;
      case 'download':
        await _api.get('/documents/${doc['id']}/download');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📥 Download started')));
        break;
      case 'delete':
        final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [Text('⚠️ ', style: TextStyle(fontSize: 22)), Text('Delete Document')]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Remove "${doc['title']}"?', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
              child: const Text('This document will be permanently deleted from the server. This cannot be undone.', style: TextStyle(fontSize: 12, color: AppColors.danger))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white), child: const Text('Delete')),
          ],
        ));
        if (ok == true) { await _api.deleteDocument(doc['id']); _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🗑️ ${doc['title']} deleted'), backgroundColor: AppColors.success)); }
        break;
      case 'edit':
        _showEditSheet(doc);
        break;
    }
  }

  void _showEditSheet(dynamic doc) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final titleCtrl = TextEditingController(text: doc['title'] ?? '');
    final docCtrl   = TextEditingController(text: doc['doctor_name'] ?? '');
    final hospCtrl  = TextEditingController(text: doc['hospital_name'] ?? '');
    final notesCtrl = TextEditingController(text: doc['notes'] ?? '');
    String docType  = doc['doc_type'] ?? 'other';

    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (_, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('✏️ Edit Document', style: TextStyle(fontFamily: 'Fraunces', fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: docType, decoration: const InputDecoration(labelText: 'Category'),
            items: _categories.entries.where((e) => e.key != 'all').map((e) => DropdownMenuItem(value: e.key, child: Text('${e.value.$1} ${e.value.$2}', style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) => setSt(() => docType = v ?? 'other')),
          const SizedBox(height: 10),
          TextField(controller: docCtrl, decoration: const InputDecoration(labelText: 'Doctor Name')),
          const SizedBox(height: 10),
          TextField(controller: hospCtrl, decoration: const InputDecoration(labelText: 'Hospital / Clinic')),
          const SizedBox(height: 10),
          TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              await _api.put('/documents/${doc['id']}', data: {
                'title': titleCtrl.text.trim(), 'doc_type': docType,
                'doctor_name': docCtrl.text.trim(), 'hospital_name': hospCtrl.text.trim(), 'notes': notesCtrl.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            },
            child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
          )),
        ])),
      )));
  }

  // ════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card   = isDark ? AppColors.cardDark : Colors.white;
    final brd    = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final tp     = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm     = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Documents', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [
          if (_isPremium)
            IconButton(icon: Icon(_favOnly ? Icons.star_rounded : Icons.star_border_rounded, color: _favOnly ? AppColors.gold : null), onPressed: () { setState(() => _favOnly = !_favOnly); _load(); }),
          if (_isPremium)
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort_rounded),
              tooltip: 'Sort',
              onSelected: (v) { setState(() => _sortBy = v); _load(); },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'date', child: Text('📅 By Date')),
                PopupMenuItem(value: 'name', child: Text('🔤 By Name')),
                PopupMenuItem(value: 'size', child: Text('📦 By Size')),
                PopupMenuItem(value: 'type', child: Text('🗂️ By Type')),
              ],
            ),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _showUploadSheet,
        backgroundColor: AppColors.document,
        foregroundColor: Colors.white,
        icon: _uploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload_file_rounded),
        label: Text(_uploading ? 'Uploading...' : 'Upload', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(children: [
        // Storage usage bar
        _StorageBar(used: _used, limit: _limit, plan: _meta?['plan_info']?['plan'] ?? 'free', isDark: isDark),

        // Premium: search bar
        if (_isPremium)
          Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search documents...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () { _searchCtrl.clear(); _load(); setState(() {}); }) : null,
              ),
              onSubmitted: (_) => _load(),
              onChanged: (_) { if (_searchCtrl.text.isEmpty) _load(); setState(() {}); },
            )),

        // Category filter chips
        SizedBox(height: 46, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          children: (_isPremium ? _categories.entries : [_categories.entries.first, ..._categories.entries.skip(1).take(4)]).map((e) {
            final sel = e.key == _selType;
            return Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
              onTap: () { setState(() => _selType = e.key); _load(); },
              child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                decoration: BoxDecoration(color: sel ? AppColors.document : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100), borderRadius: BorderRadius.circular(100)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(e.value.$1, style: const TextStyle(fontSize: 13)), const SizedBox(width: 5),
                  Text(e.value.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : tm)),
                ])),
            ));
          }).toList())),

        // Document list
        Expanded(child: _loading
            ? const LoadingView()
            : RefreshIndicator(onRefresh: _load, child: _docs.isEmpty
                ? EmptyState(
                    emoji: '🗂️',
                    title: _favOnly ? 'No starred documents' : 'No documents yet',
                    subtitle: _favOnly ? 'Star a document to see it here' : 'Upload lab reports, prescriptions, and more.',
                    action: ElevatedButton(
                      onPressed: _showUploadSheet,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.document, foregroundColor: Colors.white),
                      child: const Text('📤 Upload First Document'),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 100),
                    itemCount: _docs.length,
                    itemBuilder: (_, i) => _DocumentCard(
                      doc: _docs[i], isDark: isDark, isPremium: _isPremium,
                      card: card, brd: brd, tp: tp, tm: tm,
                      onAction: _onAction,
                    ),
                  ))),
      ]),
      bottomNavigationBar: const AppBottomNav(currentIndex: 4),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// STORAGE BAR
// ════════════════════════════════════════════════════════════════
class _StorageBar extends StatelessWidget {
  final int used, limit; final String plan; final bool isDark;
  const _StorageBar({required this.used, required this.limit, required this.plan, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final pct = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final color = pct >= 0.9 ? AppColors.danger : pct >= 0.7 ? AppColors.warning : AppColors.success;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Text('🗂️', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text('Document Storage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? AppColors.textOnDark : AppColors.textPrimary)),
          ]),
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(100)),
              child: Text('$used/$limit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color, fontFamily: 'monospace'))),
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppColors.document.withOpacity(0.1), borderRadius: BorderRadius.circular(100)),
              child: Text(plan.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.document, letterSpacing: 0.5))),
          ]),
        ]),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: pct), duration: const Duration(milliseconds: 900), curve: Curves.easeOutCubic,
          builder: (_, v, __) => ClipRRect(borderRadius: BorderRadius.circular(100), child: LinearProgressIndicator(value: v, minHeight: 7, color: color, backgroundColor: color.withOpacity(0.1)))),
        if (pct >= 0.9) Padding(padding: const EdgeInsets.only(top: 6),
          child: GestureDetector(onTap: () => Navigator.pushNamed(context, '/plans'),
            child: Text('Storage almost full. Upgrade for more →', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)))),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// DOCUMENT CARD
// ════════════════════════════════════════════════════════════════
class _DocumentCard extends StatelessWidget {
  final dynamic doc; final bool isDark, isPremium;
  final Color card, brd, tp, tm;
  final void Function(String, dynamic) onAction;
  const _DocumentCard({required this.doc, required this.isDark, required this.isPremium, required this.card, required this.brd, required this.tp, required this.tm, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final starred  = doc['is_important'] == true;
    final isImg    = doc['is_image'] == true;
    final icon     = doc['type_icon'] ?? '📄';
    final category = doc['type_label'] ?? 'Document';
    final sizeKb   = doc['file_size_kb'] as int?;
    final sizeStr  = sizeKb != null ? (sizeKb >= 1024 ? '${(sizeKb / 1024).toStringAsFixed(1)} MB' : '$sizeKb KB') : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: starred ? AppColors.gold.withOpacity(0.5) : brd, width: starred ? 1.5 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
        // Icon
        Container(width: 50, height: 50,
          decoration: BoxDecoration(color: AppColors.document.withOpacity(isDark ? 0.2 : 0.08), borderRadius: BorderRadius.circular(14)),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 24)))),
        const SizedBox(width: 12),

        // Info
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(doc['title'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tp), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (starred) const Text('⭐', style: TextStyle(fontSize: 14)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppColors.document.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(category, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.document))),
            const SizedBox(width: 6),
            if (isImg) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.info.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: const Text('IMG', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.info))),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            if (doc['doctor_name'] != null) Text('Dr. ${doc['doctor_name']}', style: TextStyle(fontSize: 11, color: tm)),
            if (doc['doctor_name'] != null && doc['uploaded_at'] != null) Text(' · ', style: TextStyle(fontSize: 11, color: tm)),
            Text(doc['uploaded_at'] ?? '', style: TextStyle(fontSize: 11, color: tm)),
            if (sizeStr.isNotEmpty) Text(' · $sizeStr', style: TextStyle(fontSize: 10, color: tm)),
          ]),
        ])),

        // Actions
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: tm, size: 20),
          color: card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (a) => onAction(a, doc),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Text('✏️  Edit Details', style: TextStyle(color: tp))),
            if (isPremium) PopupMenuItem(value: 'rename', child: Text('🔤  Rename', style: TextStyle(color: tp))),
            if (isPremium) PopupMenuItem(value: 'favourite', child: Text(starred ? '☆  Unstar' : '⭐  Star', style: TextStyle(color: tp))),
            PopupMenuItem(value: 'download', child: Text('📥  Download', style: TextStyle(color: tp))),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: const Text('🗑️  Delete', style: TextStyle(color: AppColors.danger))),
          ],
        ),
      ])),
    );
  }
}

// ── Helper classes ─────────────────────────────────────────────────
class _SelectedFile { final File file; final String name; _SelectedFile(this.file, this.name); }

class _PickBtn extends StatelessWidget {
  final String label; final IconData icon; final VoidCallback onTap;
  const _PickBtn(this.label, this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 18), const SizedBox(height: 3), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))]),
  );
}