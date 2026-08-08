# ファイル同期 (index3)

端末（Android）内のファイルを**データ形式ごとに分類**して、**Googleドライブへ一括アップロード**するアプリです。標準の画像フォルダに限らずストレージ全体を横断的に走査するため、「アプリが独自の場所に保存した画像」なども拾えます。

- **初回起動**: Googleアカウントを選んで認証
- **2回目以降**: 自動サインイン → 「今すぐ同期」ボタンで実行
- **Drive上の保存先**:

  ```
  MobileFileSync/
    2026-08-08/          ← 同期を実行した日付
      画像/   … .jpg .png .heic ...
      動画/   … .mp4 .mov ...
      音声/   … .mp3 .m4a ...
      書類/   … .pdf .docx .txt ...
      圧縮/   … .zip ...
      その他/ … 上記以外
  ```

> 仕様メモ: 重複判定は行わず**毎回すべてアップロード**します（シンプルさ優先）。同じ日に複数回実行すると、同じ日付フォルダ内にファイルが重ねて追加されます。

---

## プロジェクト構成

```
lib/
  main.dart                     アプリのエントリポイント
  models/file_category.dart     データ形式の分類ロジック（拡張子 → カテゴリ）
  services/
    auth_service.dart           Googleサインイン & Drive APIクライアント発行
    file_scanner.dart           ストレージ走査 & 分類
    drive_uploader.dart         Driveへのフォルダ作成 & アップロード
  screens/home_screen.dart      画面（サインイン / 同期・進捗表示）
test/
  file_category_test.dart       分類ロジックのユニットテスト
android/                        Android固有の設定（権限・ビルド設定など）
```

---

## セットアップ

### 1. 前提

- [Flutter SDK](https://docs.flutter.dev/get-started/install)（3.19 以上）
- Android Studio もしくは Android SDK
- 対象端末: **Android 8.0 (API 26) 以上**

### 2. 依存関係の取得

```bash
flutter pub get
```

> このリポジトリには Gradle Wrapper のバイナリ (`gradle/wrapper/gradle-wrapper.jar`) が含まれていません。初回は Android Studio でプロジェクトを開くか、`flutter build apk` を実行すると自動生成されます。うまくいかない場合は一度だけ次を実行して不足ファイルを補ってください（既存の `lib/` は保持されます）:
>
> ```bash
> flutter create --platforms=android --org com.sumika --project-name index3 .
> ```

### 3. Google認証の設定（**必須**）

Googleサインインと Drive API を使うため、Google Cloud 側の設定が必要です。

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクトを作成
2. **APIとサービス → ライブラリ** で **Google Drive API** を有効化
3. **APIとサービス → OAuth 同意画面** を設定
   - User type: 外部（テスト中は自分のアカウントを「テストユーザー」に追加）
   - スコープに `.../auth/drive.file` を追加
4. **APIとサービス → 認証情報 → OAuth クライアント ID を作成**
   - アプリケーションの種類: **Android**
   - パッケージ名: `com.sumika.index3`（変更した場合は `android/app/build.gradle` の `applicationId` に合わせる）
   - **SHA-1 証明書フィンガープリント**: 下記コマンドで取得した debug 用の SHA-1 を登録

     ```bash
     keytool -list -v \
       -alias androiddebugkey \
       -keystore ~/.android/debug.keystore \
       -storepass android -keypass android
     ```

> Android の `google_sign_in` は、パッケージ名 + SHA-1 が一致する OAuth クライアントを使って認証します。**`google-services.json` は不要**です（もし配置する場合も認証情報なのでコミットしないでください）。
>
> リリース用に署名鍵を分ける場合は、その鍵の SHA-1 も OAuth クライアントに追加登録してください。

### 4. 実行

```bash
flutter run
```

初回起動でアカウント選択 → 認証 → ストレージアクセス許可（「すべてのファイルへのアクセス」）を与えると、「今すぐ同期」でアップロードが始まります。

---

## 権限について

「アプリが保存した画像など、どこにあるか分からないファイルも拾う」という要件のため、Android 11 以降では **すべてのファイルへのアクセス (MANAGE_EXTERNAL_STORAGE)** を使用しています。初回同期時にシステム設定画面での許可が求められます。

> 注: `MANAGE_EXTERNAL_STORAGE` を使うアプリを Google Play で公開する場合、用途の審査が必要です。個人利用（自分の端末に直接インストール）なら審査は不要です。

---

## 動作の流れ

1. `signInSilently()` で自動サインインを試行（初回はボタンから `signIn()`）
2. `FileScanner` が `/storage/emulated/0` 以下を再帰走査し、`categorize()` で形式ごとに分類
   - 隠しディレクトリ、`Android/`（OSがアクセスを制限）などはスキップ
3. `DriveUploader` が `MobileFileSync/<日付>/<形式>/` のフォルダを用意し、各ファイルをアップロード
   - 1ファイルの失敗では止まらず、失敗件数を集計して継続

## テスト

```bash
flutter test
```
