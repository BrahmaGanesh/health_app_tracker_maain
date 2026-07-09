// lib/screens/lock_screen.dart — App Lock (PIN / Biometric)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_theme.dart';
import '../services/security_service.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with SingleTickerProviderStateMixin {
  final _security = SecurityService();
  String _pin = '';
  String? _error;
  bool _checking = false;
  late AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    if (_security.biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  @override
  void dispose() { _shakeCtrl.dispose(); super.dispose(); }

  Future<void> _tryBiometric() async {
    final ok = await _security.authenticateWithBiometric();
    if (ok && mounted) widget.onUnlocked();
  }

  void _onDigit(String d) {
    if (_pin.length >= 6) return;
    setState(() { _pin += d; _error = null; });
    if (_pin.length == 6) _verify();
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _checking = true);
    final ok = await _security.verifyPin(_pin);
    setState(() => _checking = false);

    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() { _error = 'Incorrect PIN'; _pin = ''; });
      HapticFeedback.heavyImpact();
      _shakeCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 50),
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.mint, AppColors.sage]),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: AppColors.mint.withOpacity(0.3), blurRadius: 24, spreadRadius: 2)],
                ),
                child: const Center(child: Text('🔒', style: TextStyle(fontSize: 32))),
              ),
              const SizedBox(height: 24),
              const Text('HealthTrack Locked', style: TextStyle(fontFamily: 'Fraunces', fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 6),
              Text('Enter your PIN to continue', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6))),
              const SizedBox(height: 40),

              // PIN dots with shake animation
              AnimatedBuilder(
                animation: _shakeCtrl,
                builder: (context, child) {
                  final offset = _shakeCtrl.value == 0 ? 0.0 : (4 * (1 - _shakeCtrl.value)) * (_shakeCtrl.value * 30 % 2 == 0 ? 1 : -1);
                  return Transform.translate(offset: Offset(offset, 0), child: child);
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    final filled = i < _pin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? AppColors.mint : Colors.transparent,
                        border: Border.all(color: _error != null ? AppColors.danger : AppColors.mint, width: 1.5),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(height: 20, child: _error != null
                  ? Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 13))
                  : (_checking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mint)) : const SizedBox())),

              const Spacer(),

              // Number pad
              _NumberPad(onDigit: _onDigit, onBackspace: _onBackspace, showBiometric: _security.biometricEnabled, onBiometric: _tryBiometric),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberPad extends StatelessWidget {
  final Function(String) onDigit;
  final VoidCallback onBackspace;
  final bool showBiometric;
  final VoidCallback onBiometric;
  const _NumberPad({required this.onDigit, required this.onBackspace, required this.showBiometric, required this.onBiometric});

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, {VoidCallback? onTap, Widget? child}) {
      return GestureDetector(
        onTap: onTap ?? () => onDigit(label),
        child: Container(
          width: 72, height: 72,
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.08)),
          child: Center(child: child ?? Text(label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Colors.white))),
        ),
      );
    }

    return Column(
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [btn('1'), btn('2'), btn('3')]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [btn('4'), btn('5'), btn('6')]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [btn('7'), btn('8'), btn('9')]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          showBiometric
              ? btn('', onTap: onBiometric, child: const Icon(Icons.fingerprint_rounded, color: AppColors.mint, size: 30))
              : const SizedBox(width: 88),
          btn('0'),
          btn('', onTap: onBackspace, child: const Icon(Icons.backspace_outlined, color: Colors.white70, size: 22)),
        ]),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// PIN SETUP SCREEN — first-time PIN creation
// ════════════════════════════════════════════════════════════════
class PinSetupScreen extends StatefulWidget {
  final VoidCallback onDone;
  const PinSetupScreen({super.key, required this.onDone});
  @override State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final _security = SecurityService();
  String _pin = '', _confirmPin = '';
  bool _confirming = false;
  String? _error;

  void _onDigit(String d) {
    if (!_confirming) {
      if (_pin.length >= 6) return;
      setState(() { _pin += d; _error = null; });
      if (_pin.length == 6) setState(() => _confirming = true);
    } else {
      if (_confirmPin.length >= 6) return;
      setState(() { _confirmPin += d; _error = null; });
      if (_confirmPin.length == 6) _finish();
    }
  }

  void _onBackspace() {
    setState(() {
      if (_confirming) {
        if (_confirmPin.isNotEmpty) _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
      } else if (_pin.isNotEmpty) {
        _pin = _pin.substring(0, _pin.length - 1);
      }
    });
  }

  Future<void> _finish() async {
    if (_pin == _confirmPin) {
      await _security.setPin(_pin);
      widget.onDone();
    } else {
      setState(() { _error = 'PINs don\'t match. Try again.'; _confirming = false; _pin = ''; _confirmPin = ''; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _confirming ? _confirmPin : _pin;
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 50),
          const Text('🔒', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 20),
          Text(_confirming ? 'Confirm Your PIN' : 'Create a 6-Digit PIN',
              style: const TextStyle(fontFamily: 'Fraunces', fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 8),
          Text(_confirming ? 'Enter the same PIN again' : 'This protects your health data',
              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6))),
          const SizedBox(height: 40),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(6, (i) {
            final filled = i < current.length;
            return Container(margin: const EdgeInsets.symmetric(horizontal: 6), width: 16, height: 16,
                decoration: BoxDecoration(shape: BoxShape.circle, color: filled ? AppColors.mint : Colors.transparent,
                    border: Border.all(color: AppColors.mint, width: 1.5)));
          })),
          const SizedBox(height: 12),
          SizedBox(height: 20, child: _error != null ? Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600)) : null),
          const Spacer(),
          _NumberPad(onDigit: _onDigit, onBackspace: _onBackspace, showBiometric: false, onBiometric: () {}),
          const SizedBox(height: 24),
        ]),
      )),
    );
  }
}