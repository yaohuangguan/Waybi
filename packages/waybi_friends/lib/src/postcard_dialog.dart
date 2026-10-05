import 'package:flutter/material.dart';

import 'journey_engine.dart';
import 'models.dart';
import 'theme.dart';
import 'friend_strings.dart';
import 'souvenir_collection.dart';

Future<void> showPostcardDialog(
  BuildContext context,
  JourneyMemory memory,
) async {
  final locale = Localizations.localeOf(context);
  final destination = destinationById(memory.destinationId);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: friendText(context, 'Close postcard', '关闭明信片'),
    barrierColor: const Color(0x990F190D),
    transitionDuration: const Duration(milliseconds: 360),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Localizations.override(
        context: context,
        locale: locale,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Material(
                color: Colors.transparent,
                child: _Postcard(memory: memory, destination: destination),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .88, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _Postcard extends StatelessWidget {
  const _Postcard({required this.memory, required this.destination});

  final JourneyMemory memory;
  final Destination destination;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Container(
        decoration: BoxDecoration(
          color: WwhColors.paper,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 40,
              offset: Offset(0, 18),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _PostcardScene(destination: destination, memory: memory),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            memoryTitle(context, memory),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: WwhColors.lime.withValues(alpha: .55),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            memory.countryCode ??
                                friendText(
                                  context,
                                  destination.area,
                                  destination.area == 'Auckland'
                                      ? '奥克兰'
                                      : destination.area == 'Hauraki Gulf'
                                      ? '豪拉基湾'
                                      : destination.area == 'Waitākere'
                                      ? '怀塔克雷'
                                      : '',
                                ),
                            style: const TextStyle(
                              color: WwhColors.ink,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      memoryStory(context, memory),
                      style: const TextStyle(
                        color: WwhColors.ink,
                        fontSize: 15,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SouvenirReward(memory: memory),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: WwhColors.ink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: Text(
                          friendText(context, 'Put it in the journal', '放进旅行册'),
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostcardScene extends StatelessWidget {
  const _PostcardScene({required this.destination, required this.memory});
  final JourneyMemory memory;

  final Destination destination;

  List<Color> get colors {
    switch (destination.id) {
      case 'mission_bay':
      case 'takapuna':
        return const [Color(0xFFBFE4E6), Color(0xFF5FA1B0)];
      case 'waiheke':
        return const [Color(0xFFD8E9D0), Color(0xFF73A082)];
      case 'piha':
        return const [Color(0xFFEBC4A9), Color(0xFF7D7A72)];
      case 'mt_eden':
        return const [Color(0xFFD8E8C3), Color(0xFF78955F)];
      default:
        return const [Color(0xFFE4E8C7), Color(0xFF91AA72)];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 24,
            top: 24,
            child: Transform.rotate(
              angle: .08,
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: WwhColors.paper.withValues(alpha: .9),
                  border: Border.all(
                    color: WwhColors.ink.withValues(alpha: .16),
                  ),
                ),
                child: Image.asset(
                  'packages/waybi_friends/assets/souvenirs/stamp.png',
                  width: 44,
                  height: 44,
                  semanticLabel: 'Postcard stamp',
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 10,
            child: Image.asset(
              'packages/waybi_friends/assets/characters/${memory.traveller.name}.png',
              width: 145,
              filterQuality: FilterQuality.high,
            ),
          ),
          Positioned(
            left: 165,
            bottom: 35,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friendText(context, 'A LITTLE POSTCARD FROM', '来自旅途的小明信片'),
                  style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  memoryPlace(context, memory),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    height: 1.02,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.6,
                    shadows: [Shadow(color: Color(0x33000000), blurRadius: 12)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
