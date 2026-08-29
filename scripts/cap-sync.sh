#!/bin/zsh

set -euo pipefail

POSEY_ROOT="${0:A:h:h}"
POSEY_DEVELOPER_DIR="${POSEY_DEVELOPER_DIR:-$POSEY_ROOT/Xcode_26.1.1/Xcode.app/Contents/Developer}"
cd "$POSEY_ROOT"
npm run build

if [[ -x /opt/homebrew/opt/ruby/bin/ruby && -x /opt/homebrew/bin/pod && -d /opt/homebrew/opt/cocoapods/libexec ]]; then
  POSEY_RUBY_GEMS="$(/opt/homebrew/opt/ruby/bin/ruby -e 'print Gem.default_dir')"
  POSEY_POD_GEMS="/opt/homebrew/opt/cocoapods/libexec"
  DEVELOPER_DIR="$POSEY_DEVELOPER_DIR" \
    GEM_HOME="$POSEY_POD_GEMS" \
    GEM_PATH="$POSEY_POD_GEMS:$POSEY_RUBY_GEMS" \
    npx cap sync
else
  DEVELOPER_DIR="$POSEY_DEVELOPER_DIR" npx cap sync
fi
