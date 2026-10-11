import 'package:flutter/material.dart';

import '../domain/road_event.dart';

class RoadEventDetailsSheet extends StatelessWidget {
  const RoadEventDetailsSheet({
    super.key,
    required this.event,
    required this.title,
    required this.language,
  });
  final RoadEvent event;
  final String title, language;
  String text(String en, String zh) => language == 'zh' ? zh : en;
  String metadata(String key) => event.metadata[key]?.toString().trim() ?? '';
  String clock(DateTime date) {
    final local = date.toLocal();
    return '${local.day}/${local.month} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final community = event.metadata['userReported'] == true;
    final reporter = metadata('reporterName');
    final description = metadata('description'),
        comments = metadata('comments');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                event.type == RoadEventType.roadClosure
                    ? Icons.block_rounded
                    : Icons.construction_rounded,
                color: event.type == RoadEventType.roadClosure
                    ? scheme.error
                    : scheme.primary,
                size: 34,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (event.roadName?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(
              event.roadName!,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            community
                ? text(
                    'Reported by ${reporter.isEmpty ? 'a Waybi driver' : reporter}',
                    '${reporter.isEmpty ? 'Waybi 用户' : reporter}报告',
                  )
                : text(
                    'Published by ${event.source.provider}',
                    '发布来源：${event.source.provider}',
                  ),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(description),
          ],
          if (comments.isNotEmpty && comments != description) ...[
            const SizedBox(height: 8),
            Text(comments),
          ],
          if (metadata('alternativeRoute').isNotEmpty) ...[
            const Divider(height: 32),
            Text(
              text('Suggested diversion', '官方绕行建议'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(metadata('alternativeRoute')),
          ],
          if (event.validUntil != null) ...[
            const SizedBox(height: 18),
            Text(
              text(
                'Until ${clock(event.validUntil!)}',
                '预计持续至 ${clock(event.validUntil!)}',
              ),
            ),
          ],
          if (event.source.updatedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              text(
                'Updated ${clock(event.source.updatedAt!)}',
                '更新于 ${clock(event.source.updatedAt!)}',
              ),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
