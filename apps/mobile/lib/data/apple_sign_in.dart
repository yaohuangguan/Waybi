import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

abstract class AppleSignInGateway {
  Future<Map<String, String>> authorize();
}

class NativeAppleSignInGateway implements AppleSignInGateway {
  @override
  Future<Map<String, String>> authorize() async {
    final random = Random.secure();
    String nonce() => List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final rawNonce = nonce();
    final state = nonce();
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      state: state,
    );
    if (credential.state != state ||
        credential.identityToken == null ||
        credential.authorizationCode.isEmpty) {
      throw StateError('Apple did not return a valid authorization');
    }
    return {
      'identityToken': credential.identityToken!,
      'authorizationCode': credential.authorizationCode,
      'rawNonce': rawNonce,
      'fullName': [
        credential.givenName,
        credential.familyName,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' '),
    };
  }
}
