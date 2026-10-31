import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/account_repository.dart';

/// One account entry for My Waybi, saved places and Plus checkout.
class AccountSignIn extends StatefulWidget {
  const AccountSignIn({
    super.key,
    required this.account,
    this.language = 'en',
    this.voiceEnabled = true,
    this.onSignedIn,
  });

  final AccountRepository account;
  final String language;
  final bool voiceEnabled;
  final VoidCallback? onSignedIn;

  @override
  State<AccountSignIn> createState() => _AccountSignInState();
}

class _AccountSignInState extends State<AccountSignIn> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _passwordMode = false, _showPassword = false, _busy = false;
  String? _challengeId, _error;
  DateTime? _resendAt;
  Timer? _timer;
  String t(String en, String zh) => widget.language == 'zh' ? zh : en;
  int get _remaining => _resendAt == null
      ? 0
      : (_resendAt!.difference(DateTime.now()).inMilliseconds / 1000)
            .ceil()
            .clamp(0, 600);
  bool get _locked => _busy || widget.account.loading;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_locked) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on GoogleSignInException catch (error) {
      if (error.code != GoogleSignInExceptionCode.canceled && mounted) {
        setState(
          () => _error = t(
            'Google sign-in failed. Please try again.',
            'Google 登录失败，请重试。',
          ),
        );
      }
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code != AuthorizationErrorCode.canceled && mounted) {
        setState(
          () => _error = t(
            'Apple sign-in failed. Please try again.',
            'Apple 登录失败，请重试。',
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst('Bad state: ', '');
        setState(
          () =>
              _error = widget.language == 'zh' ? '暂时无法继续，请检查输入或稍后重试。' : message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    if (_remaining > 0 ||
        (_challengeId == null && !_form.currentState!.validate())) {
      return;
    }
    await _run(() async {
      final challenge = await widget.account.requestEmailCode(
        _email.text,
        language: widget.language,
      );
      if (!mounted) return;
      final id = challenge['challengeId'];
      if (id is! String || id.isEmpty) {
        throw StateError('Could not request a code. Please try again.');
      }
      setState(() {
        _challengeId = id;
        _code.clear();
        _resendAt = DateTime.now().add(
          Duration(seconds: (challenge['retryAfter'] as num?)?.toInt() ?? 60),
        );
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _remaining == 0) timer.cancel();
        if (mounted) setState(() {});
      });
    });
  }

  Future<void> _signedIn() async {
    if (!mounted) return;
    _password.clear();
    _code.clear();
    // Authentication is already complete; a failed preference sync must not hide it.
    try {
      await widget.account.updatePreferences(
        language: widget.language,
        voiceEnabled: widget.voiceEnabled,
      );
    } catch (_) {
      /* Retried with the next preferences change. */
    }
    if (mounted) widget.onSignedIn?.call();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_passwordMode && _challengeId == null) return _sendCode();
    await _run(() async {
      if (_passwordMode) {
        await widget.account.authenticate(
          _email.text.trim(),
          _password.text,
          register: false,
        );
      } else {
        await widget.account.authenticateWithEmailCode(
          email: _email.text,
          challengeId: _challengeId!,
          code: _code.text,
          language: widget.language,
          voiceEnabled: widget.voiceEnabled,
        );
      }
      await _signedIn();
    });
  }

  void _changeMethod() {
    setState(() {
      _passwordMode = !_passwordMode;
      _challengeId = null;
      _password.clear();
      _code.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.account,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(24),
        ),
        child: AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.explore_outlined, size: 36, color: colors.primary),
                const SizedBox(height: 12),
                Text(
                  t('Your journey starts here', '每一程，从这里开始'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t(
                    'Sign in or create an account to keep your trips, places and companions together.',
                    '登录或注册，收藏地点、旅途记录和伙伴都在一起。',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
                  IgnorePointer(
                    ignoring: _locked,
                    child: Opacity(
                      opacity: _locked ? .5 : 1,
                      child: SignInWithAppleButton(
                        key: const Key('appleSignInButton'),
                        text: t('Continue with Apple', '使用 Apple 继续'),
                        onPressed: () => _run(() async {
                          await widget.account.authenticateWithApple(
                            language: widget.language,
                          );
                          await _signedIn();
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton.icon(
                  onPressed: _locked
                      ? null
                      : () => _run(() async {
                          await widget.account.authenticateWithGoogle();
                          await _signedIn();
                        }),
                  icon: const Icon(Icons.account_circle_outlined),
                  label: Text(t('Continue with Google', '使用 Google 继续')),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          t('or use your email', '或使用邮箱'),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                ),
                TextFormField(
                  controller: _email,
                  readOnly: _challengeId != null,
                  enabled: !_locked,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: _passwordMode || _challengeId != null
                      ? TextInputAction.next
                      : TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: t('Email', '邮箱'),
                    prefixIcon: const Icon(Icons.mail_outline_rounded),
                  ),
                  validator: (value) =>
                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(value?.trim() ?? '') &&
                          (value?.trim().length ?? 0) <= 254
                      ? null
                      : t('Enter a valid email address', '请输入有效的邮箱地址'),
                ),
                if (_passwordMode) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    enabled: !_locked,
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: t('Password', '密码'),
                      suffixIcon: IconButton(
                        tooltip: t('Show or hide password', '显示或隐藏密码'),
                        onPressed: _locked
                            ? null
                            : () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => value?.isNotEmpty == true
                        ? null
                        : t('Enter your password', '请输入密码'),
                  ),
                ] else if (_challengeId != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    t(
                      'Check your inbox. Your code is valid for 10 minutes.',
                      '请查收邮件，验证码 10 分钟内有效。',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _code,
                    enabled: !_locked,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: t('6-digit code', '6 位验证码'),
                    ),
                    validator: (value) =>
                        RegExp(r'^\d{6}$').hasMatch(value ?? '')
                        ? null
                        : t('Enter the six-digit code', '请输入 6 位验证码'),
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _locked || _remaining > 0 ? null : _sendCode,
                        child: Text(
                          _remaining > 0
                              ? t(
                                  'Resend in ${_remaining}s',
                                  '$_remaining 秒后重发',
                                )
                              : t('Resend code', '重新发送'),
                        ),
                      ),
                      TextButton(
                        onPressed: _locked
                            ? null
                            : () => setState(() {
                                _challengeId = null;
                                _code.clear();
                                _error = null;
                              }),
                        child: Text(t('Change email', '更换邮箱')),
                      ),
                    ],
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(color: colors.error, fontSize: 13),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _locked ? null : _submit,
                  child: Text(
                    _locked
                        ? t('Please wait…', '请稍候…')
                        : _passwordMode
                        ? t('Sign in', '登录')
                        : _challengeId == null
                        ? t('Continue with email', '使用邮箱继续')
                        : t('Verify and continue', '验证并继续'),
                  ),
                ),
                TextButton(
                  onPressed: _locked ? null : _changeMethod,
                  child: Text(
                    _passwordMode
                        ? t('Use an email code instead', '改用邮箱验证码')
                        : t('Sign in with a password', '使用密码登录'),
                  ),
                ),
                Text(
                  t(
                    'New here? Verifying your email creates your account automatically.',
                    '首次使用？验证邮箱后将自动创建账号。',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (final page in ['terms', 'privacy'])
                      TextButton(
                        onPressed: () async {
                          final prefix = widget.language == 'zh' ? '/zh' : '';
                          await _run(() async {
                            if (!await launchUrl(
                              Uri.parse('https://waybi.co$prefix/$page/'),
                              mode: LaunchMode.externalApplication,
                            )) {
                              throw StateError(
                                t('Could not open this page.', '暂时无法打开页面。'),
                              );
                            }
                          });
                        },
                        child: Text(
                          page == 'terms'
                              ? t('Terms of use', '使用条款')
                              : t('Privacy policy', '隐私政策'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
