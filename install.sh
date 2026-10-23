#!/bin/bash
# VoxLook installer.
#
#   curl -fsSL https://raw.githubusercontent.com/Springfolk/voxlook/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/Springfolk/voxlook/main/install.sh | bash -s -- --uninstall
#
# Options:
#   --from <VoxLook.app|VoxLook.zip>   install a local build instead of downloading
#   --uninstall                        remove VoxLook
#   --no-finder-restart                don't relaunch Finder (stale icons stay until you do)
set -euo pipefail

REPO="Springfolk/voxlook"
URL="https://github.com/$REPO/releases/latest/download/VoxLook.zip"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

from="" uninstall=0 restart_finder=1
while [ $# -gt 0 ]; do
  case "$1" in
    --from) from="$2"; shift 2 ;;
    --uninstall) uninstall=1; shift ;;
    --no-finder-restart) restart_finder=0; shift ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "VoxLook is for macOS."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || die "VoxLook needs macOS 14 or later."

# /Applications when we can write there, else ~/Applications (no sudo needed).
if [ -w /Applications ]; then dest=/Applications; else dest="$HOME/Applications"; mkdir -p "$dest"; fi
app="$dest/VoxLook.app"
for candidate in /Applications/VoxLook.app "$HOME/Applications/VoxLook.app"; do
  [ -d "$candidate" ] && app="$candidate" && dest=$(dirname "$candidate")
done

unregister() {
  [ -d "$app" ] || return 0
  pluginkit -r "$app/Contents/PlugIns/VoxLookPreview.appex" 2>/dev/null || true
  pluginkit -r "$app/Contents/PlugIns/VoxLookThumbnail.appex" 2>/dev/null || true
  "$LSREGISTER" -u "$app" 2>/dev/null || true
}

refresh_quick_look() {
  qlmanage -r >/dev/null 2>&1 || true
  qlmanage -r cache >/dev/null 2>&1 || true
  # The thumbnail agent remembers which extension handles a type; launchd restarts it.
  pkill -9 -f com.apple.quicklook.ThumbnailsAgent 2>/dev/null || true
  if [ "$restart_finder" = 1 ] && pgrep -xq Finder; then
    say "Relaunching Finder so it drops cached icons"
    killall Finder 2>/dev/null || true
  fi
}

pkill -x VoxLook 2>/dev/null || true

if [ "$uninstall" = 1 ]; then
  [ -d "$app" ] || die "VoxLook isn't installed."
  say "Removing $app"
  unregister
  rm -rf "$app"
  refresh_quick_look
  say "Uninstalled."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -z "$from" ]; then
  say "Downloading the latest VoxLook"
  curl -fsSL --retry 3 -o "$tmp/VoxLook.zip" "$URL" || die "download failed: $URL"
  from="$tmp/VoxLook.zip"
fi
case "$from" in
  *.zip) ditto -x -k "$from" "$tmp/unzipped"; src="$tmp/unzipped/VoxLook.app" ;;
  *) src="$from" ;;
esac
[ -d "$src/Contents/PlugIns/VoxLookThumbnail.appex" ] || die "not a VoxLook build: $from"

say "Installing to $app"
unregister
rm -rf "$app"
ditto "$src" "$app"
xattr -dr com.apple.quarantine "$app" 2>/dev/null || true

"$LSREGISTER" -f -R "$app"
pluginkit -a "$app/Contents/PlugIns/VoxLookPreview.appex"
pluginkit -a "$app/Contents/PlugIns/VoxLookThumbnail.appex"
pluginkit -e use -i co.springfolk.voxlook.preview
pluginkit -e use -i co.springfolk.voxlook.thumbnail
importer="$app/Contents/Library/Spotlight/VoxLook.mdimporter"
if [ -d "$importer" ]; then
  # Spotlight runs a new importer only on files that change; reindex existing .vox files now.
  say "Indexing existing .vox files for Spotlight"
  mdimport -r "$importer" >/dev/null 2>&1 || true
fi
refresh_quick_look

pluginkit -m -i co.springfolk.voxlook.thumbnail | grep -q voxlook || die "the thumbnail extension didn't register; open $app once and try again."
version=$(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
say "VoxLook $version installed. Select a .vox file in Finder and press Space."
