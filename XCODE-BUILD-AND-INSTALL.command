#!/bin/zsh
set -euo pipefail

cd -- "$(dirname -- "$0")"

team_id="${DEVELOPMENT_TEAM:-NSQB6N5244}"
export DEVELOPMENT_TEAM="$team_id"
scheme="New File from Clipboard"
project="NewFileFromClipboard.xcodeproj"
derived="xcode-derived"
built_app="$PWD/$derived/Build/Products/Release/New File from Clipboard.app"
old_app="/Applications/New File from Clipboard.app"
extension_id="com.ericbaruch.NewFileFromClipboard.FinderExtension"

echo "Preparing Xcode-managed Finder extension build..."
ruby scripts/make-xcode-project.rb >/dev/null

echo
echo "Building with Xcode automatic signing..."
rm -rf "$derived"
xcodebuild \
	-quiet \
	-project "$project" \
	-scheme "$scheme" \
	-configuration Release \
	-derivedDataPath "$derived" \
	-destination "platform=macOS" \
	-allowProvisioningUpdates \
	DEVELOPMENT_TEAM="$team_id" \
	build

if [[ ! -d "$built_app" ]]; then
	echo "Xcode build finished, but the app was not found at:"
	echo "  $built_app"
	echo
	echo "Press Return to close."
	read -r _
	exit 1
fi

echo
echo "Verifying Xcode-built signature..."
codesign --verify --deep --strict --verbose=4 "$built_app"
codesign -dv --verbose=4 "$built_app/Contents/PlugIns/NewFileFinderExtension.appex" 2>&1 \
	| /usr/bin/grep -E "Identifier=|TeamIdentifier=|Runtime|flags=|Authority=" || true

echo
echo "Removing older hand-built /Applications copy..."
if [[ -d "$old_app" ]]; then
	sudo rm -rf "$old_app"
fi

echo
echo "Registering Finder extension..."
pluginkit -r "$built_app/Contents/PlugIns/NewFileFinderExtension.appex" 2>/dev/null || true
killall pkd 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$built_app" || true
pluginkit -v -a "$built_app" || true
pluginkit -v -a "$built_app/Contents/PlugIns/NewFileFinderExtension.appex" || true
pluginkit -v -e use -i "$extension_id" || true

echo
echo "Finder extension registry:"
pluginkit -m -p com.apple.FinderSync -i "$extension_id" -v || true
echo
echo "All records for New File from Clipboard:"
pluginkit -m -A -D -vv 2>/dev/null | /usr/bin/grep -i -A 12 -B 8 "New File\\|Clipboard\\|com.ericbaruch" || true

echo
echo "Restarting Finder..."
killall Finder 2>/dev/null || true

echo
echo "Xcode-managed app path:"
echo "  $built_app"
echo "Done. Right-click blank space in Finder and look for New File from Clipboard."
echo "Press Return to close."
read -r _
