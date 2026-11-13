# Nobilva Student (iOS)

## TestFlight への配信

「TestFlight に上げて」「配信して」と頼まれたら、次の手順でそのまま配信まで進めてよい。

1. 配信したい変更がコミット済みであることを確認する（`scripts/testflight.sh` は未コミットの変更があると止まる）。
2. ビルド番号 `CURRENT_PROJECT_VERSION` を 1 つ上げてコミットする。
   - `NobilvaStudent.xcodeproj/project.pbxproj` の Debug / Release の 2 か所をそろえて書き換える。
   - 同じ番号は二度とアップロードできない。
   - `MARKETING_VERSION` がすでにリリース済みだと、そのバージョンではビルドを出せない（エラー 90186 / 90062）。その場合は `MARKETING_VERSION` も上げる。リリース済みかどうか分からないときはユーザーに確認する。
3. `scripts/testflight.sh` を実行する（数分かかるのでバックグラウンドで実行する）。
   - Xcode に登録済みの Apple ID で署名・アップロードする。App Store Connect API キーを使う場合は `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_PATH` を渡す。
   - 成果物は `build/testflight/<version>-<build>/` に出る（git 管理外）。

輸出コンプライアンス（暗号化の質問）は `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` で回答済み。アプリは OS 標準の HTTPS 以外の暗号化を使っていないので、この回答でよい。独自の暗号化を入れたときは見直す。
