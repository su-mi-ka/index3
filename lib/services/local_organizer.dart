import 'dart:io';

import 'file_scanner.dart';

/// 整理（コピー）の進捗・結果。
class OrganizeProgress {
  const OrganizeProgress({
    required this.done,
    required this.total,
    required this.currentName,
    this.copied = 0,
    this.skipped = 0,
    this.failed = 0,
  });

  final int done;
  final int total;
  final int copied;
  final int skipped;
  final int failed;
  final String currentName;
}

/// 分類済みファイルを端末内の整理フォルダへコピーする。
///
/// コピー先は `<destinationRoot>/<データ形式>/<ファイル名>`。
/// 同名・同サイズのファイルが既にある場合はスキップ（再実行しても重複しない）。
/// 同名でサイズが違う場合は `名前 (1).拡張子` のようにリネームして残す。
class LocalOrganizer {
  LocalOrganizer(this.destinationRoot);

  /// 整理先のルート（例: `/storage/emulated/0/整理整頓`）。
  final String destinationRoot;

  Future<OrganizeProgress> organize(
    List<ScannedFile> files, {
    void Function(OrganizeProgress progress)? onProgress,
  }) async {
    int done = 0;
    int copied = 0;
    int skipped = 0;
    int failed = 0;

    for (final ScannedFile sf in files) {
      final String name = _basename(sf.file.path);
      onProgress?.call(OrganizeProgress(
        done: done,
        total: files.length,
        currentName: name,
        copied: copied,
        skipped: skipped,
        failed: failed,
      ));

      try {
        final Directory dir =
            Directory('$destinationRoot/${sf.category.folderName}');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        final int srcLen = await sf.file.length();
        File target = File('${dir.path}/$name');
        if (await target.exists()) {
          if (await target.length() == srcLen) {
            // 同名・同サイズはコピー済みとみなしてスキップ。
            skipped++;
            done++;
            continue;
          }
          target = File('${dir.path}/${_uniqueName(dir.path, name)}');
        }

        await sf.file.copy(target.path);
        copied++;
      } catch (_) {
        // 1 ファイルの失敗で全体を止めない。
        failed++;
      }
      done++;
    }

    final OrganizeProgress result = OrganizeProgress(
      done: done,
      total: files.length,
      currentName: '',
      copied: copied,
      skipped: skipped,
      failed: failed,
    );
    onProgress?.call(result);
    return result;
  }

  /// `dir` 内で衝突しないファイル名を作る（`名前 (1).拡張子` 形式）。
  String _uniqueName(String dir, String name) {
    final int dot = name.lastIndexOf('.');
    final String base = dot > 0 ? name.substring(0, dot) : name;
    final String ext = dot > 0 ? name.substring(dot) : '';
    int i = 1;
    while (true) {
      final String candidate = '$base ($i)$ext';
      if (!File('$dir/$candidate').existsSync()) {
        return candidate;
      }
      i++;
    }
  }

  String _basename(String path) {
    final int slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
