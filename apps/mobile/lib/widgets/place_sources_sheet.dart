import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void showPlaceSources(
  BuildContext context, {
  required String language,
  bool mapCompatible = true,
  Map<String, dynamic>? photoCredit,
}) {
  final zh = language == 'zh';
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              zh ? '数据与图片来源' : 'Data & photo credits',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              mapCompatible
                  ? (zh
                        ? '地点与地图使用开放数据。照片只在能够确认地点和授权时显示。'
                        : 'Places use open data. Photos are shown when their location and licence can be verified.')
                  : (zh
                        ? '地点信息与照片由 Google Maps 和摄影者提供。'
                        : 'Places and photos are provided by Google Maps and photographers.'),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(
                  mapCompatible
                      ? 'https://www.openstreetmap.org/copyright'
                      : 'https://maps.google.com',
                ),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(
                mapCompatible ? '© OpenStreetMap · ODbL' : '© Google Maps',
              ),
            ),
            if (mapCompatible)
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://openmaptiles.org'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('© OpenMapTiles · CC BY'),
              ),
            if (photoCredit != null) ...[
              const Divider(),
              Text(photoCredit['author']?.toString() ?? 'Wikimedia Commons'),
              TextButton(
                onPressed: () {
                  final link = photoCredit['licenseUrl']?.toString() ?? '';
                  if (link.startsWith('https://')) {
                    launchUrl(
                      Uri.parse(link),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                child: Text(photoCredit['license']?.toString() ?? ''),
              ),
              TextButton(
                onPressed: () {
                  final link = photoCredit['sourceUrl']?.toString() ?? '';
                  if (link.startsWith('https://')) {
                    launchUrl(
                      Uri.parse(link),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                child: Text(zh ? '查看原图与作者' : 'View original photo & author'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
