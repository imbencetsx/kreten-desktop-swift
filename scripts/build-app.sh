#!/bin/zsh
# Builds a release KRETEN.app into build/ (ad-hoc signed, runs on this Mac).
set -e
set -o pipefail
cd "${0:A:h}/.."
xcodebuild -project Kreten.xcodeproj -scheme Kreten -configuration Release -derivedDataPath build/DerivedData build | grep -E "error:|warning:|BUILD"
rm -rf build/KRETEN.app
cp -R build/DerivedData/Build/Products/Release/KRETEN.app build/
echo "→ $(pwd)/build/KRETEN.app"
