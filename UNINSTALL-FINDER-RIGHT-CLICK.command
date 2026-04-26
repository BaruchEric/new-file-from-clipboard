#!/bin/zsh
set -euo pipefail

cd -- "$(dirname -- "$0")"

extension_id="com.ericbaruch.NewFileFromClipboard.FinderExtension"
built_app="$PWD/xcode-derived/Build/Products/Release/New File from Clipboard.app"

echo "Disabling New File from Clipboard Finder extension..."
pluginkit -e ignore -i "$extension_id" 2>/dev/null || true
if [[ -d "$built_app/Contents/PlugIns/NewFileFinderExtension.appex" ]]; then
	pluginkit -r "$built_app/Contents/PlugIns/NewFileFinderExtension.appex" 2>/dev/null || true
fi

echo "Restarting Finder..."
killall Finder 2>/dev/null || true

echo "Done. Press Return to close."
read -r _
