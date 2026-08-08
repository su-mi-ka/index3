import 'package:googleapis/drive/v3.dart' as drive;

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

/// 分類済みファイルを、Googleドライブに
/// `MobileFileSync / <日付> / <データ形式>` の階層で一括アップロードする。
///
/// フォルダ構成の例:
/// ```
/// MobileFileSync/
///   2026-08-08/
///     画像/  … .jpg .png ...
///     動画/  … .mp4 ...
///     書類/  … .pdf ...
/// ```
class DriveUploader {
  DriveUploader(this._api);

  final drive.DriveApi _api;

  /// Drive上のルートフォルダ名。
  static const String rootFolderName = 'MobileFileSync';

  static const String _folderMime = 'application/vnd.google-apps.folder';

  /// 同一実行内でフォルダを重複作成しないためのキャッシュ（キー: 親ID/名前）。
  final Map<String, String> _folderCache = <String, String>{};

  /// 指定した親フォルダ配下に、名前 [name] のフォルダを確保する。
  ///
  /// 既存の同名フォルダがあればそのIDを、無ければ新規作成してIDを返す。
  /// （フォルダは日付単位で使い回すため、同じ日に複数回同期しても
  ///  日付フォルダは増えない。ファイル自体は毎回アップロードされる。）
  Future<String> _ensureFolder(String name, {String? parentId}) async {
    final String cacheKey = '${parentId ?? 'root'}/$name';
    final String? cached = _folderCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final String parentClause =
        "'${parentId ?? 'root'}' in parents";
    final String query = "mimeType='$_folderMime' and "
        "name='${_escape(name)}' and trashed=false and $parentClause";

    final drive.FileList existing = await _api.files.list(
      q: query,
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    if (existing.files != null && existing.files!.isNotEmpty) {
      final String id = existing.files!.first.id!;
      _folderCache[cacheKey] = id;
      return id;
    }

    final drive.File metadata = drive.File()
      ..name = name
      ..mimeType = _folderMime
      ..parents = parentId != null ? <String>[parentId] : null;
    final drive.File created = await _api.files.create(metadata);
    final String id = created.id!;
    _folderCache[cacheKey] = id;
    return id;
  }

  /// Driveのクエリ文字列内で使う値のエスケープ。
  String _escape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  /// [files] をまとめてアップロードする。
  ///
  /// [dateFolderName] は日付フォルダ名（例: `2026-08-08`）。
  /// 失敗したファイルはスキップして継続し、失敗件数を進捗で通知する。
  Future<void> uploadAll(
    List<ScannedFile> files, {
    required String dateFolderName,
    void Function(UploadProgress progress)? onProgress,
  }) async {
    final String rootId = await _ensureFolder(rootFolderName);
    final String dateId = await _ensureFolder(dateFolderName, parentId: rootId);

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

      try {
        final String categoryId =
            await _ensureFolder(sf.category.folderName, parentId: dateId);
        final int length = await sf.file.length();
        final drive.Media media = drive.Media(sf.file.openRead(), length);
        final drive.File meta = drive.File()
          ..name = name
          ..parents = <String>[categoryId];
        await _api.files.create(meta, uploadMedia: media);
      } catch (_) {
        // 1ファイルの失敗で全体を止めない。
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

  String _basename(String path) {
    final int slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
