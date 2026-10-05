import 'package:flutter/material.dart';

import '../data/navigation_feedback_repository.dart';

class NavigationFeedbackCard extends StatefulWidget {
  const NavigationFeedbackCard({
    super.key,
    required this.tripId,
    required this.language,
    this.repository,
  });
  final String tripId, language;
  final NavigationFeedbackRepository? repository;
  @override
  State<NavigationFeedbackCard> createState() => _NavigationFeedbackCardState();
}

class _NavigationFeedbackCardState extends State<NavigationFeedbackCard> {
  late final repository = widget.repository ?? NavigationFeedbackRepository();
  int? vote;
  bool ready = false;
  String t(String en, String zh) => widget.language == 'zh' ? zh : en;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await repository.voteFor(widget.tripId);
    if (mounted) {
      setState(() {
        vote = saved;
        ready = true;
      });
    }
  }

  Future<void> _vote(int value) async {
    if (!ready || vote != null) return;
    setState(() => vote = value);
    try {
      await repository.vote(widget.tripId, value);
    } catch (_) {
      if (mounted) {
        setState(() => vote = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('Could not save your vote. Try again.', '暂时没能保存评价，请再试一次。'),
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    if (widget.repository == null) repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            vote == null
                ? t('How was this navigation?', '这次导航好用吗？')
                : t('Thanks for your feedback!', '谢谢你的评价！'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        for (final value in [1, -1])
          Semantics(
            selected: vote == value,
            child: IconButton.filledTonal(
              key: ValueKey(
                value == 1 ? 'navigation-like' : 'navigation-dislike',
              ),
              onPressed: ready && vote == null ? () => _vote(value) : null,
              tooltip: value == 1
                  ? t('Helpful', '好用')
                  : t('Needs improvement', '需要改进'),
              icon: Icon(
                value == 1
                    ? (vote == value ? Icons.thumb_up : Icons.thumb_up_outlined)
                    : (vote == value
                          ? Icons.thumb_down
                          : Icons.thumb_down_outlined),
              ),
            ),
          ),
      ],
    ),
  );
}
