#!/usr/bin/env bash
# Cloudflare Pages build command: `bash scripts/cloudflare-build.sh`, output directory `dist`.
# The Pages image has no .NET, so install the SDK pinned in global.json and the WebAssembly workload first.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_VERSION="$(python3 -c 'import json; print(json.load(open("global.json"))["sdk"]["version"])')"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
if ! "$DOTNET_ROOT/dotnet" --list-sdks 2>/dev/null | grep -q "^$SDK_VERSION "; then
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  bash /tmp/dotnet-install.sh --version "$SDK_VERSION" --install-dir "$DOTNET_ROOT" --no-path
fi
export PATH="$DOTNET_ROOT:$PATH" DOTNET="$DOTNET_ROOT/dotnet"
dotnet workload install wasm-tools --skip-manifest-update
python3 scripts/build.py
