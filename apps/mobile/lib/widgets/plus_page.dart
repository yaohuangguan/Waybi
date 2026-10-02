import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/account_repository.dart';
import '../data/plus_billing.dart';
import 'kiwi_mascot.dart';

/// Native Plus discovery and subscription flow, shared by account and upsell entries.
class PlusPage extends StatefulWidget {
  const PlusPage({
    super.key,
    required this.account,
    required this.language,
    required this.billing,
    this.onSignIn,
  });
  final AccountRepository account;
  final String language;
  final PlusBillingGateway billing;
  final VoidCallback? onSignIn;
  @override
  State<PlusPage> createState() => _PlusPageState();
}

class _PlusPageState extends State<PlusPage> with WidgetsBindingObserver {
  PlusOffering? _offering;
  String? _selected;
  bool _loading = true, _busy = false;
  String? _notice;
  bool _error = false;
  String t(String en, String zh) => widget.language == 'zh' ? zh : en;
  bool get isPlus => widget.account.profile?.isPlus == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.account.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.account.removeListener(_accountChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _refreshMembership();
  }

  Future<void> _refreshMembership() async {
    try {
      await widget.account.refresh();
    } catch (_) {
      /* retain last known state */
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notice = null;
      _error = false;
    });
    try {
      final offering = await widget.billing.load();
      if (!mounted) return;
      setState(() {
        _offering = offering;
        if (!offering.plans.any((p) => p.id == _selected)) {
          _selected =
              offering.plans.where((p) => p.annual).firstOrNull?.id ??
              offering.plans.firstOrNull?.id;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _offering = null;
        _error = true;
        _notice = t(
          'Could not load plans. Your map is ready to use; try again when connected.',
          '暂时无法加载订阅方案。地图仍可使用，网络恢复后可重试。',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _action(
    Future<void> Function() action, {
    bool restoring = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
      _error = false;
    });
    try {
      await action();
      await widget.account.refresh();
      if (!mounted) return;
      setState(
        () => _notice = isPlus
            ? t('You’re all set. Plus is active.', '准备好了，Plus 已启用。')
            : restoring
            ? t(
                'Restore completed. No active Plus membership was found for this account.',
                '恢复已完成，此账户暂未找到有效的 Plus 订阅。',
              )
            : t(
                'Complete the payment, then return here to refresh your membership.',
                '完成付款后返回这里，即可刷新会员权益。',
              ),
      );
    } on PlusPurchaseCancelled {
      if (mounted) {
        setState(
          () => _notice = t(
            'Purchase cancelled. Your current plan is unchanged.',
            '已取消购买，当前权益不变。',
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _notice = t(
          'Could not complete this step. Please try again; an unverified payment will not unlock Plus.',
          '暂时无法完成，请重试。付款确认成功后才会开通 Plus。',
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _PlusSignIn(account: widget.account, language: widget.language),
    );
    if (mounted && widget.account.signedIn) await _load();
  }

  Future<void> _openDocument(String url) async {
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Keep the subscription page usable if the browser cannot be opened.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('Could not open this link. Please try again.', '暂时无法打开链接，请重试。'),
          ),
        ),
      );
    }
  }

  List<(IconData, String, String)> get _features => [
    (
      Icons.radar_rounded,
      t('Smart Commute', '智能通勤'),
      t(
        'Compare today with your usual Home ↔ Work journey. Route Watch checks official disruptions before you leave.',
        '对比今天与平时的家 ↔ 公司通勤，出发前主动了解官方道路异常。',
      ),
    ),
    (
      Icons.flag_circle_rounded,
      t('Arrival Assistant', '到达辅助'),
      t(
        'Keep the destination, parking and final walking leg together for a smoother arrival.',
        '把目的地、停车和最后一段步行衔接起来，让到达更顺畅。',
      ),
    ),
    (
      Icons.offline_bolt_rounded,
      t('Poor-signal cache', '弱网缓存'),
      t(
        'Retain useful journey context through a weak signal. Live updates still need a connection.',
        '信号弱时保留实用行程信息，实时更新仍需要网络。',
      ),
    ),
    (
      Icons.insights_rounded,
      t('Trip Intelligence', '行程洞察'),
      t(
        'See 30-day patterns, travel time and frequent destinations. Check camera updates whenever you need.',
        '查看近 30 天出行趋势、用时和常去地点，也能随时检查摄像头数据更新。',
      ),
    ),
  ];

  Widget _feature(IconData icon, String title, String description) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xffd0f58a),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 23, color: const Color(0xff152510)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _plan(PlusPlan plan) {
    final chosen = plan.id == _selected;
    final monthly = _offering?.plans.where((p) => !p.annual).firstOrNull;
    final saving =
        plan.annual &&
            monthly != null &&
            monthly.currency == plan.currency &&
            monthly.amount > 0
        ? ((1 - plan.amount / (monthly.amount * 12)) * 100).round()
        : 0;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: chosen,
      button: true,
      child: InkWell(
        key: ValueKey('plus-plan-${plan.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: _busy ? null : () => setState(() => _selected = plan.id),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: chosen
                ? scheme.primaryContainer.withValues(alpha: .45)
                : scheme.surface,
            border: Border.all(
              color: chosen ? scheme.primary : scheme.outlineVariant,
              width: chosen ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                chosen
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: scheme.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          plan.annual ? t('Yearly', '年付') : t('Monthly', '月付'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (saving > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xffd0f58a),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              t('Save $saving%', '省 $saving%'),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xff152510),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      '${plan.price} / ${plan.annual ? t('year', '年') : t('month', '月')}',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      plan.annual
                          ? t('Charged once per year', '每年扣款一次')
                          : t('Charged once per month', '每月扣款一次'),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plan = _offering?.plans.where((p) => p.id == _selected).firstOrNull;
    final canManage =
        _offering?.canManage == true ||
        (_offering?.provider == PlusBillingProvider.apple &&
            widget.account.profile?.subscriptionSource == 'apple');
    final expiry = widget.account.profile?.subscriptionExpiresAt;
    final canBuy =
        !_busy &&
        !_loading &&
        _offering?.available == true &&
        plan != null &&
        widget.account.signedIn &&
        !isPlus;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Kiwi Lens Plus',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: t('Refresh membership', '刷新会员权益'),
            onPressed: _busy || _loading
                ? null
                : () async {
                    await _refreshMembership();
                    await _load();
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xff152510),
              borderRadius: BorderRadius.circular(27),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      t('YOUR LITTLE UPGRADE', '每天出行的小升级'),
                      style: const TextStyle(
                        color: Color(0xffd0f58a),
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const KiwiMascot(size: 74),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  t('A little more ahead.', '提前一点，\n从容一点。'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 33,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  t(
                    'Less guesswork before you leave. More help when you arrive. Your Kiwi, with a few extra superpowers.',
                    '出发前少一点猜测，到达时多一点顺畅。你的小小 Kiwi，拥有更多贴心本领。',
                  ),
                  style: const TextStyle(
                    color: Color(0xffc4d3b8),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                if (isPlus) ...[
                  const SizedBox(height: 17),
                  Row(
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        color: Color(0xffd0f58a),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        t('Plus is active', 'Plus 已启用'),
                        style: const TextStyle(
                          color: Color(0xffd0f58a),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 25),
          Text(
            t('Thoughtful extras, all the way.', '每一步，都有实用的小升级。'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 13),
          for (final feature in _features)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _feature(feature.$1, feature.$2, feature.$3),
            ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(19),
            ),
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                t('The essentials stay free', '基础功能，继续免费'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                t(
                  'Maps · search · navigation · camera updates',
                  '地图 · 搜索 · 导航 · 摄像头自动更新',
                ),
                style: const TextStyle(fontSize: 11),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    t(
                      'Core navigation, automatic camera reminders, parking discovery and trip history remain available to everyone. Plus adds proactive context and convenience.',
                      '基础导航、摄像头自动提醒、停车发现和行程记录向所有用户开放。Plus 增加主动提醒与便利体验。',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            isPlus
                ? t('Your membership', '你的会员权益')
                : t('Choose a plan that fits', '选一份适合你的订阅'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (widget.account.profile != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                widget.account.profile!.email,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else if (isPlus && expiry != null)
            Text(
              '${t('Access until', '权益有效至')} ${MaterialLocalizations.of(context).formatMediumDate(expiry.toLocal())}',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            )
          else if (!isPlus && _offering != null) ...[
            for (final p in _offering!.plans)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _plan(p),
              ),
            Text(
              _offering!.available
                  ? t(
                      'Subscriptions renew automatically. Cancel before renewal; access continues until your paid period ends.',
                      '订阅自动续订，可在续订前取消。权益保留至已付周期结束。',
                    )
                  : t(
                      'Subscriptions are not available on this build yet. You can keep exploring the free map.',
                      '当前版本暂未开放订阅，你可以继续使用免费地图。',
                    ),
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_offering == null && !_loading)
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(t('Try again', '重试')),
            ),
          if (_offering?.canRestore == true)
            TextButton(
              onPressed: _busy
                  ? null
                  : !widget.account.signedIn
                  ? (widget.onSignIn ?? _signIn)
                  : () => _action(widget.billing.restore, restoring: true),
              child: Text(t('Restore purchases', '恢复购买')),
            ),
          if (isPlus)
            OutlinedButton.icon(
              onPressed: _busy ? null : _refreshMembership,
              icon: const Icon(Icons.sync_rounded),
              label: Text(t('Refresh account access', '刷新账户权益')),
            ),
          const SizedBox(height: 17),
          Text(
            t(
              'CarPlay is awaiting Apple authorization and is not an available Plus feature yet.',
              'CarPlay 仍在等待 Apple 授权，目前不作为已可用的 Plus 功能提供。',
            ),
            style: TextStyle(
              fontSize: 10,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Wrap(
            children: [
              TextButton(
                onPressed: () => _openDocument(
                  'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
                ),
                child: Text(t('Subscription terms', '订阅条款')),
              ),
              TextButton(
                onPressed: () => _openDocument(
                  'https://github.com/yaohuangguan/kiwi-lens#privacy',
                ),
                child: Text(t('Privacy & data', '隐私与数据')),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _notice!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: _error ? scheme.error : scheme.primary,
                      ),
                    ),
                  ),
                ),
              if (!isPlus && plan != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Text(
                    '${plan.price} / ${plan.annual ? t('year', '年') : t('month', '月')}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('plus-subscribe'),
                  onPressed: _busy || _loading
                      ? null
                      : isPlus
                      ? (canManage
                            ? () => _action(widget.billing.manage)
                            : () =>
                                  Navigator.of(context)
                                      .popUntil((route) => route.isFirst))
                      : !widget.account.signedIn
                      ? (widget.onSignIn ?? _signIn)
                      : canBuy
                      ? () => _action(() => widget.billing.subscribe(plan))
                      : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(49),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          isPlus
                              ? (canManage
                                    ? t('Manage subscription', '管理订阅')
                                    : t('Let’s go, Kiwi', '回到地图，出发吧'))
                              : !widget.account.signedIn
                              ? t('Sign in to continue', '登录后继续')
                              : _offering?.available == true
                              ? t('Subscribe to Plus', '订阅 Plus')
                              : t('Subscriptions opening soon', '订阅即将开放'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlusSignIn extends StatefulWidget {
  const _PlusSignIn({required this.account, required this.language});
  final AccountRepository account;
  final String language;
  @override
  State<_PlusSignIn> createState() => _PlusSignInState();
}

class _PlusSignInState extends State<_PlusSignIn> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  bool _register = false, _busy = false, _showPassword = false;
  String? _error;
  String t(String en, String zh) => widget.language == 'zh' ? zh : en;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _authenticate({bool google = false}) async {
    if (_busy || (!google && !_form.currentState!.validate())) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (google) {
        await widget.account.authenticateWithGoogle();
      } else {
        await widget.account.authenticate(
          _email.text,
          _password.text,
          register: _register,
        );
      }
      try {
        await widget.account.updatePreferences(
          language: widget.language,
          voiceEnabled: true,
        );
      } catch (_) {
        // Signing in succeeded; a preference sync can be retried later.
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            'Could not sign in. Check your details and try again.',
            '登录失败，请检查账户信息后重试。',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      22,
      22,
      22,
      22 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _register
                  ? t('Create your Kiwi account', '创建 Kiwi 账户')
                  : t('Welcome back.', '欢迎回来。'),
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'Your Plus membership follows this account. Your selected plan stays saved.',
                'Plus 权益属于这个账户，你选择的订阅方案会保留。',
              ),
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: t('Email', '邮箱')),
              validator: (value) =>
                  RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                      .hasMatch(value?.trim() ?? '')
                  ? null
                  : t('Enter your email', '请输入有效邮箱'),
            ),
            const SizedBox(height: 13),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              autofillHints: [
                _register ? AutofillHints.newPassword : AutofillHints.password,
              ],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _authenticate(),
              decoration: InputDecoration(
                labelText: _register
                    ? t('Password · 12+ characters', '密码 · 至少 12 位')
                    : t('Password', '密码'),
                suffixIcon: IconButton(
                  tooltip: _showPassword
                      ? t('Hide password', '隐藏密码')
                      : t('Show password', '显示密码'),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (value) => (value?.length ?? 0) >= (_register ? 12 : 1)
                  ? null
                  : t('Check your password', '请检查密码长度'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 13),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : () => _authenticate(),
              child: Text(
                _busy
                    ? t('Please wait…', '请稍候…')
                    : _register
                    ? t('Create account', '创建账户')
                    : t('Sign in', '登录'),
              ),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _authenticate(google: true),
              child: Text(t('Continue with Google', '使用 Google 继续')),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _register = !_register),
              child: Text(
                _register
                    ? t('Already have an account? Sign in', '已有账户？登录')
                    : t('New here? Create an account', '第一次来？创建账户'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
