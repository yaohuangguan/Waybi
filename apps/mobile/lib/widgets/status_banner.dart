import 'dart:async';

import 'package:flutter/material.dart';
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

class _WaybiStatusBannerState extends State<WaybiStatusBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleDismiss();
  }

  @override
  void didUpdateWidget(WaybiStatusBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        (oldWidget.onAction == null) != (widget.onAction == null)) {
      _scheduleDismiss();
    }
  }

  void _scheduleDismiss() {
    _timer?.cancel();
    // Location recovery actions must stay visible until fixed or dismissed.
    if (widget.onAction == null) {
      _timer = Timer(const Duration(seconds: 4), () => widget.onDismiss());
    }
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
          child: Semantics(
            liveRegion: true,
            child: Material(
              color: WaybiColors.darkOcean.withValues(alpha: .96),
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
                          color: WaybiColors.sky,
                          size: 19,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: widget.dismissLabel,
                          onPressed: widget.onDismiss,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
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
                            foregroundColor: WaybiColors.sky,
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
  );
}
