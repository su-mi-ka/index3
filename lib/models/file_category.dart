/// スキャンしたファイルを「データ形式」で分類するためのカテゴリ定義。
///
/// [folderName] はそのままGoogleドライブ上のサブフォルダ名として使われる。
enum FileCategory {
  image('画像'),
  video('動画'),
  audio('音声'),
  document('書類'),
  archive('圧縮'),
  other('その他');

  const FileCategory(this.folderName);

  /// Googleドライブ上に作成されるサブフォルダ名。
  final String folderName;
}

/// 拡張子 → カテゴリの対応表。
const Map<FileCategory, List<String>> _extensionMap = <FileCategory, List<String>>{
  FileCategory.image: <String>[
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'tiff', 'tif',
    'svg', 'ico', 'raw', 'dng',
  ],
  FileCategory.video: <String>[
    'mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v', 'flv', 'wmv', 'mpg',
    'mpeg', 'ts',
  ],
  FileCategory.audio: <String>[
    'mp3', 'wav', 'aac', 'flac', 'ogg', 'oga', 'm4a', 'wma', 'opus', 'amr',
    'mid', 'midi',
  ],
  FileCategory.document: <String>[
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'tsv',
    'md', 'rtf', 'odt', 'ods', 'odp', 'epub', 'json', 'xml', 'html', 'htm',
  ],
  FileCategory.archive: <String>[
    'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'apk',
  ],
};

/// ファイルパス（または拡張子）からデータ形式のカテゴリを判定する。
FileCategory categorize(String path) {
  final int dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) {
    return FileCategory.other;
  }
  final String ext = path.substring(dot + 1).toLowerCase();
  for (final MapEntry<FileCategory, List<String>> entry in _extensionMap.entries) {
    if (entry.value.contains(ext)) {
      return entry.key;
    }
  }
  return FileCategory.other;
}
