# Nobilva 学習計画 iOS (生徒向け)

Next.js 版 `../nobilva_study_plan` の**生徒機能**を SwiftUI ネイティブに移植したアプリ。
API はすべて Web 側の `/api/v1/auth/mobile/**` と `/api/v1/student/**` を叩く。

## 動作環境

- Xcode 26 以降 (iOS 26 SDK)
- iOS 17.0+ 端末 / Simulator
- 外部依存: **なし** (SwiftPM 依存もゼロ、`import` は SwiftUI / Foundation / AuthenticationServices / PhotosUI / Charts / UIKit / os のみ)

## Simulator でビルドして起動

```bash
xcodebuild \
  -project NobilvaStudent.xcodeproj \
  -scheme NobilvaStudent \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  build

# Simulator に install & 起動
xcrun simctl boot 'iPhone 17' 2>/dev/null || true
open -a Simulator
BUILT=$(xcodebuild -project NobilvaStudent.xcodeproj -scheme NobilvaStudent -showBuildSettings 2>/dev/null | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')
xcrun simctl install booted "$BUILT/NobilvaStudent.app"
xcrun simctl launch booted com.nobilva.app
```

Xcode で開くなら `NobilvaStudent.xcodeproj` をダブルクリックで OK。
`NobilvaStudent/` フォルダは `PBXFileSystemSynchronizedRootGroup` で参照しているので、
ファイル追加は Finder / エディタで置くだけで自動的にビルド対象になる (pbxproj を触る必要なし)。

## 実機ビルドに必要な設定

Signing & Capabilities で以下を行う (初回のみ):

1. **Team ID** を Xcode > Signing で選択 (自動 provisioning)。
2. Bundle ID `com.nobilva.app` はそのまま。
3. **Associated Domains** を追加 (Capability を + から追加):
   ```
   webcredentials:studyplan.nobilva.jp
   applinks:studyplan.nobilva.jp
   ```
   これを入れないと Passkey ログインが動かない。
4. Web 側の `APPLE_APP_ID` env に `<TEAM_ID>.com.nobilva.app` を設定 (AASA を返す)。

## アーキテクチャ概要

- **MVVM 軽量版**: `Features/<Domain>/{View, ViewModel?, Repository}`。
- **API**: `Networking/APIClient.swift` (URLSession actor)。`Envelope<T>` で `{ data: T }` を剥がす。401 で自動 refresh & retry。
- **Auth**: `Auth/AuthStore.swift` (@MainActor ObservableObject)。`access_token` はメモリのみ、`refresh_token` は Keychain。
- **Passkey**: `Auth/PasskeyClient.swift` (`ASAuthorizationController` ラッパ)。ログインのみ (登録は Web)。
- **JST 固定**: 日付処理は全て `Core/JSTDate.swift` 経由。
- **Liquid Glass**: `DesignSystem/GlassBackground.swift` の 1 箇所にだけ集約。Blur は他で使わない (パフォーマンス)。

## API ベース URL

`APIClient.baseURL = https://studyplan.nobilva.jp` (`Networking/APIClient.swift`)。
別環境で試すときはここを書き換える。

## 実装済み画面 / 未実装

**画面 (実装済)**:
- ログイン (パスワード + パスキー)
- ホーム (Dashboard summary で 1 リクエスト)
- 計画 (期間一覧 → 日別詳細 → AI 生成)
- タイマー (ポモドーロ / タイマー / ストップウォッチ / 手動記録)
- タスク (CRUD, 期限切れセクション, 複製, 完了 toggle)
- 参考書ゴール (追加 / 進捗更新 / 削除)
- チャット (スレッド一覧, 15 秒 polling, 画像添付 (JPEG 圧縮), 既読)
- 面談 (一覧 / 詳細 / キャンセル / リスケ希望 / 別日時提案 / 提案受諾拒否)
- 履歴 (Swift Charts で 7 日の学習時間 + XP/レベル/ストリーク)
- 使えない時間 (追加 / 削除 / チームイベント opt-out)
- 設定 (アカウント / 学習 / ポモドーロ / 通知 / セキュリティ)
- 使い方 / XP ガイド

**未実装 / 後回し**:
- APNs プッシュ通知 (Web の LINE 通知に任せる)
- チャットの WebSocket リアルタイム (現状 15 秒 polling)
- LINE Login 連携 UI (endpoint は動くが LINE SDK を仕込んでない)
- パスキー "登録" (mobile API 未実装。Web で登録する導線を Settings に置いてある)
- ダークモード最適化 (システム標準のマテリアルで自動追従はするが、細部の確認はまだ)

## Info.plist / Permissions

pbxproj の Build Settings で以下を宣言:

- `NSCameraUsageDescription`: チャットで写真を撮影して送信するために使用します。
- `NSPhotoLibraryUsageDescription`: チャットに写真を添付するために使用します。
- Deployment Target: iOS 17.0
- Bundle Identifier: `com.nobilva.app`

Info.plist は `GENERATE_INFOPLIST_FILE = YES` により Xcode が自動生成。

## ディレクトリ

```
NobilvaStudent/
├── App/                   # @main, RootView, MainTabView
├── Core/                  # JSTDate, Keychain, Log
├── Networking/            # APIClient, Envelope, APIError
├── Auth/                  # AuthStore, PasskeyClient, SessionModels
├── Models/                # Codable ドメイン型
├── DesignSystem/          # Theme, Card, TodoRow, TimerRing, ChatAvatar, GlassBar
├── Features/
│   ├── Login/
│   ├── Dashboard/
│   ├── Plan/
│   ├── Tasks/
│   ├── Timer/
│   ├── Goals/
│   ├── Chat/
│   ├── Meetings/
│   ├── History/
│   ├── BusySlots/
│   ├── Guide/
│   ├── Settings/
│   └── _Stubs.swift       # MoreMenuView など
└── Preview Content/
```

## ライセンス

Private。
