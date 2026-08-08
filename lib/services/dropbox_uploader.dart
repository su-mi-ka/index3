import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'file_scanner.dart';

/// アップロードの進捗。
class UploadProgress {
  const UploadProgress({
    required this.done,
    required this.total,
    required this.currentName,
    this.failed = 0,
  });

  final int done;
  final int total;
  final int failed;
  final String currentName;
}

/// 分類済みファイルを Dropbox（App folder）へアップロードする。
///
/// 保存パスはアプリ専用フォルダを基準に `/<日付>/<データ形式>/<ファイル名>`。
/// Dropbox 側で親フォルダは自動作成される。`autorename` を有効にしているので、
/// 同名ファイルがあっても上書きせずリネームして保存する（毎回すべてアップロード）。
class DropboxUploader {
  DropboxUploader(this._accessToken);

  final String _accessToken;

  /// 150MB 以上はアップロードセッションを使う（単純アップロードの上限のため）。
  static const int _sessionThreshold = 140 * 1024 * 1024;
  static const int _chunkSize = 8 * 1024 * 1024;

  Future<void> uploadAll(
    List<ScannedFile> files, {
    required String dateFolderName,
    void Function(UploadProgress progress)? onProgress,
  }) async {
    int done = 0;
    int failed = 0;
    for (final ScannedFile sf in files) {
      final String name = _basename(sf.file.path);
      onProgress?.call(UploadProgress(
        done: done,
        total: files.length,
        failed: failed,
        currentName: name,
      ));

      final String path = '/$dateFolderName/${sf.category.folderName}/$name';
      try {
        final int length = await sf.file.length();
        if (length < _sessionThreshold) {
          await _simpleUpload(sf.file, path);
        } else {
          await _sessionUpload(sf.file, path, length);
        }
      } catch (_) {
        // 1 ファイルの失敗で全体を止めない。
        failed++;
      }
      done++;
    }

    onProgress?.call(UploadProgress(
      done: done,
      total: files.length,
      failed: failed,
      currentName: '',
    ));
  }

  Future<void> _simpleUpload(File file, String path) async {
    final Uint8List bytes = await file.readAsBytes();
    final http.Response resp = await http.post(
      Uri.parse('https://content.dropboxapi.com/2/files/upload'),
      headers: <String, String>{
        'Authorization': 'Bearer $_accessToken',
        'Dropbox-API-Arg': _asciiSafe(jsonEncode(<String, dynamic>{
          'path': path,
          'mode': 'add',
          'autorename': true,
          'mute': true,
        })),
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
    );
    if (resp.statusCode != 200) {
      throw HttpException('upload failed ${resp.statusCode}: ${resp.body}');
    }
  }

  Future<void> _sessionUpload(File file, String path, int length) async {
    final RandomAccessFile raf = await file.open();
    try {
      final List<int> first = await raf.read(_chunkSize);
      final http.Response startResp = await http.post(
        Uri.parse('https://content.dropboxapi.com/2/files/upload_session/start'),
        headers: <String, String>{
          'Authorization': 'Bearer $_accessToken',
          'Dropbox-API-Arg': jsonEncode(<String, dynamic>{'close': false}),
          'Content-Type': 'application/octet-stream',
        },
        body: first,
      );
      if (startResp.statusCode != 200) {
        throw HttpException('session start failed ${startResp.statusCode}');
      }
      final String sessionId =
          (jsonDecode(startResp.body) as Map<String, dynamic>)['session_id']
              as String;
      int offset = first.length;

      while (offset < length) {
        final List<int> chunk = await raf.read(_chunkSize);
        if (chunk.isEmpty) {
          break;
        }
        final bool isLast = offset + chunk.length >= length;
        if (isLast) {
          final http.Response finishResp = await http.post(
            Uri.parse(
                'https://content.dropboxapi.com/2/files/upload_session/finish'),
            headers: <String, String>{
              'Authorization': 'Bearer $_accessToken',
              'Dropbox-API-Arg': _asciiSafe(jsonEncode(<String, dynamic>{
                'cursor': <String, dynamic>{
                  'session_id': sessionId,
                  'offset': offset,
                },
                'commit': <String, dynamic>{
                  'path': path,
                  'mode': 'add',
                  'autorename': true,
                  'mute': true,
                },
              })),
              'Content-Type': 'application/octet-stream',
            },
            body: chunk,
          );
          if (finishResp.statusCode != 200) {
            throw HttpException('session finish failed ${finishResp.statusCode}');
          }
        } else {
          final http.Response appendResp = await http.post(
            Uri.parse(
                'https://content.dropboxapi.com/2/files/upload_session/append_v2'),
            headers: <String, String>{
              'Authorization': 'Bearer $_accessToken',
              'Dropbox-API-Arg': jsonEncode(<String, dynamic>{
                'cursor': <String, dynamic>{
                  'session_id': sessionId,
                  'offset': offset,
                },
                'close': false,
              }),
              'Content-Type': 'application/octet-stream',
            },
            body: chunk,
          );
          if (appendResp.statusCode != 200) {
            throw HttpException('session append failed ${appendResp.statusCode}');
          }
        }
        offset += chunk.length;
      }
    } finally {
      await raf.close();
    }
  }

  /// Dropbox-API-Arg ヘッダーは ASCII のみ許容されるため、
  /// 非 ASCII 文字（日本語のフォルダ名・ファイル名など）を \uXXXX に変換する。
  String _asciiSafe(String value) {
    final StringBuffer buffer = StringBuffer();
    for (final int unit in value.codeUnits) {
      if (unit > 0x7F) {
        buffer.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
      } else {
        buffer.writeCharCode(unit);
      }
    }
    return buffer.toString();
  }

  String _basename(String path) {
    final int slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
