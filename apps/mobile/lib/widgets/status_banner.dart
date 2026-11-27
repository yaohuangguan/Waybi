import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../theme/waybi_theme.dart';

class WaybiStatusBanner extends StatefulWidget {
  const WaybiStatusBanner({
    super.key,
    required this.message,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
    this.dismissLabel = 'Dismiss',
  });

  final String message;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String dismissLabel;

  @override
  State<WaybiStatusBanner> createState() => _WaybiStatusBannerState();
}

/// How long a notice stays: at least 4 s, plus reading time for longer
/// messages, at most 12 s.
Duration statusBannerDuration(String message) => Duration(
  milliseconds: (1500 + message.characters.length * 70).clamp(4000, 12000),
);

class _WaybiStatusBannerState extends State<WaybiStatusBanner> {
  Timer? _timer;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_scheduled) {
      _scheduled = true;
      _scheduleDismiss();
      _announce();
    }
  }

  @override
  void didUpdateWidget(WaybiStatusBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        (oldWidget.onAction == null) != (widget.onAction == null)) {
      _scheduleDismiss();
      if (oldWidget.message != widget.message) _announce();
    }
  }

  void _scheduleDismiss() {
    _timer?.cancel();
    _timer = null;
    _resume();
  }

  /// (Re)starts the countdown. Location recovery actions stay visible until
  /// fixed or dismissed, and screen-reader users dismiss notices themselves.
  void _resume() {
    if (_timer != null ||
        widget.onAction != null ||
        MediaQuery.accessibleNavigationOf(context)) {
      return;
    }
    _timer = Timer(
      statusBannerDuration(widget.message),
      () => widget.onDismiss(),
    );
  }

  /// Touching the banner pauses it; releasing gives a full reading time.
  void _pause() {
    _timer?.cancel();
    _timer = null;
  }

  void _announce() {
    // Android announces the live region; iOS VoiceOver needs an explicit
    // announcement for a banner that appears without focus.
    if (defaultTargetPlatform != TargetPlatform.iOS ||
        !MediaQuery.supportsAnnounceOf(context)) {
      return;
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      widget.message,
      Directionality.of(context),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 76, 20, 0),
        child: PointerInterceptor(
          child: Listener(
            onPointerDown: (_) => _pause(),
            onPointerUp: (_) => _resume(),
            onPointerCancel: (_) => _resume(),
            child: Semantics(
              liveRegion: true,
              child: Material(
                color: WaybiInk.surface.withValues(alpha: .96),
                elevation: 8,
                borderRadius: BorderRadius.circular(15),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 9, 5, 9),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: WaybiInk.accent,
                            size: 19,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              widget.message,
                              style: const TextStyle(
                                color: WaybiInk.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: widget.dismissLabel,
                            onPressed: widget.onDismiss,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: WaybiInk.muted,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                      if (widget.onAction != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: widget.onAction,
                            style: TextButton.styleFrom(
                              foregroundColor: WaybiInk.accent,
                            ),
                            child: Text(widget.actionLabel ?? 'Retry'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
