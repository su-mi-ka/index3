# ファイル同期 (index3)

端末（Android）内のファイルを**データ形式ごとに分類**して、**Dropbox へ一括アップロード**するアプリです。標準の画像フォルダに限らずストレージ全体を横断的に走査するため、「アプリが独自の場所に保存した画像」なども拾えます。

- **初回起動**: Dropbox でサインイン（ブラウザで許可するだけ。SHA-1 登録も同意画面も不要）
- **2回目以降**: 自動サインイン → 「今すぐ同期」ボタンで実行
- **Dropbox 上の保存先**（アプリ専用フォルダ内）:

  ```
  /アプリ/index3 File Sync/       ← Dropbox の「App folder」
    2026-08-08/                    ← 同期を実行した日付
      画像/   … .jpg .png .heic ...
      動画/   … .mp4 .mov ...
      音声/   … .mp3 .m4a ...
      書類/   … .pdf .docx .txt ...
      圧縮/   … .zip ...
      その他/ … 上記以外
  ```

> 仕様メモ: 重複判定は行わず**毎回すべてアップロード**します。同名ファイルは上書きせず自動でリネーム（`ファイル (1).jpg` など）されます。

---

## GitHub でビルドする（ローカル環境不要）

GitHub Actions のワークフロー (`.github/workflows/build.yml`) が入っており、**ブランチにプッシュするたびにクラウド上で APK がビルド**され、`latest` リリースに添付されます。

1. まず下記「Dropbox のセットアップ」で App key を用意
2. GitHub の **Actions** タブ →「Build APK」を実行（`workflow_dispatch` で手動実行も可）
3. APK を取得:
   - **Releases** の `latest`（スマホから直接ダウンロードしやすい）:
     `https://github.com/su-mi-ka/index3/releases/download/latest/app-release.apk`
   - もしくは実行結果ページ下部の **Artifacts** → `index3-release-apk`
4. APK を端末に入れて「提供元不明のアプリ」を許可してインストール

> APK は動作確認用の署名（debug 鍵）でビルドされます。自分の端末にサイドロードする分には問題なく使えます（Dropbox 認証は署名鍵に依存しません）。

---

## Dropbox のセットアップ（最初に一度だけ）

1. [Dropbox App Console](https://www.dropbox.com/developers/apps) で **Create app**
   - **Scoped access** を選択
   - **App folder** を選択（アプリ専用フォルダのみにアクセス。安全）
   - 任意の名前（例: `index3 File Sync`）を付ける
2. 作成したアプリの **Settings** タブ:
   - **App key** をメモ（これをビルドに使う）
   - **Redirect URIs** に次を追加:
     `index3sync://oauth2redirect`
3. **Permissions** タブで以下にチェックして **Submit**:
   - `files.content.write`
   - `files.content.read`（任意。将来の重複判定などに使う場合）
4. **Build APK** を実行 → `latest` リリースの APK をインストール → アプリで **Dropbox でサインイン**

> App key は `lib/services/dropbox_auth_service.dart` に既定値として埋め込んでいます（App key は秘密情報ではなく、配布アプリに必ず含まれる公開値のため）。**App secret は PKCE 方式では使いません**（埋め込まない）。
>
> 別の Dropbox アプリに差し替えたい場合は、`appKey` の既定値を変更するか、ビルド時に
> `flutter run --dart-define=DROPBOX_APP_KEY=あなたのAppKey` で上書きしてください（GitHub の Variable `DROPBOX_APP_KEY` を設定した場合はそちらが優先されます）。

---

## 権限について

「アプリが保存した画像など、どこにあるか分からないファイルも拾う」という要件のため、Android 11 以降では **すべてのファイルへのアクセス (MANAGE_EXTERNAL_STORAGE)** を使用しています。初回同期時にシステム設定画面での許可が求められます。

> 注: `MANAGE_EXTERNAL_STORAGE` を使うアプリを Google Play で公開する場合は用途の審査が必要ですが、個人利用（自分の端末に直接インストール）なら審査は不要です。

---

## プロジェクト構成

```
lib/
  main.dart                       アプリのエントリポイント
  models/file_category.dart       データ形式の分類ロジック（拡張子 → カテゴリ）
  services/
    dropbox_auth_service.dart     Dropbox の OAuth (PKCE) 認証・トークン管理
    dropbox_uploader.dart         Dropbox へのアップロード（大容量はセッション対応）
    file_scanner.dart             ストレージ走査 & 分類
  screens/home_screen.dart        画面（サインイン / 同期・進捗表示）
test/
  file_category_test.dart         分類ロジックのユニットテスト
android/                          Android固有の設定（権限・OAuth コールバックなど）
```

## 動作の流れ

1. `restoreSession()` で保存済みリフレッシュトークンから自動サインイン（初回はボタンから `signIn()`）
2. `FileScanner` が `/storage/emulated/0` 以下を再帰走査し、`categorize()` で形式ごとに分類
3. `DropboxUploader` が `/<日付>/<形式>/` のパスへ各ファイルをアップロード（親フォルダは自動作成、同名は自動リネーム）
   - 1ファイルの失敗では止まらず、失敗件数を集計して継続

## テスト

```bash
flutter test
```

## ローカルで動かす場合

```bash
flutter pub get
flutter run --dart-define=DROPBOX_APP_KEY=あなたのAppKey
```

> Gradle Wrapper のバイナリ (`gradle/wrapper/gradle-wrapper.jar`) は含めていません。Android Studio で開くか `flutter build apk` 実行時に自動生成されます。
