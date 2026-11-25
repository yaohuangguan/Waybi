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

  Future<void> _openPolicy(String page) async {
    final prefix = widget.language == 'zh' ? '/zh' : '';
    await _run(() async {
      if (!await launchUrl(
        Uri.parse('https://waybi.co$prefix/$page/'),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError(t('Could not open this page.', '暂时无法打开页面。'));
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.account,
    builder: (context, _) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final dark = theme.brightness == Brightness.dark;
      final muted = TextStyle(
        color: colors.onSurfaceVariant,
        fontSize: 12.5,
        height: 1.4,
      );
      final buttonShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      );
      const buttonSize = Size.fromHeight(50);
      final showApple = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      return Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(22),
          boxShadow: dark
              ? null
              : [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: .04),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t('Sign in to Waybi', '登录 Waybi'),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t(
                    'Keep your trips, saved places and companions on every device.',
                    '在所有设备上同步你的行程、收藏地点和旅伴。',
                  ),
                  style: muted.copyWith(fontSize: 13),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Semantics(
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colors.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 18,
                              color: colors.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: colors.onErrorContainer,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (showApple) ...[
                  IgnorePointer(
                    ignoring: _locked,
                    child: Opacity(
                      opacity: _locked ? .5 : 1,
                      child: SignInWithAppleButton(
                        key: const Key('appleSignInButton'),
                        text: t('Continue with Apple', '使用 Apple 继续'),
                        height: 50,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(14),
                        ),
                        style: dark
                            ? SignInWithAppleButtonStyle.white
                            : SignInWithAppleButtonStyle.black,
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
                OutlinedButton(
                  key: const Key('googleSignInButton'),
                  onPressed: _locked
                      ? null
                      : () => _run(() async {
                          await widget.account.authenticateWithGoogle();
                          await _signedIn();
                        }),
                  style: OutlinedButton.styleFrom(
                    minimumSize: buttonSize,
                    shape: buttonShape,
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1F1F1F),
                    disabledBackgroundColor: Colors.white.withValues(alpha: .6),
                    side: const BorderSide(color: Color(0xFFDADCE0)),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const GoogleLogo(size: 20),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          t('Continue with Google', '使用 Google 继续'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(t('or', '或'), style: muted),
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
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _password,
                    enabled: !_locked,
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: t('Password', '密码'),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
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
                  const SizedBox(height: 10),
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
                    style: const TextStyle(
                      fontSize: 18,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: t('6-digit code', '6 位验证码'),
                      helperText: t(
                        'Check your inbox. Your code is valid for 10 minutes.',
                        '请查收邮件，验证码 10 分钟内有效。',
                      ),
                      prefixIcon: const Icon(Icons.pin_outlined),
                    ),
                    validator: (value) =>
                        RegExp(r'^\d{6}$').hasMatch(value ?? '')
                        ? null
                        : t('Enter the six-digit code', '请输入 6 位验证码'),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _locked ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: buttonSize,
                    shape: buttonShape,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                const SizedBox(height: 2),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    if (!_passwordMode && _challengeId != null) ...[
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
                    ] else
                      TextButton(
                        onPressed: _locked ? null : _changeMethod,
                        child: Text(
                          _passwordMode
                              ? t('Use an email code instead', '改用邮箱验证码')
                              : t('Sign in with a password', '使用密码登录'),
                        ),
                      ),
                  ],
                ),
                const Divider(height: 14),
                Text(
                  t(
                    'New here? Verifying your email creates your account. By continuing you agree to our',
                    '首次使用？验证邮箱即自动创建账号。继续即表示你同意',
                  ),
                  textAlign: TextAlign.center,
                  style: muted.copyWith(fontSize: 11.5),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (final page in ['terms', 'privacy'])
                      TextButton(
                        onPressed: () => _openPolicy(page),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

/// The four-colour Google "G" mark, drawn from Google's published 48×48 logo
/// paths so the sign-in button carries the recognisable brand symbol.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    excludeSemantics: true,
    child: CustomPaint(
      size: Size.square(size),
      painter: const _GoogleLogoPainter(),
    ),
  );
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    final paint = Paint()..isAntiAlias = true;
    canvas.drawPath(
      Path()
        ..moveTo(24, 9.5)
        ..cubicTo(27.54, 9.5, 30.71, 10.72, 33.21, 13.1)
        ..lineTo(40.06, 6.25)
        ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
        ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
        ..lineTo(10.54, 19.41)
        ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
        ..close(),
      paint..color = const Color(0xFFEA4335),
    );
    canvas.drawPath(
      Path()
        ..moveTo(46.98, 24.55)
        ..cubicTo(46.98, 22.98, 46.83, 21.46, 46.6, 20)
        ..lineTo(24, 20)
        ..lineTo(24, 29.02)
        ..lineTo(36.94, 29.02)
        ..cubicTo(36.36, 31.98, 34.68, 34.5, 32.16, 36.2)
        ..lineTo(39.89, 42.2)
        ..cubicTo(44.4, 38.02, 46.98, 31.84, 46.98, 24.55)
        ..close(),
      paint..color = const Color(0xFF4285F4),
    );
    canvas.drawPath(
      Path()
        ..moveTo(10.53, 28.59)
        ..cubicTo(10.05, 27.14, 9.77, 25.6, 9.77, 24)
        ..cubicTo(9.77, 22.4, 10.04, 20.86, 10.53, 19.41)
        ..lineTo(2.55, 13.22)
        ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
        ..cubicTo(0, 27.88, 0.92, 31.54, 2.56, 34.78)
        ..lineTo(10.53, 28.59)
        ..close(),
      paint..color = const Color(0xFFFBBC05),
    );
    canvas.drawPath(
      Path()
        ..moveTo(24, 48)
        ..cubicTo(30.48, 48, 35.93, 45.87, 39.89, 42.19)
        ..lineTo(32.16, 36.19)
        ..cubicTo(30.01, 37.64, 27.24, 38.49, 24, 38.49)
        ..cubicTo(17.74, 38.49, 12.43, 34.27, 10.53, 28.58)
        ..lineTo(2.55, 34.77)
        ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
        ..close(),
      paint..color = const Color(0xFF34A853),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
