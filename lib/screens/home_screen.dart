import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:permission_handler/permission_handler.dart';

import '../services/auth_service.dart';
import '../services/drive_uploader.dart';
import '../services/file_scanner.dart';

/// アプリの状態遷移。
enum _Phase { idle, scanning, uploading, done }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _auth = AuthService();
  final FileScanner _scanner = FileScanner();

  _Phase _phase = _Phase.idle;
  GoogleSignInAccount? _account;

  int _scanFound = 0;
  UploadProgress? _upload;
  String _message = '';

  @override
  void initState() {
    super.initState();
    // 2回目以降は自動サインインを試みる。
    _auth.signInSilently().then((GoogleSignInAccount? user) {
      if (mounted) {
        setState(() => _account = user);
      }
    });
  }

  Future<void> _handleSignIn() async {
    try {
      final GoogleSignInAccount? user = await _auth.signIn();
      setState(() {
        _account = user;
        _message = user == null ? 'サインインがキャンセルされました' : '';
      });
    } catch (e) {
      setState(() => _message = 'サインインに失敗しました: $e');
    }
  }

  Future<void> _handleSignOut() async {
    await _auth.signOut();
    setState(() {
      _account = null;
      _phase = _Phase.idle;
      _message = '';
    });
  }

  /// ストレージ全体へのアクセス権限を要求する。
  ///
  /// Android 11 (API 30) 以降は「すべてのファイルへのアクセス」
  /// (MANAGE_EXTERNAL_STORAGE) が必要。許可されていない場合は
  /// 設定画面へ誘導する。
  Future<bool> _ensureStoragePermission() async {
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }
    final PermissionStatus status =
        await Permission.manageExternalStorage.request();
    if (status.isGranted) {
      return true;
    }

    // 旧APIのフォールバック。
    if (await Permission.storage.request().isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    return false;
  }

  Future<void> _startSync() async {
    if (!await _ensureStoragePermission()) {
      setState(() => _message = 'ストレージへのアクセス許可が必要です');
      return;
    }

    final drive.DriveApi? api = await _auth.getDriveApi();
    if (api == null) {
      setState(() => _message = '認証情報を取得できませんでした。再度サインインしてください。');
      return;
    }

    // スキャン
    setState(() {
      _phase = _Phase.scanning;
      _scanFound = 0;
      _upload = null;
      _message = '';
    });

    final List<ScannedFile> files = await _scanner.scan(
      onProgress: (int found) {
        if (mounted) {
          setState(() => _scanFound = found);
        }
      },
    );

    if (files.isEmpty) {
      setState(() {
        _phase = _Phase.done;
        _message = 'アップロード対象のファイルが見つかりませんでした';
      });
      return;
    }

    // アップロード
    setState(() => _phase = _Phase.uploading);
    final DriveUploader uploader = DriveUploader(api);
    try {
      await uploader.uploadAll(
        files,
        dateFolderName: _todayFolderName(),
        onProgress: (UploadProgress p) {
          if (mounted) {
            setState(() => _upload = p);
          }
        },
      );
      setState(() {
        _phase = _Phase.done;
        _message = '同期が完了しました';
      });
    } catch (e) {
      setState(() {
        _phase = _Phase.done;
        _message = 'アップロード中にエラーが発生しました: $e';
      });
    }
  }

  /// `YYYY-MM-DD` 形式の日付フォルダ名。
  String _todayFolderName() {
    final DateTime now = DateTime.now();
    final String y = now.year.toString().padLeft(4, '0');
    final String m = now.month.toString().padLeft(2, '0');
    final String d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ファイル同期'),
        actions: <Widget>[
          if (_account != null)
            IconButton(
              tooltip: 'サインアウト',
              icon: const Icon(Icons.logout),
              onPressed: _handleSignOut,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: _account == null ? _buildSignIn() : _buildSignedIn(),
        ),
      ),
    );
  }

  Widget _buildSignIn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.cloud_upload_outlined, size: 72),
        const SizedBox(height: 16),
        const Text(
          '端末内のファイルをデータ形式ごとに分類して\nGoogleドライブに一括コピーします。',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _handleSignIn,
          icon: const Icon(Icons.login),
          label: const Text('Googleアカウントでサインイン'),
        ),
        if (_message.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text(_message, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }

  Widget _buildSignedIn() {
    final bool busy = _phase == _Phase.scanning || _phase == _Phase.uploading;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'アカウント: ${_account?.email ?? ''}',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        _buildStatus(),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: busy ? null : _startSync,
          icon: const Icon(Icons.sync),
          label: Text(busy ? '実行中…' : '今すぐ同期'),
        ),
        if (_message.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text(_message, textAlign: TextAlign.center),
        ],
      ],
    );
  }

  Widget _buildStatus() {
    switch (_phase) {
      case _Phase.idle:
        return const Text(
          '「今すぐ同期」を押すと、ストレージを走査して\nアップロードを開始します。',
          textAlign: TextAlign.center,
        );
      case _Phase.scanning:
        return Column(
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('ファイルを検索中… ($_scanFound 件)'),
          ],
        );
      case _Phase.uploading:
        final UploadProgress? p = _upload;
        final double? value =
            (p != null && p.total > 0) ? p.done / p.total : null;
        return Column(
          children: <Widget>[
            LinearProgressIndicator(value: value),
            const SizedBox(height: 16),
            if (p != null)
              Text('アップロード中… ${p.done} / ${p.total}'
                  '${p.failed > 0 ? '（失敗 ${p.failed}）' : ''}'),
            if (p != null && p.currentName.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                p.currentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      case _Phase.done:
        final UploadProgress? p = _upload;
        return Column(
          children: <Widget>[
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 8),
            if (p != null)
              Text('${p.done} 件をアップロードしました'
                  '${p.failed > 0 ? '（失敗 ${p.failed}）' : ''}'),
          ],
        );
    }
  }
}
