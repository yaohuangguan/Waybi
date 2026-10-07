import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/waybi_theme.dart';
import 'waybi_bird.dart';

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
        ? KeyedSubtree(key: const ValueKey('waybi-map'), child: widget.child)
        : Scaffold(
            key: ValueKey('waybi-splash'),
            backgroundColor: WaybiColors.lightBackground,
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const WaybiBird(size: 136),
                    const SizedBox(height: 22),
                    const Text(
                      'Waybi',
                      style: TextStyle(
                        color: WaybiColors.deepOcean,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Meet Waybi. Find your way.',
                      style: TextStyle(color: WaybiColors.lightTextSecondary),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Map data © OpenStreetMap contributors',
                      style: TextStyle(
                        color: WaybiColors.lightTextSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
