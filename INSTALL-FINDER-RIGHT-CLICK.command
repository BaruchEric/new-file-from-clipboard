#!/bin/zsh
set -euo pipefail

cd -- "$(dirname -- "$0")"
exec ./XCODE-BUILD-AND-INSTALL.command
