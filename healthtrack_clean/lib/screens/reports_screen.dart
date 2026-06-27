// lib/screens/reports_screen.dart — Health Reports
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart' hide AppBottomNav;

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _api = ApiService();
  bool _loading = true, _sending = false;
  Map<String, dynamic>? _emailConfig;
  List<dynamic> _history = [];
  int _selectedPeriod = 7;
  final _emailCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _emailCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([_api.getEmailConfig(), _api.getReportHistory()]);
    if (results[0].success) setState(() => _emailConfig = results[0].data);
    if (results[1].success) setState(() => _history = results[1].data['history'] ?? []);
    setState(() => _loading = false);
  }

  Future<void> _sendReport() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty && (_emailConfig?['recipients'] == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter at least one email address')));
      return;
    }
    setState(() => _sending = true);
    final resp = await _api.sendReportNow(
      periodDays: _selectedPeriod,
      recipients: email.isNotEmpty ? [email] : null,
    );
    setState(() => _sending = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(resp.success ? '✅ ${resp.message}' : '❌ ${resp.message}'),
        backgroundColor: resp.success ? AppColors.success : AppColors.danger,
      ));
      if (resp.success) { _emailCtrl.clear(); _load(); }
    }
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
        title: const Text('Reports', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: _loading ? const LoadingView() : RefreshIndicator(
        onRefresh: _load,
        color: AppColors.sage,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Hero ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF142D4C), Color(0xFF1E3F6E), Color(0xFF4F3B78)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('📊 Health Reports', style: TextStyle(fontFamily: 'Fraunces', fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text('Send detailed PDF reports to your email or doctor', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.75))),
                  const SizedBox(height: 10),
                  if (_emailConfig?['auth_provider'] == 'google')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(100)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('📧', style: TextStyle(fontSize: 13)),
                        SizedBox(width: 6),
                        Text('Sent from your Gmail', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                      ]),
                    ),
                ])),
                const Text('📊', style: TextStyle(fontSize: 42, color: Colors.white24)),
              ]),
            ),
            const SizedBox(height: 20),

            // ── Send Report Card ──────────────────────────────────
            _SectionCard(
              title: '📤 Send Report',
              isDark: isDark, cardBg: cardBg, border: border, textPrimary: textPrimary,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // Period selector
                Text('Report Period', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: textMuted, letterSpacing: 0.7)),
                const SizedBox(height: 10),
                Row(children: [7, 14, 30, 90].map((days) {
                  final sel = days == _selectedPeriod;
                  return Expanded(child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedPeriod = days),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.sage : (isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: sel ? AppColors.sage : Colors.transparent),
                        ),
                        child: Column(children: [
                          Text('$days', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: sel ? AppColors.navy : textMuted)),
                          Text('days', style: TextStyle(fontSize: 10, color: sel ? AppColors.navy : textMuted, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ));
                }).toList()),
                const SizedBox(height: 14),

                // Email input
                Text('Send To', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textMuted, letterSpacing: 0.7)),
                const SizedBox(height: 8),
                if (_emailConfig?['recipients'] != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.sage.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.sage.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle, color: AppColors.sage, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Default: ${_emailConfig!['recipients']}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.sage))),
                    ]),
                  ),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: _emailConfig?['recipients'] != null ? 'Or add another email...' : 'doctor@example.com',
                    prefixIcon: const Padding(padding: EdgeInsets.all(12), child: Text('📧', style: TextStyle(fontSize: 16))),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  ),
                ),
                const SizedBox(height: 14),

                // Send button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _sending ? null : _sendReport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.sage,
                      foregroundColor: AppColors.navy,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
                        : Text('📤 Send $_selectedPeriod-Day Report', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // ── What's included ──────────────────────────────────
            _SectionCard(
              title: '📋 What\'s Included',
              isDark: isDark, cardBg: cardBg, border: border, textPrimary: textPrimary,
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final item in ['❤️ Blood Pressure', '⚖️ Weight', '💧 Water', '😴 Sleep',
                    '🏃 Exercise', '🩺 Blood Sugar', '👟 Steps', '💊 Medicines', '📊 Health Score', '💡 Insights'])
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A2E45) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(item, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textMuted)),
                  ),
              ]),
            ),
            const SizedBox(height: 16),

            // ── History ──────────────────────────────────────────
            _SectionCard(
              title: '📜 Report History',
              isDark: isDark, cardBg: cardBg, border: border, textPrimary: textPrimary,
              child: _history.isEmpty
                  ? Center(child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('No reports sent yet.', style: TextStyle(color: textMuted)),
                    ))
                  : Column(children: _history.take(10).map((h) {
                      final sent = h['status'] == 'sent';
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border, width: 0.5))),
                        child: Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: (sent ? AppColors.success : AppColors.danger).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(child: Text(sent ? '✅' : '❌', style: const TextStyle(fontSize: 16))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(h['recipients'] ?? 'Unknown', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                            Text('${h['period_days'] ?? '?'}-day report · ${h['sent_at']?.toString().substring(0, 10) ?? ''}',
                                style: TextStyle(fontSize: 11, color: textMuted)),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (sent ? AppColors.success : AppColors.danger).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(h['status']?.toString().toUpperCase() ?? '',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                                    color: sent ? AppColors.success : AppColors.danger)),
                          ),
                        ]),
                      );
                    }).toList()),
            ),
            const SizedBox(height: 80),
          ]),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 4),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final bool isDark;
  final Color cardBg, border, textPrimary;
  const _SectionCard({required this.title, required this.child, required this.isDark,
      required this.cardBg, required this.border, required this.textPrimary});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Text(title, style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
        ),
        Divider(height: 1, color: border),
        Padding(padding: const EdgeInsets.all(16), child: child),
      ]),
    );
  }
}