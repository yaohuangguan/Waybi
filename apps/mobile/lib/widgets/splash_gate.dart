import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/kiwi_lens_theme.dart';
import 'kiwi_mascot.dart';

class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});
  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  Timer? _timer;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1050), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 360),
    child: _ready
        ? KeyedSubtree(key: const ValueKey('kiwi-map'), child: widget.child)
        : Scaffold(
            key: ValueKey('kiwi-splash'),
            backgroundColor: KiwiLensColors.lightBackground,
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const KiwiMascot(size: 136),
                    const SizedBox(height: 22),
                    const Text(
                      'Kiwi Lens',
                      style: TextStyle(
                        color: KiwiLensColors.deepOcean,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'A little kiwi. A clearer journey.',
                      style: TextStyle(
                        color: KiwiLensColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
