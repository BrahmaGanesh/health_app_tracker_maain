// lib/screens/profile_screen.dart — Profile + Dark Mode Toggle
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../main.dart' show ThemeService;
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/security_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiService();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth   = context.watch<AuthService>();
    final theme  = context.watch<ThemeService>();
    final user   = auth.user;

    final cardBg  = isDark ? AppColors.cardDark : Colors.white;
    final border  = isDark ? const Color(0xFF1E3250) : Colors.grey.shade200;
    final textPrimary = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final textMuted   = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold)),
        actions: [
          Consumer<ThemeService>(
            builder: (_, t, __) => IconButton(
              icon: Icon(t.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
              onPressed: t.toggle,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: auth.refreshUser,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Profile Hero ──────────────────────────────────
            _buildProfileHero(user, isDark),
            const SizedBox(height: 20),

            // ── Stats row ─────────────────────────────────────
            _buildStatsRow(user, isDark, cardBg, border, textPrimary, textMuted),
            const SizedBox(height: 20),

            // ── Conditions ────────────────────────────────────
            if (auth.conditions.isNotEmpty) ...[
              _buildConditions(auth.conditions, isDark, cardBg, border, textPrimary),
              const SizedBox(height: 20),
            ],

            // ── Theme toggle card ──────────────────────────────
            _buildThemeCard(theme, isDark, cardBg, border, textPrimary, textMuted),
            const SizedBox(height: 16),

            // ── Quick links ───────────────────────────────────
            _buildSection('Health Tools', isDark, textPrimary),
            const SizedBox(height: 10),
            _buildMenuCard([
              _MenuItem('❤️', 'Blood Pressure', 'Log & trend tracking', '/bp'),
              _MenuItem('💧', 'Water Intake', 'Daily hydration goal', '/water'),
              _MenuItem('⚖️', 'Weight', 'BMI & goal progress', '/weight'),
              _MenuItem('😴', 'Sleep', 'Sleep pattern tracker', '/sleep'),
              _MenuItem('🩺', 'Blood Sugar', 'Fasting & post-meal', '/sugar'),
            ], isDark, cardBg, border, textPrimary, textMuted),
            const SizedBox(height: 16),
            _buildSection('Management', isDark, textPrimary),
            const SizedBox(height: 10),
            _buildMenuCard([
              _MenuItem('💊', 'Medicines', 'Stock & adherence tracking', '/medicines'),
              _MenuItem('🧪', 'Lab Tests', 'Blood reports & trends', '/lab-tests'),
              _MenuItem('📅', 'Appointments', 'Doctor & lab calendar', '/appointments'),
              _MenuItem('👨‍👩‍👧', 'Family Health', 'Track family members', '/family'),
              _MenuItem('🗂️', 'Documents', 'Medical document vault', '/documents'),
              _MenuItem('📊', 'Reports', 'Email health reports', '/reports'),
            ], isDark, cardBg, border, textPrimary, textMuted),
            const SizedBox(height: 16),
            _buildSection('Insights & AI', isDark, textPrimary),
            const SizedBox(height: 10),
            _buildMenuCard([
              _MenuItem('📋', 'Timeline', 'All health events', '/timeline'),
              _MenuItem('📈', 'Analytics', 'Charts & trends', '/analytics'),
              _MenuItem('🤖', 'Wellness AI', 'Ask health questions', '/ai'),
            ], isDark, cardBg, border, textPrimary, textMuted),
            const SizedBox(height: 16),
            _buildSection('Emergency & Plans', isDark, textPrimary),
            const SizedBox(height: 10),
            _buildMenuCard([
              _MenuItem('🚨', 'Emergency Card', 'Accessible without login', '/emergency'),
              _MenuItem('💎', 'Plans & Upgrade', 'Free / Premium / Family', '/plans'),
              _MenuItem('⏰', 'Reminders', 'Smart repeat alerts', '/reminders'),
            ], isDark, cardBg, border, textPrimary, textMuted),
            const SizedBox(height: 16),
            _buildSection('Security', isDark, textPrimary),
            const SizedBox(height: 10),
            _buildSecurityCard(isDark, cardBg, border, textPrimary, textMuted),
            const SizedBox(height: 16),

            // ── Test notification ──────────────────────────────
            _buildSection('Notifications', isDark, textPrimary),
            const SizedBox(height: 10),
            _buildNotifCard(isDark, cardBg, border, textPrimary, textMuted),
            const SizedBox(height: 16),

            // ── Sign out ──────────────────────────────────────
            _buildSignOut(auth, isDark),
            const SizedBox(height: 80),
          ]),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 4),
    );
  }

  Widget _buildSection(String title, bool isDark, Color textPrimary) =>
      Text(title, style: TextStyle(fontFamily: 'Fraunces', fontSize: 17, fontWeight: FontWeight.bold, color: textPrimary));

  Widget _buildProfileHero(Map<String, dynamic>? user, bool isDark) {
    final isGoogle = user?['auth_provider'] == 'google';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.navy, Color(0xFF1E3F6E), AppColors.violet],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        // Avatar
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppColors.mint.withOpacity(0.25),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.mint.withOpacity(0.4), width: 2),
          ),
          child: Center(child: Text(
            user?['name']?.toString().substring(0, 1).toUpperCase() ?? 'U',
            style: const TextStyle(fontSize: 28, fontFamily: 'Fraunces', fontWeight: FontWeight.bold, color: AppColors.mint),
          )),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user?['name'] ?? '', style: const TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 3),
          Text(user?['email'] ?? '', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
          const SizedBox(height: 8),
          Row(children: [
            if (user?['is_verified'] == true)
              _HeroBadge('✓ Verified', AppColors.mint),
            if (isGoogle) ...[
              const SizedBox(width: 6),
              _HeroBadge('G Google', Colors.white),
            ],
          ]),
        ])),
      ]),
    );
  }

  Widget _buildStatsRow(Map<String, dynamic>? user, bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    return Row(children: [
      _StatBox('BMI', user?['bmi']?.toString() ?? '—', user?['bmi_status'] ?? '', AppColors.violet, isDark, cardBg, border, textPrimary, textMuted),
      const SizedBox(width: 12),
      _StatBox('Age', user?['age']?.toString() ?? '—', 'years', AppColors.sage, isDark, cardBg, border, textPrimary, textMuted),
      const SizedBox(width: 12),
      _StatBox('Cal', user?['daily_calorie_target']?.toString() ?? '—', 'target', AppColors.gold, isDark, cardBg, border, textPrimary, textMuted),
    ]);
  }

  Widget _buildConditions(List<String> conditions, bool isDark, Color cardBg, Color border, Color textPrimary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('🏥 Health Conditions', style: TextStyle(fontFamily: 'Fraunces', fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: conditions.map((c) =>
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: AppColors.violet.withOpacity(0.1), borderRadius: BorderRadius.circular(100), border: Border.all(color: AppColors.violet.withOpacity(0.25))),
            child: Text(c, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.violet)),
          )
        ).toList()),
      ]),
    );
  }

  Widget _buildThemeCard(ThemeService theme, bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('🎨 Appearance', style: TextStyle(fontFamily: 'Fraunces', fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary)),
        const SizedBox(height: 14),
        Row(children: [
          for (final option in [
            (ThemeMode.light,  Icons.light_mode_rounded,  'Light',  AppColors.gold),
            (ThemeMode.system, Icons.phone_android_rounded,'Auto',  AppColors.sage),
            (ThemeMode.dark,   Icons.dark_mode_rounded,   'Dark',   AppColors.violet),
          ])
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => theme.setMode(option.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.mode == option.$1 ? option.$4.withOpacity(isDark ? 0.2 : 0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.mode == option.$1 ? option.$4 : border, width: theme.mode == option.$1 ? 2 : 1),
                  ),
                  child: Column(children: [
                    Icon(option.$2, size: 22, color: theme.mode == option.$1 ? option.$4 : textMuted),
                    const SizedBox(height: 4),
                    Text(option.$3, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        color: theme.mode == option.$1 ? option.$4 : textMuted)),
                  ]),
                ),
              ),
            )),
        ]),
      ]),
    );
  }

  Widget _buildMenuCard(List<_MenuItem> items, bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    return Container(
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
      child: Column(children: items.asMap().entries.map((e) {
        final i = e.key; final item = e.value;
        return InkWell(
          onTap: () => Navigator.pushNamed(context, item.route),
          borderRadius: BorderRadius.circular(i == 0 ? 18 : (i == items.length - 1 ? 18 : 0)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: i < items.length - 1 ? border : Colors.transparent))),
            child: Row(children: [
              Text(item.icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary)),
                Text(item.subtitle, style: TextStyle(fontSize: 11, color: textMuted)),
              ])),
              Icon(Icons.chevron_right_rounded, color: textMuted, size: 20),
            ]),
          ),
        );
      }).toList()),
    );
  }

  Widget _buildNotifCard(bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Test that push notifications and sounds work on your device.', style: TextStyle(fontSize: 13, color: textMuted, height: 1.5)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              await NotificationService().sendTestNotification();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🔔 Test notification sent!'), backgroundColor: AppColors.success));
            },
            child: const Text('🔔 Send Test Notification'),
          ),
        ),
      ]),
    );
  }

  Widget _buildSecurityCard(bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    final security = context.watch<SecurityService>();
    return Container(
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // PIN Lock
        _SecurityTile(
          icon: '🔒', title: 'PIN Lock',
          subtitle: security.hasPinSet ? 'PIN is set — app locks on exit' : 'Not set — tap to create PIN',
          isDark: isDark, textPrimary: textPrimary, textMuted: textMuted, border: border,
          trailing: Switch(
            value: security.hasPinSet,
            activeColor: AppColors.sage,
            onChanged: (v) async {
              if (v) {
                Navigator.pushNamed(context, '/pin-setup');
              } else {
                final ok = await showConfirmDialog(context, 'Remove PIN', 'Remove PIN lock from app?');
                if (ok) await security.removePin();
              }
            },
          ),
        ),
        // Biometric Lock
        FutureBuilder<bool>(
          future: security.isBiometricAvailable(),
          builder: (context, snap) {
            final available = snap.data ?? false;
            return _SecurityTile(
              icon: '👆', title: 'Fingerprint / Face ID',
              subtitle: !available ? 'Not available on this device' : security.biometricEnabled ? 'Biometric lock enabled' : 'Tap to enable biometric lock',
              isDark: isDark, textPrimary: textPrimary, textMuted: textMuted, border: border,
              trailing: Switch(
                value: security.biometricEnabled,
                activeColor: AppColors.sage,
                onChanged: available ? (v) async {
                  if (v) await security.enableBiometric();
                  else await security.disableBiometric();
                } : null,
              ),
            );
          },
        ),
        // Auto-lock timeout
        if (security.hasAnyLock)
          _SecurityTile(
            icon: '⏱️', title: 'Auto-Lock Timeout',
            subtitle: 'Locks after ${security.autoLockSeconds}s in background',
            isDark: isDark, textPrimary: textPrimary, textMuted: textMuted, border: border,
            trailing: DropdownButton<int>(
              value: security.autoLockSeconds,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 15,  child: Text('15s')),
                DropdownMenuItem(value: 30,  child: Text('30s')),
                DropdownMenuItem(value: 60,  child: Text('1 min')),
                DropdownMenuItem(value: 300, child: Text('5 min')),
              ],
              onChanged: (v) { if (v != null) security.setAutoLock(true, seconds: v); },
            ),
          ),
        // Lock now
        if (security.hasAnyLock)
          _SecurityTile(
            icon: '🔐', title: 'Lock App Now',
            subtitle: 'Immediately lock the app',
            isDark: isDark, textPrimary: textPrimary, textMuted: textMuted, border: Colors.transparent,
            trailing: TextButton(
              onPressed: security.lockNow,
              child: const Text('Lock', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
            ),
          ),
      ]),
    );
  }

  Widget _buildSignOut(AuthService auth, bool isDark) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          final confirm = await showConfirmDialog(context, 'Sign Out', 'Are you sure you want to sign out?');
          if (confirm && mounted) {
            await auth.logout();
            Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
          }
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: BorderSide(color: AppColors.danger.withOpacity(0.4)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ── Helper Widgets ────────────────────────────────────────────────
class _HeroBadge extends StatelessWidget {
  final String text; final Color color;
  const _HeroBadge(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(100)),
    child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
  );
}

class _StatBox extends StatelessWidget {
  final String label, value, sub; final Color color, cardBg, border, textPrimary, textMuted; final bool isDark;
  const _StatBox(this.label, this.value, this.sub, this.color, this.isDark, this.cardBg, this.border, this.textPrimary, this.textMuted);
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border),
        boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))]),
    child: Column(children: [
      Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.w700, color: color)),
      Text(sub.isNotEmpty ? sub : label, style: TextStyle(fontSize: 10, color: textMuted, fontWeight: FontWeight.w600)),
    ]),
  ));
}

class _MenuItem {
  final String icon, label, subtitle, route;
  const _MenuItem(this.icon, this.label, this.subtitle, this.route);
}

// ── Security tile widget ──────────────────────────────────────────
class _SecurityTile extends StatelessWidget {
  final String icon, title, subtitle;
  final bool isDark;
  final Color textPrimary, textMuted, border;
  final Widget trailing;
  const _SecurityTile({
    required this.icon, required this.title, required this.subtitle,
    required this.isDark, required this.textPrimary, required this.textMuted,
    required this.border, required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border, width: 0.5)),
      ),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: textMuted)),
        ])),
        trailing,
      ]),
    );
  }
}