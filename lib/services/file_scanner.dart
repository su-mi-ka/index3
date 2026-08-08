import 'dart:io';

import '../models/file_category.dart';

/// スキャンで見つかった1ファイルと、その分類結果。
class ScannedFile {
  ScannedFile(this.file, this.category);

  final File file;
  final FileCategory category;
}

/// 端末ストレージを再帰的にスキャンし、見つかったファイルを
/// データ形式ごとに分類する。
///
/// 標準の画像フォルダに限らずストレージ全体を横断的に走査するため、
/// 「アプリが独自の場所に保存した画像」なども拾える。
class FileScanner {
  /// 走査をスキップするディレクトリ名（隠しディレクトリは別途 `.` 判定でスキップ）。
  ///
  /// `Android/data` `Android/obb` はOSの制約でアクセスできず例外の元になるため除外。
  static const Set<String> _skipDirNames = <String>{
    'Android',
    'cache',
    'Cache',
    '.thumbnails',
    'LOST.DIR',
  };

  /// 走査対象のルート。既定では内部ストレージのユーザー領域。
  static const List<String> defaultRoots = <String>[
    '/storage/emulated/0',
  ];

  /// [roots] 以下を走査し、分類済みファイルの一覧を返す。
  ///
  /// [onProgress] は見つかったファイル数の途中経過を通知する（任意）。
  Future<List<ScannedFile>> scan({
    List<String>? roots,
    void Function(int found)? onProgress,
  }) async {
    final List<ScannedFile> results = <ScannedFile>[];
    for (final String root in roots ?? defaultRoots) {
      final Directory dir = Directory(root);
      if (!await dir.exists()) {
        continue;
      }
      await _walk(dir, results, onProgress);
    }
    return results;
  }

  Future<void> _walk(
    Directory dir,
    List<ScannedFile> out,
    void Function(int found)? onProgress,
  ) async {
    final List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      // 権限のないディレクトリなどはスキップして走査を継続する。
      return;
    }

    for (final FileSystemEntity entity in entries) {
      final String name = _basename(entity.path);
      if (name.startsWith('.')) {
        continue;
      }
      if (entity is Directory) {
        if (_skipDirNames.contains(name)) {
          continue;
        }
        await _walk(entity, out, onProgress);
      } else if (entity is File) {
        out.add(ScannedFile(entity, categorize(entity.path)));
        onProgress?.call(out.length);
      }
    }
  }

  String _basename(String path) {
    final int slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
