import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'bag_page.dart';
import 'friend_strings.dart';
import 'game_controller.dart';
import 'game_session.dart';
import 'journal_page.dart';
import 'postcard_dialog.dart';
import 'room_page.dart';
import 'theme.dart';

class WaybisWayHomeApp extends StatelessWidget {
  const WaybisWayHomeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: "Waybi's Way Home",
    theme: buildWaybiTheme(),
    supportedLocales: const [Locale('en'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const GameShell(),
  );
}

class GameShell extends StatefulWidget {
  const GameShell({super.key, this.embedded = false, this.controller});
  final bool embedded;
  final GameController? controller;
  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  late final GameSession session;
  GameController get controller => session.controller;
  int index = 0;
  Timer? _returnTimer;
  bool showingReturn = false;

  @override
  void initState() {
    super.initState();
    session = GameSession(
      controller:
          widget.controller ??
          (widget.embedded ? GameController.embedded : null),
      saveKey: widget.embedded ? 'waybi_friends_v1' : 'waybis_way_home_v1',
    );
    session.ownsController = widget.controller == null && !widget.embedded;
    session.addListener(_changed);
    session.start();
  }

  bool get _roomVisible =>
      session.foreground &&
      index == 0 &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _scheduleReturn();
  }

  void _scheduleReturn() {
    if (!mounted ||
        !_roomVisible ||
        controller.latestReturn == null ||
        showingReturn ||
        _returnTimer != null) {
      return;
    }
    final arrivedAt = controller.roomLife.arrivedAt;
    final elapsed = arrivedAt == null
        ? 4000
        : controller.clock().difference(arrivedAt).inMilliseconds;
    _returnTimer = Timer(
      Duration(milliseconds: (4000 - elapsed).clamp(0, 4000)),
      () {
        _returnTimer = null;
        if (!mounted || !_roomVisible || showingReturn) return;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || !_roomVisible || showingReturn) return;
          final latest = controller.takeLatestReturn();
          if (latest == null) return;
          showingReturn = true;
          await showPostcardDialog(context, latest);
          showingReturn = false;
        });
        // A delayed callback needs a frame even when reduced motion is enabled.
        WidgetsBinding.instance.scheduleFrame();
      },
    );
  }

  Future<void> _openPage(Widget page, String title) async {
    final locale = Localizations.localeOf(context);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) => Localizations.override(
          context: pageContext,
          locale: locale,
          child: Theme(
            data: buildWaybiTheme(),
            child: Scaffold(
              appBar: AppBar(title: Text(title)),
              body: SafeArea(
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (_, _) => page,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) _scheduleReturn();
  }

  void _select(int value) {
    setState(() => index = value);
    _scheduleReturn();
  }

  @override
  void dispose() {
    _returnTimer?.cancel();
    session.removeListener(_changed);
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (session.error != null && !controller.ready) {
      return Scaffold(
        appBar: widget.embedded
            ? AppBar(title: const Text('Waybi & Friends'))
            : null,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(friendText(context, "Couldn't open the room.", '暂时没能打开小屋。')),
              TextButton(
                onPressed: session.load,
                child: Text(friendText(context, 'Try again', '重试')),
              ),
            ],
          ),
        ),
      );
    }
    if (!controller.ready) {
      return Scaffold(
        appBar: widget.embedded
            ? AppBar(title: const Text('Waybi & Friends'))
            : null,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'packages/waybi_friends/assets/characters/waybi.png',
                width: 92,
              ),
              const SizedBox(height: 18),
              Text(friendText(context, 'Finding the way home…', '正在回到小屋…')),
            ],
          ),
        ),
      );
    }
    final visible =
        session.foreground && (ModalRoute.of(context)?.isCurrent ?? true);
    if (widget.embedded) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Waybi & Friends'),
          actions: [
            IconButton(
              tooltip: friendText(context, 'Journal', '旅行册'),
              onPressed: () => _openPage(
                JournalPage(controller: controller),
                friendText(context, 'Journal', '旅行册'),
              ),
              icon: const Icon(Icons.auto_stories_rounded),
            ),
            IconButton(
              tooltip: friendText(context, 'Bag', '背包'),
              onPressed: () => _openPage(
                BagPage(controller: controller),
                friendText(context, 'Bag', '背包'),
              ),
              icon: const Icon(Icons.backpack_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: TickerMode(
            enabled: visible,
            child: RoomPage(
              controller: controller,
              showHeader: false,
              showPrototypeControls: false,
            ),
          ),
        ),
      );
    }
    final pages = [
      RoomPage(controller: controller),
      JournalPage(controller: controller),
      BagPage(controller: controller),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: index,
          children: [
            for (var i = 0; i < pages.length; i++)
              TickerMode(enabled: visible && index == i, child: pages[i]),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: WwhColors.paper,
            border: Border(top: BorderSide(color: Color(0x1A23351D))),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
          child: Row(
            children: [
              _NavItem(
                label: friendText(context, 'Home', '小屋'),
                icon: Icons.home_rounded,
                selected: index == 0,
                onTap: () => _select(0),
              ),
              _NavItem(
                label: friendText(context, 'Journal', '旅行册'),
                icon: Icons.auto_stories_rounded,
                selected: index == 1,
                onTap: () => _select(1),
              ),
              _NavItem(
                label: friendText(context, 'Bag', '背包'),
                icon: Icons.backpack_rounded,
                selected: index == 2,
                onTap: () => _select(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? WwhColors.lime.withValues(alpha: .55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 23,
                color: selected ? WwhColors.moss : WwhColors.muted,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? WwhColors.ink : WwhColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
