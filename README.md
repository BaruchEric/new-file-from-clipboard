# New File from Clipboard

Finder right-click extension for creating a new `.txt` file from the clipboard in the current Finder folder.

## Use

Run:

```sh
./INSTALL-FINDER-RIGHT-CLICK.command
```

Then right-click blank space inside a Finder window and choose **New File from Clipboard**.

The file name is suggested from the clipboard text. If a file already exists, the extension adds a number.

## Important

Finder is registered to the built app here:

```text
xcode-derived/Build/Products/Release/New File from Clipboard.app
```

Do not delete `xcode-derived/Build/Products/Release/New File from Clipboard.app` unless you plan to run the installer again.

## Project Layout

- `FinderExtension/` - Objective-C source, Info.plists, and entitlements.
- `NewFileFromClipboard.xcodeproj/` - generated Xcode project.
- `scripts/make-xcode-project.rb` - regenerates the Xcode project.
- `INSTALL-FINDER-RIGHT-CLICK.command` - main installer.
- `XCODE-BUILD-AND-INSTALL.command` - Xcode build/sign/register script.
- `xcode-derived/Build/Products/Release/New File from Clipboard.app` - active app registered with Finder.

## Debug

The extension writes a small trace here:

```text
~/Library/Logs/NewFileFromClipboard.log
```
