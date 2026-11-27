import 'package:flutter/material.dart';

import '../theme/waybi_theme.dart';

/// Full error state for a page or section whose first load failed.
///
/// It replaces the content entirely, so nothing that depends on the missing
/// data (saved places, membership, empty states) is shown in a wrong state.
class WaybiLoadError extends StatelessWidget {
  const WaybiLoadError({
    super.key,
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
    this.icon = Icons.cloud_off_rounded,
  });

  final String title;
  final String message;
  final String retryLabel;

  /// Null while a retry is already running.
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(WaybiRadius.panel),
        ),
        child: Column(
          children: [
            Icon(icon, size: 40, color: scheme.error),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.textStyles.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.textStyles.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, WaybiTouch.minTarget),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-line problem above content that is still shown (for example a
/// refresh that failed while the last loaded data stays on screen).
class WaybiInlineError extends StatelessWidget {
  const WaybiInlineError({
    super.key,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final status = context.status;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: status.warningContainer,
          borderRadius: BorderRadius.circular(WaybiRadius.button),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: status.onWarningContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: status.onWarningContainer,
                  fontSize: WaybiTextSize.caption,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: status.onWarningContainer,
                minimumSize: const Size(
                  WaybiTouch.minTarget,
                  WaybiTouch.minTarget,
                ),
              ),
              child: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
