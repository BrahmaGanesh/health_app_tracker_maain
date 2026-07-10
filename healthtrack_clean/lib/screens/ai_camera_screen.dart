// lib/screens/ai_camera_screen.dart — AI Camera with Settings Toggle
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';

// ── Settings keys ─────────────────────────────────────────────────
const _kFoodScanEnabled    = 'ai_food_scan_enabled';
const _kMedScanEnabled     = 'ai_med_scan_enabled';
const _kBloodScanEnabled   = 'ai_blood_scan_enabled';
const _kAutoSave           = 'ai_auto_save_result';

class AiCameraScreen extends StatefulWidget {
  const AiCameraScreen({super.key});
  @override State<AiCameraScreen> createState() => _AiCameraScreenState();
}

class _AiCameraScreenState extends State<AiCameraScreen> with SingleTickerProviderStateMixin {
  final _api    = ApiService();
  final _picker = ImagePicker();
  late TabController _tabs;

  bool _foodEnabled  = true;
  bool _medEnabled   = true;
  bool _bloodEnabled = false;
  bool _autoSave     = false;

  bool _scanning     = false;
  Map<String, dynamic>? _result;
  String _mode       = 'food'; // food / medicine / blood

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      setState(() => _mode = ['food', 'medicine', 'blood'][_tabs.index]);
    });
    _loadSettings();
  }

  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _foodEnabled  = p.getBool(_kFoodScanEnabled)  ?? true;
      _medEnabled   = p.getBool(_kMedScanEnabled)   ?? true;
      _bloodEnabled = p.getBool(_kBloodScanEnabled) ?? false;
      _autoSave     = p.getBool(_kAutoSave)         ?? false;
    });
  }

  Future<void> _saveSetting(String key, bool val) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, val);
  }

  bool get _currentEnabled {
    if (_mode == 'food')     return _foodEnabled;
    if (_mode == 'medicine') return _medEnabled;
    return _bloodEnabled;
  }

  Future<void> _scan() async {
    if (!_currentEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${_modeLabel()} scan is turned off. Enable it in Settings tab.'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    final picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 800);
    if (picked == null) return;

    setState(() { _scanning = true; _result = null; });

    final bytes   = await File(picked.path).readAsBytes();
    final base64  = base64Encode(bytes);

    ApiResponse resp;
    if (_mode == 'food') {
      resp = await _api.analyzeFoodPhoto(base64);
    } else if (_mode == 'medicine') {
      resp = await _api.analyzeMedicinePhoto(base64);
    } else {
      resp = await _api.analyzeFoodPhoto(base64); // blood scan uses food analysis endpoint
    }

    setState(() { _scanning = false; _result = resp.success ? resp.data : {'error': resp.message}; });

    // Auto-save if enabled
    if (_autoSave && resp.success && _mode == 'food') {
      final cal = resp.data['calories'] as num?;
      if (cal != null && cal > 0) {
        await _api.logExercise(exerciseName: 'Meal scan: ${resp.data['food_name']}', exerciseType: 'other');
      }
    }
  }

  String _modeLabel() {
    if (_mode == 'food')     return '🍱 Food';
    if (_mode == 'medicine') return '💊 Medicine';
    return '🩸 Blood Result';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final brd  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('AI Camera', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.sage, unselectedLabelColor: tm, indicatorColor: AppColors.sage,
          tabs: [
            Tab(text: _foodEnabled  ? '🍱 Food'     : '🍱 Food 🔴'),
            Tab(text: _medEnabled   ? '💊 Medicine' : '💊 Med 🔴'),
            Tab(text: _bloodEnabled ? '🩸 Blood'    : '🩸 Blood 🔴'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _buildScanTab(isDark, tp, tm, card, brd, 'food',     _foodEnabled),
        _buildScanTab(isDark, tp, tm, card, brd, 'medicine', _medEnabled),
        _buildScanTab(isDark, tp, tm, card, brd, 'blood',    _bloodEnabled),
      ]),
    );
  }

  Widget _buildScanTab(bool isDark, Color tp, Color tm, Color card, Color brd, String mode, bool enabled) {
    final isActive = _mode == mode;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ON/OFF toggle
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: brd)),
          child: Row(children: [
            Text(_modeIcon(mode), style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_modeName(mode)} Scan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tp)),
              Text(enabled ? 'Tap camera button to scan' : 'Disabled — toggle to enable', style: TextStyle(fontSize: 12, color: enabled ? AppColors.success : tm)),
            ])),
            Switch(
              value: enabled,
              activeColor: AppColors.sage,
              onChanged: (v) async {
                final key = mode == 'food' ? _kFoodScanEnabled : mode == 'medicine' ? _kMedScanEnabled : _kBloodScanEnabled;
                await _saveSetting(key, v);
                setState(() {
                  if (mode == 'food')     _foodEnabled  = v;
                  if (mode == 'medicine') _medEnabled   = v;
                  if (mode == 'blood')    _bloodEnabled = v;
                });
              },
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Auto-save toggle (food only)
        if (mode == 'food')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14), border: Border.all(color: brd)),
            child: Row(children: [
              const Text('💾', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Auto-save to meal log', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tp)),
                Text('Automatically logs detected food', style: TextStyle(fontSize: 11, color: tm)),
              ])),
              Switch(value: _autoSave, activeColor: AppColors.sage, onChanged: (v) async { await _saveSetting(_kAutoSave, v); setState(() => _autoSave = v); }),
            ]),
          ),
        if (mode == 'food') const SizedBox(height: 16),

        // Camera button
        if (enabled)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isActive && !_scanning ? () { _mode = mode; _scan(); } : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _modeColor(mode),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: _scanning && isActive
                  ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      SizedBox(width: 10),
                      Text('Analysing...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ])
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.camera_alt_rounded, size: 22),
                      const SizedBox(width: 10),
                      Text('Take Photo to Scan ${_modeName(mode)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ]),
            ),
          ),

        if (!enabled)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              Text(_modeIcon(mode), style: const TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              Text('${_modeName(mode)} scan is OFF', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tm)),
              const SizedBox(height: 4),
              Text('Toggle the switch above to enable', style: TextStyle(fontSize: 12, color: tm)),
            ]),
          ),
        const SizedBox(height: 20),

        // Result card
        if (isActive && _result != null) ...[
          Text('📊 Result', style: TextStyle(fontFamily: 'Fraunces', fontSize: 17, fontWeight: FontWeight.bold, color: tp)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: _result!.containsKey('error') ? AppColors.danger.withOpacity(0.3) : AppColors.success.withOpacity(0.3))),
            child: _result!.containsKey('error')
                ? Row(children: [
                    const Text('❌', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_result!['error'].toString(), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600))),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (mode == 'food') ...[
                      _ResultRow('Food',     _result!['food_name']?.toString() ?? '—', tp),
                      _ResultRow('Calories', '${_result!['calories'] ?? 0} kcal', AppColors.danger),
                      _ResultRow('Protein',  '${_result!['protein_g'] ?? 0}g', AppColors.success),
                      _ResultRow('Carbs',    '${_result!['carbs_g'] ?? 0}g', AppColors.warning),
                      _ResultRow('Fat',      '${_result!['fat_g'] ?? 0}g', tm),
                      _ResultRow('Sodium',   '${_result!['sodium_mg'] ?? 0}mg', tm),
                      const SizedBox(height: 8),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(
                        color: (_result!['is_healthy_for_bp'] == true ? AppColors.success : AppColors.warning).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(100)),
                        child: Text(_result!['is_healthy_for_bp'] == true ? '✅ BP-Friendly food' : '⚠️ High sodium — eat in moderation',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _result!['is_healthy_for_bp'] == true ? AppColors.success : AppColors.warning))),
                    ] else if (mode == 'medicine') ...[
                      _ResultRow('Medicine',     _result!['medicine_name']?.toString() ?? '—', tp),
                      _ResultRow('Active',       _result!['active_ingredient']?.toString() ?? '—', tm),
                      _ResultRow('Common uses',  _result!['common_uses']?.toString() ?? '—', tm),
                      _ResultRow('Typical dose', _result!['typical_dosage']?.toString() ?? '—', tp),
                      if (_result!['requires_prescription'] == true)
                        Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                          child: const Row(children: [
                            Text('⚠️', style: TextStyle(fontSize: 16)),
                            SizedBox(width: 8),
                            Expanded(child: Text('Prescription required. Take only as prescribed by doctor.', style: TextStyle(fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.w600))),
                          ])),
                    ],
                    if (_result!['notes'] != null) ...[
                      const SizedBox(height: 10),
                      Text(_result!['notes'].toString(), style: TextStyle(fontSize: 12, color: tm, fontStyle: FontStyle.italic, height: 1.4)),
                    ],
                  ]),
          ),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: OutlinedButton(
            onPressed: () => setState(() => _result = null),
            child: const Text('🔄 Scan Again'),
          )),
        ],

        // Disclaimer
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
          child: Text(
            '⚕️ This AI analysis is for informational purposes only. Always consult your doctor for medical decisions.',
            style: TextStyle(fontSize: 11, color: tm, height: 1.5),
          )),
        const SizedBox(height: 40),
      ]),
    );
  }

  String _modeIcon(String mode) { if (mode == 'food') return '🍱'; if (mode == 'medicine') return '💊'; return '🩸'; }
  String _modeName(String mode) { if (mode == 'food') return 'Food'; if (mode == 'medicine') return 'Medicine'; return 'Blood Result'; }
  Color  _modeColor(String mode) { if (mode == 'food') return AppColors.sage; if (mode == 'medicine') return AppColors.medicine; return AppColors.danger; }
}

class _ResultRow extends StatelessWidget {
  final String label, value; final Color color;
  const _ResultRow(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
      Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))),
    ]),
  );
}