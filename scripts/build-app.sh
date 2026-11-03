#!/bin/zsh
# Builds dist/Vigil.app (Universal, ad-hoc signed) and dist/Vigil-<version>.zip.
set -euo pipefail
cd "${0:A:h}/.."

version=${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}
version=${version:-0.0.0}

# Universal builds need full Xcode, not just the Command Line Tools.
if [[ -z ${DEVELOPER_DIR:-} && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release --arch arm64 --arch x86_64
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Vigil

app=dist/Vigil.app
rm -rf dist
mkdir -p $app/Contents/MacOS $app/Contents/Resources
cp $bin $app/Contents/MacOS/Vigil
cp Resources/AppIcon.icns $app/Contents/Resources/
sed "s/VERSION/$version/g" Resources/Info.plist > $app/Contents/Info.plist
codesign --force --sign - $app

ditto -c -k --keepParent $app dist/Vigil-$version.zip
echo "Built $app ($version): $(lipo -archs $app/Contents/MacOS/Vigil)"
