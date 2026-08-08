import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

/// Googleアカウントの選択・認証と、Drive APIクライアントの発行を担当する。
///
/// スコープは `drive.file` のみ。これは「このアプリが作成／アップロードした
/// ファイルだけ」にアクセスできる最小権限で、ユーザーの既存のDrive内容を
/// 読み取ることはできない（アップロード用途にはこれで十分）。
class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[drive.DriveApi.driveFileScope],
  );

  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  /// アカウント選択ダイアログを表示して明示的にサインインする（初回起動時）。
  Future<GoogleSignInAccount?> signIn() async {
    _currentUser = await _googleSignIn.signIn();
    return _currentUser;
  }

  /// 2回目以降の起動で、ダイアログを出さずに自動サインインを試みる。
  Future<GoogleSignInAccount?> signInSilently() async {
    _currentUser = await _googleSignIn.signInSilently();
    return _currentUser;
  }

  /// サインアウト（アカウント連携の解除）。
  Future<void> signOut() async {
    await _googleSignIn.disconnect();
    _currentUser = null;
  }

  /// 認証済みのDrive APIクライアントを取得する。
  ///
  /// 未サインインの場合はサイレントサインインを試み、それでも取得できなければ
  /// `null` を返す。
  Future<drive.DriveApi?> getDriveApi() async {
    _currentUser ??= await signInSilently();
    if (_currentUser == null) {
      return null;
    }
    final authClient = await _googleSignIn.authenticatedClient();
    if (authClient == null) {
      return null;
    }
    return drive.DriveApi(authClient);
  }
}
