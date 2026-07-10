// lib/screens/documents_screen.dart — FIXED Document Vault with working upload
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
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
  final _api    = ApiService();
  final _picker = ImagePicker();
  List<dynamic> _docs = [];
  bool _loading = true, _uploading = false;
  String _selectedType = 'all';

  static const _types = {
    'all':          ('📁', 'All'),
    'lab_report':   ('🧪', 'Lab Report'),
    'prescription': ('💊', 'Prescription'),
    'insurance':    ('🛡️', 'Insurance'),
    'xray':         ('🦴', 'X-Ray'),
    'ecg':          ('❤️', 'ECG'),
    'mri':          ('🧠', 'MRI'),
    'vaccination':  ('💉', 'Vaccination'),
    'other':        ('📄', 'Other'),
  };

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resp = await _api.getDocuments(
      docType: _selectedType == 'all' ? null : _selectedType,
    );
    if (resp.success) setState(() => _docs = resp.data['documents'] ?? []);
    setState(() => _loading = false);
  }

  // ── UPLOAD ──────────────────────────────────────────────────────
  Future<void> _showUploadSheet() async {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final titleCtrl  = TextEditingController();
    String docType   = 'lab_report';
    File? selectedFile;
    String? selectedFileName;
    bool uploading   = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('📎 Upload Document', style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),

              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Document Title', hintText: 'e.g. Blood Report Jan 2026')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: docType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: _types.entries
                    .where((e) => e.key != 'all')
                    .map((e) => DropdownMenuItem(value: e.key, child: Text('${e.value.$1} ${e.value.$2}')))
                    .toList(),
                onChanged: (v) => setSt(() => docType = v ?? 'lab_report'),
              ),
              const SizedBox(height: 14),

              // File pick / camera buttons
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: const Text('Pick File'),
                  onPressed: () async {
                    final r = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
                    );
                    if (r != null && r.files.single.path != null) {
                      setSt(() {
                        selectedFile     = File(r.files.single.path!);
                        selectedFileName = r.files.single.name;
                      });
                    }
                  },
                )),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: const Text('Camera'),
                  onPressed: () async {
                    final img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
                    if (img != null) {
                      setSt(() {
                        selectedFile     = File(img.path);
                        selectedFileName = 'doc_${DateTime.now().millisecondsSinceEpoch}.jpg';
                      });
                    }
                  },
                )),
              ]),

              // Show selected file
              if (selectedFile != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.success.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(selectedFileName ?? 'File selected',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success),
                        overflow: TextOverflow.ellipsis)),
                    GestureDetector(
                      onTap: () => setSt(() { selectedFile = null; selectedFileName = null; }),
                      child: const Icon(Icons.close_rounded, size: 16, color: AppColors.success),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 16),

              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: (titleCtrl.text.trim().isEmpty || selectedFile == null || uploading) ? null : () async {
                  setSt(() => uploading = true);
                  Navigator.pop(ctx);
                  await _uploadFile(titleCtrl.text.trim(), docType, selectedFile!);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.document, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: uploading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('📤 Upload Document', style: TextStyle(fontWeight: FontWeight.bold)),
              )),
            ],
          )),
        ),
      ),
    );
  }

  Future<void> _uploadFile(String title, String docType, File file) async {
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final b64   = base64Encode(bytes);
      final ext   = file.path.split('.').last.toLowerCase();

      final resp = await _api.post('/documents/upload', data: {
        'title':     title,
        'doc_type':  docType,
        'file_data': b64,
        'file_name': '${title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.$ext',
        'mime_type': _mimeType(ext),
      });

      if (resp.success) {
        _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ ${resp.message}'), backgroundColor: AppColors.success));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ ${resp.message}'), backgroundColor: AppColors.danger));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Upload failed: $e'), backgroundColor: AppColors.danger));
    }
    setState(() => _uploading = false);
  }

  String _mimeType(String ext) {
    const map = {'pdf':'application/pdf','jpg':'image/jpeg','jpeg':'image/jpeg',
      'png':'image/png','doc':'application/msword',
      'docx':'application/vnd.openxmlformats-officedocument.wordprocessingml.document'};
    return map[ext] ?? 'application/octet-stream';
  }

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
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _showUploadSheet,
        backgroundColor: AppColors.document,
        foregroundColor: Colors.white,
        icon: _uploading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.upload_file_rounded),
        label: Text(_uploading ? 'Uploading...' : 'Upload', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(children: [
        // Type filter chips
        SizedBox(height: 48, child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: _types.entries.map((e) {
            final sel = e.key == _selectedType;
            return Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
              onTap: () { setState(() => _selectedType = e.key); _load(); },
              child: AnimatedContainer(duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? AppColors.document : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(e.value.$1, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Text(e.value.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : tm)),
                ])),
            ));
          }).toList())),

        Expanded(child: _loading
            ? const LoadingView()
            : RefreshIndicator(
                onRefresh: _load, color: AppColors.document,
                child: _docs.isEmpty
                    ? EmptyState(
                        emoji: '🗂️',
                        title: 'No documents yet',
                        subtitle: 'Upload lab reports, prescriptions, and medical files.',
                        action: ElevatedButton(
                          onPressed: _showUploadSheet,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.document, foregroundColor: Colors.white),
                          child: const Text('📤 Upload First Document'),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: _docs.length,
                        itemBuilder: (context, i) {
                          final doc     = _docs[i];
                          final info    = _types[doc['doc_type']] ?? ('📄', 'Document');
                          final starred = doc['is_important'] == true;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: card, borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: starred ? AppColors.gold.withOpacity(0.5) : brd),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0,2))],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              leading: Container(width: 46, height: 46,
                                decoration: BoxDecoration(color: AppColors.document.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                child: Center(child: Text(info.$1, style: const TextStyle(fontSize: 22)))),
                              title: Row(children: [
                                Expanded(child: Text(doc['title'] ?? '', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: tp))),
                                if (starred) const Text('⭐', style: TextStyle(fontSize: 14)),
                              ]),
                              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const SizedBox(height: 3),
                                Text(info.$2, style: const TextStyle(fontSize: 12, color: AppColors.document, fontWeight: FontWeight.w600)),
                                if ((doc['doctor_name'] ?? '').isNotEmpty) Text('Dr. ${doc['doctor_name']}', style: TextStyle(fontSize: 11, color: tm)),
                                Text(doc['uploaded_at']?.toString().substring(0, 10) ?? '', style: TextStyle(fontSize: 11, color: tm)),
                              ]),
                              trailing: PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert_rounded, color: tm, size: 20),
                                color: card,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                onSelected: (a) async {
                                  if (a == 'star') { await _api.toggleDocumentImportant(doc['id']); _load(); }
                                  else if (a == 'delete') {
                                    final ok = await showConfirmDialog(context, 'Delete Document', 'Remove "${doc['title']}"?');
                                    if (ok) { await _api.deleteDocument(doc['id']); _load(); }
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'star', child: Text(starred ? '☆  Unstar' : '⭐  Star', style: TextStyle(color: tp))),
                                  PopupMenuItem(value: 'delete', child: Text('🗑️  Delete', style: TextStyle(color: AppColors.danger))),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              )),
      ]),
      bottomNavigationBar: const AppBottomNav(currentIndex: 4),
    );
  }
}