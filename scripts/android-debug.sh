#!/bin/zsh

set -euo pipefail

POSEY_ROOT="${0:A:h:h}"
POSEY_JAVA_HOME="${POSEY_JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"

if [[ ! -x "$POSEY_JAVA_HOME/bin/java" ]]; then
  print -u2 "找不到 Java 21：$POSEY_JAVA_HOME"
  exit 1
fi

cd "$POSEY_ROOT/android"
JAVA_HOME="$POSEY_JAVA_HOME" ./gradlew :app:assembleDebug
