import '../theme/waybi_theme.dart';

import 'package:flutter/material.dart';
import 'package:waybi_friends/waybi_friends.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/account_repository.dart';
import '../data/app_store_billing.dart';
import '../data/plus_billing.dart';
import 'plus_page.dart';
import '../data/camera_repository.dart';
import '../domain/map_provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.account,
    this.plusBilling,
    required this.voiceEnabled,
    required this.lanesEnabled,
    this.keepScreenAwake = true,
    this.onKeepScreenAwakeChanged,
    this.onNativeLanguageSettings,
    required this.appLanguage,
    required this.voiceLanguage,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    required this.onVoiceChanged,
    required this.onLanesChanged,
    required this.onAppLanguageChanged,
    required this.onLanguageChanged,
    required this.onMapLayers,
    required this.mapProvider,
    required this.locationMarker,
    required this.onMapProviderChanged,
    required this.onLocationMarkerChanged,
    required this.notifySafetyCameras,
    required this.notifyRoadIncidents,
    required this.notifyCommunityReports,
    required this.notifySavedRouteDisruptions,
    required this.onNotifySafetyCamerasChanged,
    required this.onNotifyRoadIncidentsChanged,
    required this.onNotifyCommunityReportsChanged,
    required this.onNotifySavedRouteDisruptionsChanged,
    this.cameraSnapshot,
    required this.onSyncCameraData,
  });

  final AccountRepository account;
  final PlusBillingGateway? plusBilling;
  final bool voiceEnabled;
  final bool lanesEnabled;
  final bool keepScreenAwake;
  final ValueChanged<bool>? onKeepScreenAwakeChanged;
  final VoidCallback? onNativeLanguageSettings;
  final String appLanguage;
  final String voiceLanguage;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<bool> onVoiceChanged;
  final ValueChanged<bool> onLanesChanged;
  final ValueChanged<String> onAppLanguageChanged;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onMapLayers;
  final MapProvider mapProvider;
  final LocationMarkerStyle locationMarker;
  final Future<MapProvider> Function(MapProvider) onMapProviderChanged;
  final ValueChanged<LocationMarkerStyle> onLocationMarkerChanged;
  final bool notifySafetyCameras;
  final bool notifyRoadIncidents;
  final bool notifyCommunityReports;
  final bool notifySavedRouteDisruptions;
  final ValueChanged<bool> onNotifySafetyCamerasChanged;
  final ValueChanged<bool> onNotifyRoadIncidentsChanged;
  final ValueChanged<bool> onNotifyCommunityReportsChanged;
  final ValueChanged<bool> onNotifySavedRouteDisruptionsChanged;
  final CameraSnapshot? cameraSnapshot;
  final Future<CameraSnapshot?> Function() onSyncCameraData;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  String? _error;
  late bool _voice = widget.voiceEnabled;
  late bool _lanes = widget.lanesEnabled;
  late bool _keepScreenAwake = widget.keepScreenAwake;
  late String _appLanguage = widget.appLanguage;
  late String _language = widget.voiceLanguage;
  late ThemeMode _themeMode = widget.themeMode;
  late MapProvider _mapProvider = widget.mapProvider;
  late LocationMarkerStyle _locationMarker = widget.locationMarker;
  late bool _notifySafetyCameras = widget.notifySafetyCameras;
  late bool _notifyRoadIncidents = widget.notifyRoadIncidents;
  late bool _notifyCommunityReports = widget.notifyCommunityReports;
  late bool _notifySavedRouteDisruptions = widget.notifySavedRouteDisruptions;
  late CameraSnapshot? _cameraSnapshot = widget.cameraSnapshot;
  bool _cameraSyncing = false;

  String _text(String english, String chinese) =>
      _appLanguage == 'zh' ? chinese : english;

  Future<void> _showMapDataLicences() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .66,
        minChildSize: .48,
        maxChildSize: .9,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Text(
              _text('Map data & licences', '地图数据与许可'),
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _text(
                'Waybi controls the map experience, style, navigation UI and product layers. Geographic data still comes from credited open and official sources.',
                'Waybi 自己控制地图体验、样式、导航界面和产品图层；底层地理数据仍来自需要注明来源的开放数据和官方数据。',
              ),
              style: const TextStyle(height: 1.45),
            ),
            const SizedBox(height: 20),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.public_rounded),
              title: Text('OpenStreetMap'),
              subtitle: Text(
                'Map data © OpenStreetMap contributors · Open Database License (ODbL)',
              ),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.location_city_rounded),
              title: Text('Toitū Te Whenua LINZ'),
              subtitle: Text(
                'New Zealand address data · Creative Commons Attribution 4.0',
              ),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.layers_outlined),
              title: Text('Waybi Map basemap'),
              subtitle: Text(
                'MapLibre rendering. Current rollout still uses OpenFreeMap / OpenMapTiles infrastructure while Waybi-hosted map tiles are introduced.',
              ),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.route_rounded),
              title: Text('Routing'),
              subtitle: Text(
                'OSRM routing over OpenStreetMap road data. Waybi-hosted regional routing is being introduced before public launch.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraSnapshot != widget.cameraSnapshot && !_cameraSyncing) {
      _cameraSnapshot = widget.cameraSnapshot;
    }
  }

  Future<void> _syncCameraData() async {
    if (_cameraSyncing || widget.account.profile?.isPlus != true) return;
    setState(() => _cameraSyncing = true);
    try {
      final snapshot = await widget.onSyncCameraData();
      if (!mounted) return;
      setState(() => _cameraSnapshot = snapshot ?? _cameraSnapshot);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _cameraSyncing = false);
    }
  }

  String _cameraDate(DateTime? value) {
    if (value == null) return _text('Unknown', '未知');
    final local = value.toLocal();
    final date =
        '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
    return date;
  }

  String _cameraFetchMode(String? value) => switch (value) {
    'direct' => _text('NZTA direct', 'NZTA 直连'),
    'reader-fallback' => _text('Verified NZTA page fallback', 'NZTA 页面校验回退'),
    'bundled-seed' => _text('Bundled verified snapshot', '内置已验证快照'),
    _ => _text('NZTA published data', 'NZTA 公开数据'),
  };

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _error = null);
    try {
      await widget.account.authenticate(
        _email.text,
        _password.text,
        register: _register,
      );
      _password.clear();
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'.replaceFirst('Bad state: ', ''));
      }
    }
  }

  Future<void> _google({bool link = false}) async {
    setState(() => _error = null);
    try {
      await widget.account.authenticateWithGoogle(link: link);
    } on GoogleSignInException catch (error) {
      if (error.code != GoogleSignInExceptionCode.canceled && mounted) {
        setState(
          () => _error =
              'Google sign-in: ${error.description ?? error.code.name}',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'.replaceFirst('Bad state: ', ''));
      }
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(
      text: widget.account.profile?.displayName ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_text('Edit display name', '编辑显示名称')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(labelText: _text('Name', '名称')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_text('Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(_text('Save', '保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    try {
      await widget.account.updateDisplayName(name);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _voiceChanged(bool value) {
    setState(() => _voice = value);
    widget.onVoiceChanged(value);
    widget.account
        .updatePreferences(language: _appLanguage, voiceEnabled: value)
        .catchError((_) {});
  }

  void _languageChanged(String value) {
    setState(() => _language = value);
    widget.onLanguageChanged(value);
  }

  void _appLanguageChanged(String value) {
    setState(() => _appLanguage = value);
    widget.onAppLanguageChanged(value);
    widget.account
        .updatePreferences(language: value, voiceEnabled: _voice)
        .catchError((_) {});
  }

  Widget _cameraDataCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final snapshot = _cameraSnapshot;
    final isPlus = widget.account.profile?.isPlus == true;
    final status = snapshot?.syncStatus ?? 'unknown';
    final statusColor = switch (status) {
      'live' => WaybiColors.success,
      'stale' => WaybiColors.warning,
      'seed' => scheme.primary,
      _ => scheme.onSurfaceVariant,
    };
    final statusLabel = switch (status) {
      'live' => _text('Live', '已同步'),
      'stale' => _text('Stale', '数据较旧'),
      'seed' => _text('Bundled', '内置数据'),
      _ => _text('Not loaded', '未加载'),
    };
    int countType(String needle) =>
        snapshot?.cameras
            .where((camera) => camera.type.toLowerCase().contains(needle))
            .length ??
        0;
    final total = snapshot?.cameras.length ?? 0;
    final spot = countType('spot');
    final red = countType('red light');
    final average = countType('average');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.photo_camera_rounded, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text('NZTA camera data', 'NZTA 摄像头数据'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total == 0
                          ? _text('Published fixed safety cameras', '公开固定安全摄像头')
                          : _text(
                              '$total published fixed cameras',
                              '$total 个公开固定摄像头',
                            ),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (snapshot != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _CameraDataPill(label: _text('Spot', '定点'), value: '$spot'),
                _CameraDataPill(label: _text('Red light', '红灯'), value: '$red'),
                _CameraDataPill(
                  label: _text('Average', '区间'),
                  value: '$average',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _text(
                'NZTA source updated ${_cameraDate(snapshot.sourceUpdatedAt)} · checked ${_cameraDate(snapshot.checkedAt)}',
                'NZTA 源更新于 ${_cameraDate(snapshot.sourceUpdatedAt)} · 检查于 ${_cameraDate(snapshot.checkedAt)}',
              ),
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _cameraFetchMode(snapshot.fetchMode),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5),
            ),
            if (snapshot.changeAdded > 0 || snapshot.changeRemoved > 0) ...[
              const SizedBox(height: 3),
              Text(
                _text(
                  'Last change: +${snapshot.changeAdded} / -${snapshot.changeRemoved}',
                  '最近变化：+${snapshot.changeAdded} / -${snapshot.changeRemoved}',
                ),
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Text(
            _text(
              'Uses every field NZTA publishes for fixed safety cameras: region, suburb, location, camera type and GPS. Mobile camera locations are not fixed or fabricated.',
              '完整使用 NZTA 对固定安全摄像头公开的区域、郊区、位置、类型和 GPS。移动测速点没有固定公开位置，Waybi 不会虚构。',
            ),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (!isPlus) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _text(
                      'Instant NZTA refresh is a Waybi Plus feature. Automatic camera updates still stay available to everyone.',
                      '立即刷新 NZTA 摄像头是 Waybi Plus 功能。后台自动更新仍然对所有用户开放。',
                    ),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: !isPlus || _cameraSyncing ? null : _syncCameraData,
              icon: _cameraSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(isPlus ? Icons.sync_rounded : Icons.lock_rounded),
              label: Text(
                _cameraSyncing
                    ? _text('Checking NZTA…', '正在检查 NZTA…')
                    : isPlus
                    ? _text('Check for camera updates', '检查摄像头更新')
                    : _text(
                        'Plus · Check for camera updates',
                        'Plus · 检查摄像头更新',
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.account,
    builder: (context, _) {
      final profile = widget.account.profile;
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: WaybiColors.darkOcean,
          foregroundColor: Colors.white,
          title: Text(
            _text('My Waybi', '我的 Waybi'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [WaybiColors.darkOcean, WaybiColors.ocean],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 27,
                      backgroundColor: WaybiColors.sky,
                      child: Text(
                        profile?.displayName.isNotEmpty == true
                            ? profile!.displayName[0].toUpperCase()
                            : 'T',
                        style: const TextStyle(
                          color: WaybiColors.darkOcean,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile?.displayName.isNotEmpty == true
                                ? profile!.displayName
                                : profile == null
                                ? _text('Guest explorer', '访客')
                                : _text('Waybi member', 'Waybi 用户'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            profile?.email ??
                                _text(
                                  'Sign in to sync your trips and places',
                                  '登录以同步行程和地点',
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (profile != null)
                      IconButton(
                        onPressed: _editName,
                        tooltip: _text('Edit profile', '编辑资料'),
                        icon: const Icon(
                          Icons.edit_rounded,
                          color: WaybiColors.sky,
                        ),
                      ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 13),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FriendsEntry(chinese: _appLanguage == 'zh'),
              const SizedBox(height: 16),
              _PlusCard(
                isPlus: profile?.isPlus ?? false,
                chinese: _appLanguage == 'zh',
                onOpen: () async {
                  final billing =
                      widget.plusBilling ??
                      AppStoreBillingGateway(widget.account);
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlusPage(
                        account: widget.account,
                        voiceEnabled: _voice,
                        language: _appLanguage,
                        billing: billing,
                      ),
                    ),
                  );
                  if (widget.plusBilling == null) billing.dispose();
                },
              ),
              if (profile == null) ...[
                const SizedBox(height: 19),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: _text('Email', '邮箱'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: [
                    _register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: InputDecoration(
                    labelText: _register
                        ? _text('Password (12+ characters)', '密码（至少 12 个字符）')
                        : _text('Password', '密码'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: widget.account.loading ? null : _signIn,
                  child: Text(
                    _register
                        ? _text('Create account', '创建账号')
                        : _text('Sign in', '登录'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _register = !_register),
                  child: Text(
                    _register
                        ? _text('Already have an account? Sign in', '已有账号？登录')
                        : _text('New here? Create an account', '第一次使用？创建账号'),
                  ),
                ),
                Center(
                  child: Text(
                    _text('or', '或'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.account.loading ? null : () => _google(),
                  icon: const Text(
                    'G',
                    style: TextStyle(
                      color: Color(0xFF4285F4),
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                  label: Text(_text('Continue with Google', '使用 Google 继续')),
                ),
              ] else ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    _Stat('${profile.routes.length}', _text('Routes', '路线')),
                    _Stat(
                      '${profile.places.where((place) => place['isFavorite'] == true).length}',
                      _text('Saved', '收藏'),
                    ),
                    _Stat('${profile.reviews.length}', _text('Reviews', '评价')),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_done_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _text('Waybi Sync', 'Waybi 同步'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _text(
                                'Routes, saved places, reviews and preferences are synced.',
                                '路线、收藏地点、评价和偏好设置已同步。',
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        profile.providers
                            .map(
                              (provider) => provider == 'google'
                                  ? 'Google'
                                  : _text('Email', '邮箱'),
                            )
                            .join(' · '),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (profile.recentDestinations.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionTitle(_text('Recent destinations', '最近目的地')),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      children: [
                        for (final item in profile.recentDestinations.take(3))
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.history_rounded),
                            title: Text(
                              item['label']?.toString() ??
                                  _text('Destination', '目的地'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: item['createdAt'] == null
                                ? null
                                : Text(
                                    item['createdAt'].toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (!profile.providers.contains('google'))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link_rounded),
                    title: Text(_text('Link Google account', '关联 Google 账号')),
                    subtitle: Text(
                      _text(
                        'Use the same email address to sign in with Google later',
                        '以后可使用相同邮箱通过 Google 登录',
                      ),
                    ),
                    onTap: widget.account.loading
                        ? null
                        : () => _google(link: true),
                  ),
              ],
              const SizedBox(height: 18),
              _SectionTitle(_text('App', '应用')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.translate_rounded),
                title: Text(_text('App language', '应用语言')),
                subtitle: Text(
                  _text('Navigation cards update immediately', '导航卡片即时切换语言'),
                ),
                trailing: DropdownButton<String>(
                  value: _appLanguage,
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'zh', child: Text('中文')),
                  ],
                  onChanged: (value) {
                    if (value != null) _appLanguageChanged(value);
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _themeMode == ThemeMode.dark
                      ? Icons.dark_mode_rounded
                      : _themeMode == ThemeMode.light
                      ? Icons.light_mode_rounded
                      : Icons.brightness_auto_rounded,
                ),
                title: Text(_text('Appearance', '外观')),
                subtitle: Text(
                  _text(
                    'Use Waybi in light, dark or follow the system',
                    '选择浅色、深色或跟随系统',
                  ),
                ),
                trailing: DropdownButton<ThemeMode>(
                  value: _themeMode,
                  items: [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text(_text('System', '系统')),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text(_text('Light', '浅色')),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text(_text('Dark', '深色')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _themeMode = value);
                    widget.onThemeModeChanged?.call(value);
                  },
                ),
              ),
              const SizedBox(height: 8),
              _SectionTitle(_text('Map', '地图')),
              if (widget.onNativeLanguageSettings != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.translate_rounded),
                  title: Text(
                    _text('Google map label language', 'Google 地图标签语言'),
                  ),
                  subtitle: Text(
                    _text(
                      'Native maps use the system app language. Reopen after changing it.',
                      '原生地图使用系统应用语言，修改后重新打开应用。',
                    ),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: widget.onNativeLanguageSettings,
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.map_outlined),
                title: Text(_text('Map provider', '地图提供商')),
                trailing: DropdownButton<MapProvider>(
                  value: _mapProvider,
                  items: [
                    const DropdownMenuItem(
                      value: MapProvider.google,
                      child: Text('Google Maps'),
                    ),
                    DropdownMenuItem(
                      value: MapProvider.independent,
                      child: Text(_text('Waybi Map', 'Waybi 地图')),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    final actual = await widget.onMapProviderChanged(value);
                    if (mounted) setState(() => _mapProvider = actual);
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(_text('Map data & licences', '地图数据与许可')),
                subtitle: Text(
                  _text(
                    'OpenStreetMap, LINZ and other map-data credits',
                    'OpenStreetMap、LINZ 及其他地图数据来源',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _showMapDataLicences,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.layers_outlined),
                title: Text(_text('Map style', '地图样式')),
                subtitle: Text(
                  _mapProvider == MapProvider.independent
                      ? _text(
                          'Waybi Map · day and night colours',
                          'Waybi 地图 · 日夜配色',
                        )
                      : _text(
                          'Default, satellite, terrain and hybrid',
                          '标准、卫星、地形和混合',
                        ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: widget.onMapLayers,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.navigation_outlined),
                title: Text(_text('Location marker', '位置标记')),
                trailing: DropdownButton<LocationMarkerStyle>(
                  value: _locationMarker,
                  items: [
                    DropdownMenuItem(
                      value: LocationMarkerStyle.kiwi,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'packages/waybi_friends/assets/characters/waybi.png',
                            width: 28,
                            height: 28,
                            semanticLabel: _text(
                              'Waybi, the kiwi bird',
                              'Waybi 几维鸟',
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Waybi'),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: LocationMarkerStyle.cat,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/markers/clover.png',
                            width: 28,
                            height: 28,
                          ),
                          const SizedBox(width: 8),
                          Text(_text('Clover', 'Clover 猫')),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: LocationMarkerStyle.dog,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/markers/sett.png',
                            width: 28,
                            height: 28,
                          ),
                          const SizedBox(width: 8),
                          Text(_text('Sett', 'Sett 狗')),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: LocationMarkerStyle.arrow,
                      child: Text(_text('Arrow', '箭头')),
                    ),
                    DropdownMenuItem(
                      value: LocationMarkerStyle.car,
                      child: Text(_text('Car', '车辆')),
                    ),
                    DropdownMenuItem(
                      value: LocationMarkerStyle.classic,
                      child: Text(_text('Classic', '经典')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _locationMarker = value);
                    widget.onLocationMarkerChanged(value);
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (_mapProvider == MapProvider.google)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _text(
                      'Google navigation uses its navigation arrow. Custom markers appear while browsing and in Waybi Map.',
                      'Google 导航使用导航箭头。浏览地图与 Waybi 地图可使用自定义位置标记。',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              _SectionTitle(_text('Navigation & voice', '导航与语音')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.wb_sunny_outlined),
                title: Text(_text('Keep screen awake', '导航时屏幕常亮')),
                subtitle: Text(
                  _text('Prevent auto-lock while navigating', '导航期间保持屏幕亮起'),
                ),
                value: _keepScreenAwake,
                onChanged: (value) {
                  setState(() => _keepScreenAwake = value);
                  widget.onKeepScreenAwakeChanged?.call(value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.volume_up_rounded),
                title: Text(
                  _text('Voice guidance & camera alerts', '语音导航与摄像头提醒'),
                ),
                value: _voice,
                onChanged: _voiceChanged,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.language_rounded),
                title: Text(_text('Camera alert language', '摄像头提醒语言')),
                trailing: DropdownButton<String>(
                  value: _language,
                  items: const [
                    DropdownMenuItem(value: 'en-NZ', child: Text('English')),
                    DropdownMenuItem(value: 'zh-CN', child: Text('中文')),
                  ],
                  onChanged: (value) {
                    if (value != null) _languageChanged(value);
                  },
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.alt_route_rounded),
                title: Text(_text('Lane guidance', '车道指引')),
                value: _lanes,
                onChanged: (value) {
                  setState(() => _lanes = value);
                  widget.onLanesChanged(value);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.layers_rounded),
                title: Text(_text('Map layers', '地图图层')),
                subtitle: Text(
                  _text('Cameras, traffic and map style', '摄像头、路况与地图样式'),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: widget.onMapLayers,
              ),
              const SizedBox(height: 10),
              _SectionTitle(_text('NZTA camera data', 'NZTA 摄像头数据')),
              _cameraDataCard(context),
              if (profile != null) ...[
                const SizedBox(height: 12),
                _SectionTitle(_text('Notifications', '通知')),
                Text(
                  _text(
                    'Waybi only asks for system notification permission when you turn on a notification below.',
                    '只有当你主动开启下面的通知类型时，Waybi 才会请求系统通知权限。',
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.speed_rounded),
                  title: Text(_text('Safety cameras', '安全摄像头')),
                  subtitle: Text(
                    _text(
                      'System alerts for enabled camera types while driving',
                      '驾驶时对已启用的摄像头类型发送系统通知',
                    ),
                  ),
                  value: _notifySafetyCameras,
                  onChanged: (value) {
                    setState(() => _notifySafetyCameras = value);
                    widget.onNotifySafetyCamerasChanged(value);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.warning_amber_rounded),
                  title: Text(_text('Road incidents', '道路事件')),
                  subtitle: Text(
                    _text(
                      'Closures, serious incidents and important road warnings',
                      '封路、严重事故和重要道路警告',
                    ),
                  ),
                  value: _notifyRoadIncidents,
                  onChanged: (value) {
                    setState(() => _notifyRoadIncidents = value);
                    widget.onNotifyRoadIncidentsChanged(value);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.groups_2_outlined),
                  title: Text(_text('Community reports', '社区上报')),
                  subtitle: Text(
                    _text(
                      'Nearby reports shared by Waybi drivers',
                      '附近 Waybi 用户分享的道路报告',
                    ),
                  ),
                  value: _notifyCommunityReports,
                  onChanged: (value) {
                    setState(() => _notifyCommunityReports = value);
                    widget.onNotifyCommunityReportsChanged(value);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    profile.isPlus ? Icons.route_outlined : Icons.lock_rounded,
                  ),
                  title: Text(
                    _text('Proactive saved-route alerts', '收藏路线主动预警'),
                  ),
                  subtitle: Text(
                    profile.isPlus
                        ? _text(
                            'Background alerts for major disruptions on watched routes',
                            '后台监控已关注路线上的重大异常并主动提醒',
                          )
                        : _text(
                            'Plus · background alerts before you leave',
                            'Plus · 出发前后台主动提醒',
                          ),
                  ),
                  value: profile.isPlus && _notifySavedRouteDisruptions,
                  onChanged: profile.isPlus
                      ? (value) {
                          setState(() => _notifySavedRouteDisruptions = value);
                          widget.onNotifySavedRouteDisruptionsChanged(value);
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                _SectionTitle(_text('Your activity', '你的活动')),
                _ActivitySection(
                  _text('Recent routes', '最近路线'),
                  Icons.route_rounded,
                  profile.routes
                      .map(
                        (item) =>
                            item['destinationName']?.toString() ??
                            _text('Route', '路线'),
                      )
                      .toList(),
                  countLabel: _text('items', '项'),
                  emptyLabel: _text('Nothing here yet', '这里还没有内容'),
                ),
                _ActivitySection(
                  _text('Saved places', '已收藏地点'),
                  Icons.bookmark_rounded,
                  profile.places
                      .map(
                        (item) =>
                            item['name']?.toString() ?? _text('Place', '地点'),
                      )
                      .toList(),
                  countLabel: _text('items', '项'),
                  emptyLabel: _text('Nothing here yet', '这里还没有内容'),
                ),
                _ActivitySection(
                  _text('Your reviews', '你的评价'),
                  Icons.rate_review_rounded,
                  profile.reviews
                      .map(
                        (item) =>
                            item['placeName']?.toString() ??
                            _text('Place', '地点'),
                      )
                      .toList(),
                  countLabel: _text('items', '项'),
                  emptyLabel: _text('Nothing here yet', '这里还没有内容'),
                ),
                const SizedBox(height: 15),
                OutlinedButton.icon(
                  onPressed: () async {
                    await widget.account.signOut();
                    if (mounted) setState(() => _error = null);
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(_text('Sign out', '退出登录')),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _CameraDataPill extends StatelessWidget {
  const _CameraDataPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    ),
  );
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection(
    this.title,
    this.icon,
    this.items, {
    required this.countLabel,
    required this.emptyLabel,
  });
  final String title;
  final IconData icon;
  final List<String> items;
  final String countLabel;
  final String emptyLabel;
  @override
  Widget build(BuildContext context) {
    final preview = items.take(3).toList(growable: false);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${items.length} $countLabel'),
        children: items.isEmpty
            ? [ListTile(title: Text(emptyLabel))]
            : [
                for (final item in preview)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.chevron_right_rounded, size: 18),
                    title: Text(
                      item,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (items.length > preview.length)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '+${items.length - preview.length}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
      ),
    );
  }
}

class _PlusCard extends StatelessWidget {
  const _PlusCard({
    required this.isPlus,
    required this.chinese,
    required this.onOpen,
  });
  final bool isPlus, chinese;
  final VoidCallback onOpen;
  String t(String en, String zh) => chinese ? zh : en;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [WaybiColors.darkOcean, WaybiColors.ocean],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const PageStorageKey('waybi-plus-card'),
        initiallyExpanded: false,
        collapsedIconColor: Colors.white70,
        iconColor: WaybiColors.sky,
        collapsedTextColor: Colors.white,
        textColor: Colors.white,
        leading: const Icon(Icons.radar_rounded, color: WaybiColors.sky),
        title: const Text(
          'Waybi Plus',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          isPlus
              ? t('Plus is active', 'Plus 已启用')
              : t('More help for your everyday trips', '给日常出行多一点帮助'),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(17, 0, 17, 17),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          Text(
            t(
              'Core maps, search and turn-by-turn navigation stay free. Plus adds proactive commute intelligence, arrival help, offline resilience and deeper trip insights.',
              '地图、搜索和逐向导航保持免费。Plus 增加主动通勤情报、到达辅助、弱网保障和更深入的行程洞察。',
            ),
            style: const TextStyle(
              color: Colors.white,
              height: 1.35,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PlusChip(
                icon: Icons.flag_circle_rounded,
                label: t('Arrival Assistant', '到达辅助'),
              ),
              _PlusChip(
                icon: Icons.radar_rounded,
                label: t('Smart Commute', '智能通勤'),
              ),
              _PlusChip(
                icon: Icons.insights_rounded,
                label: t('Trip Intelligence', '行程洞察'),
              ),
              _PlusChip(
                icon: Icons.offline_bolt_rounded,
                label: t('Poor-signal cache', '弱网缓存'),
              ),
              _PlusChip(
                icon: Icons.notifications_active_rounded,
                label: t('Proactive alerts · live', '主动预警 · 已启用'),
              ),
              _PlusChip(
                icon: Icons.directions_car_filled_rounded,
                label: t(
                  'CarPlay · Apple entitlement',
                  'CarPlay · 等待 Apple entitlement',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffd0f58a),
                foregroundColor: const Color(0xff152510),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(
                isPlus
                    ? t('Explore your Plus benefits', '查看你的 Plus 权益')
                    : t('Meet Waybi Plus', '了解 Waybi Plus'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PlusChip extends StatelessWidget {
  const _PlusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final maxWidth = (MediaQuery.sizeOf(context).width - 64).clamp(
      160.0,
      300.0,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: WaybiColors.sky, size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
