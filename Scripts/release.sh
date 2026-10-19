#!/bin/zsh
# Builds, signs and publishes a GitHub release.
#   Scripts/release.sh 0.2.0          # bump version, commit, tag, build, upload
#   Scripts/release.sh 0.2.0 --dry    # bump + build + zip only (no commit/tag/upload)
# Requires the "T-Utilities Dev" signing certificate in the login keychain and `gh` logged in.
set -euo pipefail

VERSION=${1:?usage: Scripts/release.sh <version> [--dry]}
DRY=${2:-}
ROOT=${0:A:h:h}
cd "$ROOT"

[[ $VERSION =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "version must be X.Y.Z"; exit 1; }
[[ -z $DRY && -n $(git status --porcelain) ]] && { echo "working tree is not clean"; exit 1; }

BUILD=$(( $(sed -n 's/.*CFBundleVersion: "\([0-9]*\)".*/\1/p' project.yml) + 1 ))
sed -i '' -e "s/CFBundleShortVersionString: \".*\"/CFBundleShortVersionString: \"$VERSION\"/" \
          -e "s/CFBundleVersion: \".*\"/CFBundleVersion: \"$BUILD\"/" project.yml

xcodegen generate
xcodebuild -project T-Utilities.xcodeproj -scheme T-Utilities -configuration Release \
  -derivedDataPath build/DerivedData clean build | grep -E "error:|BUILD" || true

APP=build/DerivedData/Build/Products/Release/T-Utilities.app
codesign --verify --deep --strict "$APP"
codesign -dr - "$APP" 2>&1 | grep -q 'certificate leaf' || { echo "app is not signed with the T-Utilities Dev certificate"; exit 1; }
[[ $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString) == $VERSION ]]

ZIP=build/T-Utilities-$VERSION.zip
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "built $ZIP"
[[ -n $DRY ]] && exit 0

git commit -qam "Release $VERSION"
git tag "v$VERSION"
git push -q origin HEAD "v$VERSION"
gh release create "v$VERSION" "$ZIP" --title "T-Utilities $VERSION" --generate-notes
