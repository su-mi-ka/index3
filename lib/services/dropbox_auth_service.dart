import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

/// Dropbox のアカウント認証を担当する。
///
/// モバイル向けの OAuth 2.0 PKCE フローを使う（クライアントシークレット不要）。
/// `token_access_type=offline` でリフレッシュトークンを取得し、端末に安全に
/// 保存する。2 回目以降の起動ではリフレッシュトークンから新しいアクセストークンを
/// 取得するため、再ログインは不要。
///
/// 権限は「App folder」を想定。アプリ専用フォルダ以外にはアクセスできない。
class DropboxAuthService {
  /// Dropbox アプリの App key。ビルド時に
  /// `--dart-define=DROPBOX_APP_KEY=xxxxx` で注入する。
  static const String appKey = String.fromEnvironment('DROPBOX_APP_KEY');

  /// OAuth リダイレクトのカスタムスキーム（AndroidManifest / Dropbox コンソールと一致させる）。
  static const String _callbackScheme = 'index3sync';
  static const String _redirectUri = 'index3sync://oauth2redirect';

  static const String _refreshTokenKey = 'dropbox_refresh_token';

  final FlutterSecureStorage _storage = FlutterSecureStorage();

  String? _accessToken;
  String? get accessToken => _accessToken;

  /// App key が設定されているか。
  bool get isConfigured => appKey.isNotEmpty;

  /// 保存済みのログイン（リフレッシュトークン）があるか。
  Future<bool> hasSavedLogin() async {
    final String? token = await _storage.read(key: _refreshTokenKey);
    return token != null && token.isNotEmpty;
  }

  /// 保存済みのリフレッシュトークンからアクセストークンを復元する（自動サインイン）。
  Future<bool> restoreSession() async {
    final String? refresh = await _storage.read(key: _refreshTokenKey);
    if (refresh == null || refresh.isEmpty) {
      return false;
    }
    return _refreshAccessToken(refresh);
  }

  /// ブラウザで Dropbox にログインして認可する（初回サインイン）。
  Future<bool> signIn() async {
    if (!isConfigured) {
      throw StateError('DROPBOX_APP_KEY が設定されていません');
    }

    final String verifier = _randomString(64);
    final String challenge = _codeChallenge(verifier);

    final String authUrl = Uri.https('www.dropbox.com', '/oauth2/authorize', <String, String>{
      'client_id': appKey,
      'response_type': 'code',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'token_access_type': 'offline',
      'redirect_uri': _redirectUri,
    }).toString();

    final String result = await FlutterWebAuth2.authenticate(
      url: authUrl,
      callbackUrlScheme: _callbackScheme,
    );
    final String? code = Uri.parse(result).queryParameters['code'];
    if (code == null) {
      return false;
    }

    final http.Response resp = await http.post(
      Uri.https('api.dropboxapi.com', '/oauth2/token'),
      body: <String, String>{
        'code': code,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
        'client_id': appKey,
        'redirect_uri': _redirectUri,
      },
    );
    if (resp.statusCode != 200) {
      return false;
    }
    final Map<String, dynamic> data =
        jsonDecode(resp.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String?;
    final String? refresh = data['refresh_token'] as String?;
    if (refresh != null && refresh.isNotEmpty) {
      await _storage.write(key: _refreshTokenKey, value: refresh);
    }
    return _accessToken != null;
  }

  Future<bool> _refreshAccessToken(String refresh) async {
    final http.Response resp = await http.post(
      Uri.https('api.dropboxapi.com', '/oauth2/token'),
      body: <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
        'client_id': appKey,
      },
    );
    if (resp.statusCode != 200) {
      return false;
    }
    final Map<String, dynamic> data =
        jsonDecode(resp.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String?;
    return _accessToken != null;
  }

  /// サインアウト（保存したリフレッシュトークンを削除）。
  Future<void> signOut() async {
    _accessToken = null;
    await _storage.delete(key: _refreshTokenKey);
  }

  String _randomString(int length) {
    const String chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final Random rand = Random.secure();
    return List<String>.generate(
      length,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  String _codeChallenge(String verifier) {
    final Digest digest = sha256.convert(ascii.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
