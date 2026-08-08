import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/file_scanner.dart';
import '../services/local_organizer.dart';
import '../services/wifi_server.dart';

/// アプリの状態遷移（整理処理側）。
enum _Phase { idle, scanning, copying, done }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FileScanner _scanner = FileScanner();

  /// 整理先（端末内ストレージ直下の「整理整頓」フォルダ）。
  static const String _destinationRoot = '/storage/emulated/0/整理整頓';

  final WifiServer _server = WifiServer(_destinationRoot);

  _Phase _phase = _Phase.idle;
  int _scanFound = 0;
  OrganizeProgress? _progress;
  String _message = '';

  bool _sharing = false;
  String? _shareUrl;

  @override
  void dispose() {
    _server.stop();
    super.dispose();
  }

  /// ストレージ全体へのアクセス権限を要求する。
  Future<bool> _ensureStoragePermission() async {
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }
    final PermissionStatus status =
        await Permission.manageExternalStorage.request();
    if (status.isGranted) {
      return true;
    }
    if (await Permission.storage.request().isGranted) {
      return true;
    }
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    return false;
  }

  Future<void> _organize() async {
    if (!await _ensureStoragePermission()) {
      setState(() => _message = 'ストレージへのアクセス許可が必要です');
      return;
    }

    setState(() {
      _phase = _Phase.scanning;
      _scanFound = 0;
      _progress = null;
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
        _message = '対象のファイルが見つかりませんでした';
      });
      return;
    }

    setState(() => _phase = _Phase.copying);
    final LocalOrganizer organizer = LocalOrganizer(_destinationRoot);
    try {
      final OrganizeProgress result = await organizer.organize(
        files,
        onProgress: (OrganizeProgress p) {
          if (mounted) {
            setState(() => _progress = p);
          }
        },
      );
      setState(() {
        _phase = _Phase.done;
        _progress = result;
        _message = '整理が完了しました';
      });
    } catch (e) {
      setState(() {
        _phase = _Phase.done;
        _message = '整理中にエラーが発生しました: $e';
      });
    }
  }

  Future<void> _toggleShare() async {
    if (_sharing) {
      await _server.stop();
      setState(() {
        _sharing = false;
        _shareUrl = null;
      });
      return;
    }

    final String? url = await _server.start();
    if (url == null) {
      await _server.stop();
      setState(() {
        _sharing = false;
        _shareUrl = null;
        _message = 'WiFi に接続してから共有してください';
      });
      return;
    }
    setState(() {
      _sharing = true;
      _shareUrl = url;
      _message = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool busy = _phase == _Phase.scanning || _phase == _Phase.copying;
    return Scaffold(
      appBar: AppBar(title: const Text('整理整頓')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 8),
            const Icon(Icons.folder_copy_outlined, size: 64),
            const SizedBox(height: 16),
            const Text(
              '端末内のファイルをデータ形式ごとに分類して\n「整理整頓」フォルダにまとめ、WiFi で共有します。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '保存先: $_destinationRoot',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            _buildStatus(),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: busy ? null : _organize,
              icon: const Icon(Icons.cleaning_services),
              label: Text(busy ? '実行中…' : '① 整理する'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: busy ? null : _toggleShare,
              icon: Icon(_sharing ? Icons.stop : Icons.wifi),
              label: Text(_sharing ? '② 共有を停止' : '② WiFi で共有'),
            ),
            if (_shareUrl != null) ...<Widget>[
              const SizedBox(height: 20),
              _buildShareCard(),
            ],
            if (_message.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text(_message, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShareCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            const Text('パソコンやタブレットのブラウザで、\n同じ WiFi につないで下の URL を開いてください。',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            SelectableText(
              _shareUrl ?? '',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _shareUrl ?? ''));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('URL をコピーしました')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('URL をコピー'),
            ),
            const SizedBox(height: 4),
            Text(
              'この画面を開いている間だけ共有されます。',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus() {
    switch (_phase) {
      case _Phase.idle:
        return const Text(
          'まず「① 整理する」でファイルをまとめ、\n次に「② WiFi で共有」でパソコンから受け取れます。',
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
      case _Phase.copying:
        final OrganizeProgress? p = _progress;
        final double? value =
            (p != null && p.total > 0) ? p.done / p.total : null;
        return Column(
          children: <Widget>[
            LinearProgressIndicator(value: value),
            const SizedBox(height: 16),
            if (p != null) Text('コピー中… ${p.done} / ${p.total}'),
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
        final OrganizeProgress? p = _progress;
        return Column(
          children: <Widget>[
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 8),
            if (p != null)
              Text(
                'コピー ${p.copied} 件 / スキップ ${p.skipped} 件'
                '${p.failed > 0 ? ' / 失敗 ${p.failed} 件' : ''}',
                textAlign: TextAlign.center,
              ),
          ],
        );
    }
  }
}
