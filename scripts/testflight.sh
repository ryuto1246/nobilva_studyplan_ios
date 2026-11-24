#!/bin/zsh
# NobilvaStudent を Archive して App Store Connect (TestFlight) にアップロードする。
#
# 使い方:
#   scripts/testflight.sh
#
# 認証:
#   - 既定では Xcode に登録済みの Apple ID (Xcode > Settings > Accounts) を使う。
#   - App Store Connect API キーを使う場合は次の 3 つを環境変数で渡す。
#       ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (AuthKey_XXXX.p8 のパス。リポジトリには置かない)
#
# 輸出コンプライアンス (暗号化の質問) は project.pbxproj の
# INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO で回答済みなので、
# アップロード後に App Store Connect で手動回答する必要はない。
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

SCHEME=NobilvaStudent
PROJECT=NobilvaStudent.xcodeproj
TEAM_ID=638Z73V9XS
PBXPROJ="$PROJECT/project.pbxproj"

# 未コミットの変更があると、何を配信したか後から追えなくなる
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: 未コミットの変更があります。コミットしてから実行してください。" >&2
  git status --short >&2
  exit 1
fi

VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed -E 's/.*= ([^;]+);/\1/')
BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed -E 's/.*= ([^;]+);/\1/')
COMMIT=$(git rev-parse --short HEAD)
echo "==> $SCHEME $VERSION ($BUILD) @ $COMMIT を TestFlight に上げます"

OUT="$ROOT/build/testflight/$VERSION-$BUILD"
ARCHIVE="$OUT/$SCHEME.xcarchive"
rm -rf "$OUT"
mkdir -p "$OUT"

AUTH_ARGS=(-allowProvisioningUpdates)
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
  AUTH_ARGS+=(
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
    -authenticationKeyPath "$ASC_KEY_PATH"
  )
fi

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "==> Archive"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  "${AUTH_ARGS[@]}" \
  -quiet

echo "==> Upload to App Store Connect"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" \
  "${AUTH_ARGS[@]}"

echo "==> 完了: $VERSION ($BUILD) をアップロードしました。App Store Connect の処理が終わると TestFlight に出ます。"
