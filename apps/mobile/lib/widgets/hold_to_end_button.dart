import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/waybi_theme.dart';

/// The one pattern Waybi uses to end an active trip: press and hold.
///
/// A brief tap never ends navigation; it shows [holdHint] instead. Holding for
/// [holdDuration] fills the button and then calls [onEnd]. Screen-reader users
/// get a confirmation dialog on activation (and the long-press action ends
/// directly), so nobody has to perform a timed gesture blind.
class HoldToEndButton extends StatefulWidget {
  const HoldToEndButton({
    super.key,
    required this.label,
    required this.holdHint,
    required this.confirmTitle,
    required this.confirmAction,
    required this.cancelAction,
    required this.onEnd,
    this.icon = Icons.stop_rounded,
    this.compact = false,
    this.onInk = false,
    this.holdDuration = const Duration(milliseconds: 900),
  });

  /// Visible label ("End") and semantic label.
  final String label;

  /// Shown after a short tap and read as the semantic hint ("Hold to end").
  final String holdHint;
  final String confirmTitle;
  final String confirmAction;
  final String cancelAction;
  final VoidCallback onEnd;
  final IconData icon;

  /// A round 48 dp icon button instead of a labelled pill.
  final bool compact;

  /// Drawn on an always-dark guidance surface ([WaybiInk]).
  final bool onInk;
  final Duration holdDuration;

  @override
  State<HoldToEndButton> createState() => _HoldToEndButtonState();
}

class _HoldToEndButtonState extends State<HoldToEndButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  )..addStatusListener(_statusChanged);
  final _tooltip = GlobalKey<TooltipState>();
  bool _showHint = false;
  bool _ended = false;

  @override
  void didUpdateWidget(covariant HoldToEndButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _progress.duration = widget.holdDuration;
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _statusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || _ended) return;
    _ended = true;
    HapticFeedback.heavyImpact();
    widget.onEnd();
  }

  void _pressStart() {
    _ended = false;
    if (_showHint) setState(() => _showHint = false);
    _progress.forward(from: 0);
  }

  void _pressCancel() {
    if (_ended) return;
    _progress.stop();
    _progress.value = 0;
  }

  void _released() {
    if (_ended) return;
    _pressCancel();
    HapticFeedback.selectionClick();
    setState(() => _showHint = true);
    // The pill shows the hint as its label; the round button has no room.
    if (widget.compact) _tooltip.currentState?.ensureTooltipVisible();
  }

  Future<void> _confirm() async {
    final end = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.confirmTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(widget.cancelAction),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(widget.confirmAction),
          ),
        ],
      ),
    );
    if (end == true && mounted) widget.onEnd();
  }

  void _semanticTap() {
    if (MediaQuery.accessibleNavigationOf(context)) {
      _confirm();
    } else {
      setState(() => _showHint = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = context.status;
    final background = widget.onInk ? WaybiInk.raised : status.danger;
    final foreground = widget.onInk ? WaybiInk.text : status.onDanger;
    final fill = widget.onInk
        ? WaybiInk.danger.withValues(alpha: .55)
        : status.onDanger.withValues(alpha: .28);
    final text = _showHint ? widget.holdHint : widget.label;

    final Widget face = widget.compact
        ? SizedBox.square(
            dimension: WaybiTouch.minTarget,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _progress,
                  builder: (context, _) => CircularProgressIndicator(
                    value: _progress.value,
                    strokeWidth: 3,
                    color: widget.onInk ? WaybiInk.danger : status.danger,
                    backgroundColor: Colors.transparent,
                  ),
                ),
                Icon(widget.icon, color: foreground, size: 24),
              ],
            ),
          )
        : ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: WaybiTouch.minTarget,
              minWidth: 72,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _progress,
                    builder: (context, _) => FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: _progress.value,
                      child: ColoredBox(color: fill),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.icon, color: foreground, size: 20),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: foreground,
                            fontSize: WaybiTextSize.body,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

    return Semantics(
      button: true,
      label: widget.label,
      hint: widget.holdHint,
      onTap: _semanticTap,
      onLongPress: widget.onEnd,
      excludeSemantics: true,
      // Manual trigger: a long-press tooltip would win the gesture arena and
      // cancel the hold.
      child: Tooltip(
        key: _tooltip,
        message: widget.holdHint,
        triggerMode: TooltipTriggerMode.manual,
        excludeFromSemantics: true,
        child: Material(
          color: widget.compact && widget.onInk
              ? Colors.transparent
              : background,
          shape: widget.compact
              ? const CircleBorder()
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _pressStart(),
            onTapUp: (_) => _released(),
            onTapCancel: _pressCancel,
            child: face,
          ),
        ),
      ),
    );
  }
}
