#!/bin/zsh
set -euo pipefail

: "${SPARKLE_GENERATE_APPCAST:?Set SPARKLE_GENERATE_APPCAST to Sparkle's generate_appcast executable}"

script_dir=${0:A:h}
release_version=${1:?Usage: ./generate-appcast.sh <version, for example 1.0.4>}
downloads_dir="$script_dir/public/downloads"
release_base="$downloads_dir/NookFlow-$release_version"

required_release_files=(
  "$release_base.dmg"
  "$release_base.html"
  "$release_base.zh.html"
  "$release_base.en.html"
)

for required_file in "${required_release_files[@]}"; do
  if [[ ! -s "$required_file" ]]; then
    print -u2 "Missing required release file: $required_file"
    print -u2 "Every update must include default, Chinese, and English release notes."
    exit 1
  fi
done

"$SPARKLE_GENERATE_APPCAST" \
  --download-url-prefix "https://nookflow.luckysoft.cn/downloads/" \
  --release-notes-url-prefix "https://nookflow.luckysoft.cn/downloads/" \
  --link "https://nookflow.luckysoft.cn/" \
  -o "$script_dir/public/appcast.xml" \
  "$downloads_dir"

plutil -lint "$script_dir/../App/Info.plist"
xmllint --noout "$script_dir/public/appcast.xml"
