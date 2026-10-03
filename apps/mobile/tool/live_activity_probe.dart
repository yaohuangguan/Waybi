// Simulator-only entrypoint for exercising the production ActivityKit bridge.
// Production builds continue to use lib/main.dart.
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:waybi_mobile/drive/system_navigation.dart';

void main() => runApp(const MaterialApp(home: LiveActivityProbe()));

class LiveActivityProbe extends StatefulWidget {
  const LiveActivityProbe({super.key});
  @override
  State<LiveActivityProbe> createState() => _LiveActivityProbeState();
}

class _LiveActivityProbeState extends State<LiveActivityProbe> {
  final navigation = SystemNavigation();
  Timer? timer;
  int metres = 240;
  bool reliable = true;
  Map<String, Object?> get state => {
    'destination': 'Foodie · Westgate',
    'language': 'zh',
    'instruction': '右转进入 Northside Drive',
    'distance': '$metres 米',
    'remaining': '1.2 公里',
    'seconds': 240,
    'maneuver': 'arrow.turn.up.right',
    'gpsReliable': reliable,
    'offRoute': false,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await navigation.start(state);
      timer = Timer.periodic(const Duration(seconds: 3), (_) {
        metres = (metres - 5).clamp(30, 240);
        unawaited(navigation.update(state));
      });
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    unawaited(navigation.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Live Activity simulator check')),
    body: AnimatedBuilder(
      animation: navigation,
      builder: (context, _) => Column(
        children: [
          Text(
            'Active: ${navigation.surfaceActive} · Enabled: ${navigation.enabled}',
          ),
          Text(navigation.failureReason ?? 'No native errors'),
          FilledButton(
            onPressed: () async {
              reliable = !reliable;
              await navigation.update(state, force: true);
            },
            child: const Text('Toggle GPS quality'),
          ),
          TextButton(
            onPressed: () => navigation.stop(),
            child: const Text('End activity'),
          ),
        ],
      ),
    ),
  );
}
