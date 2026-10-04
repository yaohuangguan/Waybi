import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../drive/system_navigation.dart';

class SystemNavigationStatus extends StatelessWidget {
  const SystemNavigationStatus({
    super.key,
    required this.navigation,
    required this.language,
  });
  final SystemNavigation navigation;
  final String language;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }
    String text(String en, String zh) => language == 'zh' ? zh : en;
    return AnimatedBuilder(
      animation: navigation,
      builder: (context, _) {
        final active = navigation.surfaceActive;
        final label = active
            ? text('Dynamic Island navigation is on', '灵动岛导航已开启')
            : !navigation.enabled
            ? text('Enable Live Activities in Settings', '在系统设置中开启实时活动')
            : navigation.failureReason != null
            ? text('Lock Screen guidance unavailable', '锁屏导航暂不可用')
            : text('Preparing Lock Screen guidance', '正在准备锁屏导航');
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(
            active
                ? Icons.check_circle_outline_rounded
                : Icons.phone_iphone_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(label, style: const TextStyle(fontSize: 12)),
          trailing: active
              ? null
              : TextButton(
                  onPressed: navigation.enabled
                      ? navigation.retry
                      : navigation.openSettings,
                  child: Text(
                    navigation.enabled
                        ? text('Retry', '重试')
                        : text('Settings', '设置'),
                  ),
                ),
        );
      },
    );
  }
}
