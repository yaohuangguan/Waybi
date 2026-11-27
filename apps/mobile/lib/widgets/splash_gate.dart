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

  /// The splash backgrounds, matching the native launch screens: keep in
  /// sync with android/.../values(-night)/colors.xml and the iOS
  /// LaunchBackground color set (test/startup_handoff_test.dart checks).
  static const lightBackground = WaybiColors.lightBackground;
  static const darkBackground = WaybiColors.midnightOcean;

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
    // The native launch screens follow the system appearance (iOS
    // LaunchBackground color set, Android values-night), not the app's own
    // theme setting, so the splash does too: one splash, no flash.
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 360),
      child: _ready
          ? KeyedSubtree(key: const ValueKey('waybi-map'), child: widget.child)
          : Scaffold(
              key: const ValueKey('waybi-splash'),
              backgroundColor: dark
                  ? SplashGate.darkBackground
                  : SplashGate.lightBackground,
              body: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const WaybiBird(size: 136),
                      const SizedBox(height: 22),
                      Text(
                        'Waybi',
                        style: TextStyle(
                          color: dark
                              ? WaybiColors.darkText
                              : WaybiColors.deepOcean,
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        zh ? '遇见 Waybi，找到你的路。' : 'Meet Waybi. Find your way.',
                        style: TextStyle(
                          color: dark
                              ? WaybiColors.darkTextSecondary
                              : WaybiColors.lightTextSecondary,
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
