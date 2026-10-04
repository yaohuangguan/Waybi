import 'package:flutter/material.dart';

import 'journey_engine.dart';
import 'models.dart';
import 'theme.dart';

Future<void> showPostcardDialog(
  BuildContext context,
  JourneyMemory memory,
) async {
  final destination = destinationById(memory.destinationId);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close postcard',
    barrierColor: const Color(0x990F190D),
    transitionDuration: const Duration(milliseconds: 360),
    pageBuilder: (context, animation, secondaryAnimation) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Material(
              color: Colors.transparent,
              child: _Postcard(memory: memory, destination: destination),
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
              _PostcardScene(destination: destination),
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
                            memory.title,
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
                            destination.area,
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
                      memory.story,
                      style: const TextStyle(
                        color: WwhColors.ink,
                        fontSize: 15,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3EBDD),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Row(
                        children: [
                          const Text('🎒', style: TextStyle(fontSize: 24)),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              'Waybi brought home ${memory.souvenir}.',
                              style: const TextStyle(
                                color: WwhColors.ink,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                        child: const Text(
                          'Put it in the journal',
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
  const _PostcardScene({required this.destination});

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
                child: Text(
                  destination.emoji,
                  style: const TextStyle(fontSize: 34),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 10,
            child: Image.asset(
              'packages/waybi_friends/assets/characters/waybi.png',
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
                const Text(
                  'A LITTLE POSTCARD FROM',
                  style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  destination.name,
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
