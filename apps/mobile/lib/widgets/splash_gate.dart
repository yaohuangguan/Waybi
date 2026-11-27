import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/waybi_theme.dart';
import 'waybi_bird.dart';
import 'waybi_format.dart';

class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child, this.language});
  final Widget child;

  /// `en` or `zh`; defaults to the app locale.
  final String? language;

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
  Widget build(BuildContext context) {
    final zh = waybiLanguageOf(context, widget.language) == 'zh';
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 360),
      child: _ready
          ? KeyedSubtree(key: const ValueKey('waybi-map'), child: widget.child)
          // Matches the native launch screens (light in both themes on iOS
          // and Android), so there is a single splash rather than a
          // light-to-dark flash. A dark splash needs night launch resources.
          : Scaffold(
              key: const ValueKey('waybi-splash'),
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
                      Text(
                        zh ? '遇见 Waybi，找到你的路。' : 'Meet Waybi. Find your way.',
                        style: const TextStyle(
                          color: WaybiColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
