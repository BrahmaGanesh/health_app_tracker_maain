// ============================================================
// lib/screens/profile_screen.dart — User Profile & Settings
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/common_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    final conditions = auth.conditions;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: const Text('Profile', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold))),
      body: RefreshIndicator(
        onRefresh: auth.refreshUser,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileHero(user),
              const SizedBox(height: 20),
              if (conditions.isNotEmpty) _buildConditionsCard(conditions),
              if (conditions.isNotEmpty) const SizedBox(height: 16),
              _buildStatsCard(user),
              const SizedBox(height: 16),
              _buildMenuSection(auth),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 4),
    );
  }

  Widget _buildProfileHero(Map<String, dynamic>? user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.navy, Color(0xFF1E3F6E)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: AppColors.mint.withOpacity(0.2),
            child: Text(user?['name']?.toString().substring(0, 1).toUpperCase() ?? 'U', style: const TextStyle(fontSize: 28, fontFamily: 'Fraunces', fontWeight: FontWeight.bold, color: AppColors.mint)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user?['name'] ?? '', style: const TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                Text(user?['email'] ?? '', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7))),
                const SizedBox(height: 6),
                if (user?['is_verified'] == true)
                  PillChip(text: '✓ Verified', color: AppColors.mint, bgColor: AppColors.mint.withOpacity(0.15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionsCard(List<String> conditions) {
    return SectionCard(
      title: '🏥 Health Conditions',
      child: Wrap(
        spacing: 8, runSpacing: 6,
        children: conditions.map((c) => PillChip(text: c, color: AppColors.violet)).toList(),
      ),
    );
  }

  Widget _buildStatsCard(Map<String, dynamic>? user) {
    return SectionCard(
      title: '📊 Your Stats',
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Text(user?['bmi']?.toString() ?? '—', style: const TextStyle(fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.violet)),
                Text(user?['bmi_status'] ?? 'BMI', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(user?['age']?.toString() ?? '—', style: const TextStyle(fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.sage)),
                const Text('Age', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(user?['daily_calorie_target']?.toString() ?? '—', style: const TextStyle(fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.gold)),
                const Text('Cal Target', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuSection(AuthService auth) {
    final menuItems = [
      _MenuItem(icon: '🔔', label: 'Reminders', subtitle: 'Sound alerts with repeat', route: '/reminders'),
      _MenuItem(icon: '👨‍👩‍👧', label: 'Family Health', subtitle: 'Manage family members', route: '/family'),
      _MenuItem(icon: '📊', label: 'Analytics', subtitle: 'Trends and predictions', route: '/analytics'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Quick Links', style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navy)),
        ),
        ...menuItems.map((item) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Text(item.icon, style: const TextStyle(fontSize: 22)),
            title: Text(item.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(item.subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: () => Navigator.pushNamed(context, item.route),
          ),
        )),
        const SizedBox(height: 16),
        SectionCard(
          title: '🔔 Test Notifications',
          child: Column(
            children: [
              const Text('Verify that push notifications and sounds are working on your device.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await NotificationService().sendTestNotification();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔔 Test notification sent!'), backgroundColor: AppColors.success));
                  },
                  child: const Text('🔔 Send Test Notification'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: const Color(0xFFFEE2E2),
          child: ListTile(
            leading: const Text('🚪', style: TextStyle(fontSize: 22)),
            title: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
            onTap: () async {
              final confirm = await showConfirmDialog(context, 'Sign Out', 'Are you sure you want to sign out?');
              if (confirm && mounted) {
                await auth.logout();
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _MenuItem {
  final String icon, label, subtitle, route;
  const _MenuItem({required this.icon, required this.label, required this.subtitle, required this.route});
}