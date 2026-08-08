import 'package:flutter_test/flutter_test.dart';
import 'package:index3/models/file_category.dart';

void main() {
  group('categorize', () {
    test('画像の拡張子を image に分類する', () {
      expect(categorize('/storage/emulated/0/DCIM/photo.JPG'),
          FileCategory.image);
      expect(categorize('a.png'), FileCategory.image);
      expect(categorize('a.heic'), FileCategory.image);
    });

    test('動画・音声・書類・圧縮を正しく分類する', () {
      expect(categorize('movie.mp4'), FileCategory.video);
      expect(categorize('song.mp3'), FileCategory.audio);
      expect(categorize('report.pdf'), FileCategory.document);
      expect(categorize('backup.zip'), FileCategory.archive);
    });

    test('未知・拡張子なしは other に分類する', () {
      expect(categorize('unknown.xyz'), FileCategory.other);
      expect(categorize('README'), FileCategory.other);
      expect(categorize('name.'), FileCategory.other);
    });
  });
}
