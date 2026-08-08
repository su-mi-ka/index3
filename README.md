# 整理整頓 (index3)

端末（Android）内のファイルを**データ形式ごとに分類**して、端末内の **`整理整頓` フォルダにまとめてコピー**するアプリです。標準の画像フォルダに限らずストレージ全体を横断的に走査するため、「アプリが独自の場所に保存した画像」なども拾えます。

クラウドもアカウントも不要。整理してできた 1 フォルダを、あとから **USB メモリ・SD カード・パソコン・予備スマホ**へ好きにコピーできます。

- **保存先**: `/storage/emulated/0/整理整頓/`

  ```
  整理整頓/
    画像/   … .jpg .png .heic ...
    動画/   … .mp4 .mov ...
    音声/   … .mp3 .m4a ...
    書類/   … .pdf .docx .txt ...
    圧縮/   … .zip ...
    その他/ … 上記以外
  ```

> 仕様メモ: 同名・同サイズのファイルが既にある場合はスキップ（再実行しても重複しません）。同名でサイズが違う場合は `名前 (1).拡張子` としてリネーム保存します。

---

## 使い方

1. `latest` リリースから APK をダウンロードしてインストール
   （「提供元不明のアプリ」を許可）:
   `https://github.com/su-mi-ka/index3/releases/download/latest/app-release.apk`
2. アプリを開いて **「整理する」** をタップ
3. **「すべてのファイルへのアクセス」** を許可（初回のみ）
4. 走査 → `整理整頓` フォルダへ形式ごとにコピー
5. 端末の「ファイル」アプリなどで `整理整頓` フォルダを開き、USB・SD・PC などへコピー

### USB / 予備スマホ / PC への移し方

- **USB メモリ（USB-OTG）/ SD カード**: 端末の「ファイル」アプリで `整理整頓` を選び、コピー＆貼り付け
- **パソコン**: ケーブルで接続 → `整理整頓` フォルダをドラッグでコピー
- **robocopy を使う場合（Windows）**: いったん `整理整頓` を SD カードや USB、または PC 上にコピーしてから、

  ```bat
  robocopy "E:\整理整頓" "D:\backup\整理整頓" /E /XO
  ```

  のように使えます。
  ※ robocopy はスマホの MTP 接続（ドライブ文字が付かない）には直接使えないため、
  一度ドライブ文字の付く場所（SD/USB/PC 内）に置いてから実行してください。

---

## GitHub でビルドする（ローカル環境不要）

GitHub Actions のワークフロー (`.github/workflows/build.yml`) が入っており、**ブランチにプッシュするたびにクラウド上で APK がビルド**され、`latest` リリースに添付されます。

1. **Actions** タブ →「Build APK」を実行（`workflow_dispatch` で手動実行も可）
2. **Releases** の `latest`、または実行結果の **Artifacts** から APK を取得
3. 端末にインストール

> APK は動作確認用の署名（debug 鍵）でビルドされます。自分の端末にサイドロードする分には問題なく使えます。

---

## 権限について

「アプリが保存した画像など、どこにあるか分からないファイルも拾う」という要件のため、Android 11 以降では **すべてのファイルへのアクセス (MANAGE_EXTERNAL_STORAGE)** を使用しています。初回実行時にシステム設定画面での許可が求められます。

---

## プロジェクト構成

```
lib/
  main.dart                     アプリのエントリポイント
  models/file_category.dart     データ形式の分類ロジック（拡張子 → カテゴリ）
  services/
    file_scanner.dart           ストレージ走査 & 分類
    local_organizer.dart        整理整頓フォルダへのコピー（重複スキップ）
  screens/home_screen.dart      画面（整理・進捗表示）
test/
  file_category_test.dart       分類ロジックのユニットテスト
android/                        Android固有の設定（権限・ビルド設定など）
```

## 動作の流れ

1. `FileScanner` が `/storage/emulated/0` 以下を再帰走査し、`categorize()` で形式ごとに分類
   （隠しディレクトリ、`Android/`、出力先の `整理整頓/` はスキップ）
2. `LocalOrganizer` が `整理整頓/<形式>/` へ各ファイルをコピー
   - 同名・同サイズはスキップ、同名別サイズはリネーム、失敗は集計して継続

## テスト

```bash
flutter test
```

## ローカルで動かす場合

```bash
flutter pub get
flutter run
```

> Gradle Wrapper のバイナリ (`gradle/wrapper/gradle-wrapper.jar`) は含めていません。Android Studio で開くか `flutter build apk` 実行時に自動生成されます。
