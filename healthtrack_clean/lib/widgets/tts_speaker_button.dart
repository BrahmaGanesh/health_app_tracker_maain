// lib/widgets/tts_speaker_button.dart
// Reusable TTS speaker button for Recipe / Exercise / Breathing bottom sheets
// Tap once = speak, tap again = stop. No auto-play.
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsSpeakerButton extends StatefulWidget {
  final String text;
  const TtsSpeakerButton({super.key, required this.text});
  @override State<TtsSpeakerButton> createState() => _TtsSpeakerButtonState();
}

class _TtsSpeakerButtonState extends State<TtsSpeakerButton> with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;
  late AnimationController _pulse;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse    = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulseAnim= Tween<double>(begin: 1.0, end: 1.18).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
      _pulse.stop(); _pulse.reset();
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _speaking = false);
      _pulse.stop(); _pulse.reset();
    });
    _setup();
  }

  Future<void> _setup() async {
    await _tts.setLanguage('en-IN');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _toggle() async {
    if (_speaking) {
      await _tts.stop();
      _pulse.stop(); _pulse.reset();
      setState(() => _speaking = false);
    } else {
      setState(() => _speaking = true);
      _pulse.repeat(reverse: true);
      await _tts.speak(widget.text);
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_speaking)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(100)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 14),
            SizedBox(width: 4),
            Text('Speaking...', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      ScaleTransition(
        scale: _speaking ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
        child: GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _speaking ? const Color(0xFF1D4ED8) : const Color(0xFF142D4C),
              boxShadow: [BoxShadow(color: (_speaking ? const Color(0xFF1D4ED8) : const Color(0xFF142D4C)).withOpacity(0.4), blurRadius: 16, spreadRadius: 2)],
            ),
            child: Icon(_speaking ? Icons.stop_rounded : Icons.volume_up_rounded, color: Colors.white, size: 22),
          ),
        ),
      ),
    ]);
  }
}

// ── Shared Bottom Sheet Header ──────────────────────────────────────
class BsHeader extends StatelessWidget {
  final String? imageUrl, emoji;
  final String title;
  final Widget? badge;
  const BsHeader({super.key, this.imageUrl, this.emoji, required this.title, this.badge});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Drag handle
      Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
      // Hero image or emoji
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: imageUrl != null
            ? Image.network(imageUrl!, width: double.infinity, height: 200, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _EmojiBanner(emoji ?? '🍽️'))
            : _EmojiBanner(emoji ?? '🍽️'),
      ),
      const SizedBox(height: 16),
      if (badge != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: badge!),
      Text(title, style: TextStyle(fontFamily: 'Fraunces', fontSize: 22, fontWeight: FontWeight.w900,
          color: isDark ? Colors.white : const Color(0xFF142D4C))),
    ]);
  }
}

class _EmojiBanner extends StatelessWidget {
  final String emoji;
  const _EmojiBanner(this.emoji);
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, height: 200,
    decoration: BoxDecoration(gradient: LinearGradient(colors: [const Color(0xFF142D4C), const Color(0xFF4F3B78)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 72))),
  );
}

// ── Nutrition macro chip ────────────────────────────────────────────
class MacroChip extends StatelessWidget {
  final String label, value; final Color color;
  const MacroChip({super.key, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(isDark ? 0.2 : 0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color.withOpacity(0.8))),
      ]),
    );
  }
}

// ── Difficulty chip ─────────────────────────────────────────────────
class DifficultyChip extends StatelessWidget {
  final String difficulty;
  const DifficultyChip({super.key, required this.difficulty});
  static const _colors = {'easy':Color(0xFF22C55E),'beginner':Color(0xFF22C55E),'medium':Color(0xFFF59E0B),'moderate':Color(0xFFF59E0B),'hard':Color(0xFFEF4444),'advanced':Color(0xFFEF4444)};
  @override
  Widget build(BuildContext context) {
    final color = _colors[difficulty.toLowerCase()] ?? const Color(0xFF6B7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(100), border: Border.all(color: color.withOpacity(0.3))),
      child: Text(difficulty[0].toUpperCase() + difficulty.substring(1), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ── Info row ────────────────────────────────────────────────────────
class InfoRow extends StatelessWidget {
  final String icon, label, value;
  const InfoRow({super.key, required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Text('$label:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black54)),
        const SizedBox(width: 6),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87))),
      ]),
    );
  }
}

// ── Section title ───────────────────────────────────────────────────
class BsSection extends StatelessWidget {
  final String title;
  final Widget child;
  const BsSection({super.key, required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 20),
      Text(title, style: TextStyle(fontFamily: 'Fraunces', fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF142D4C))),
      const SizedBox(height: 10),
      child,
    ]);
  }
}

// ── Animated progress bar for nutrition ────────────────────────────
class AnimatedNutritionBar extends StatelessWidget {
  final String label; final double value, max; final Color color; final String unit;
  const AnimatedNutritionBar({super.key, required this.label, required this.value, required this.max, required this.color, required this.unit});
  @override
  Widget build(BuildContext context) {
    final pct = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF142D4C))),
          Text('${value.toInt()} / ${max.toInt()} $unit', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black45, fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: pct),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: color.withOpacity(0.12), color: color),
          ),
        ),
      ]),
    );
  }
}