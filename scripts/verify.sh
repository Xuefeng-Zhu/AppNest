#!/usr/bin/env bash
set -euo pipefail
appnest_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$appnest_root"
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed appnest_server/lib appnest_server/test appnest_server/bin appnest_client/bin appnest_flutter/lib appnest_flutter/test packages scripts
cd "$appnest_root/packages/appnest_spec"
dart test
cd "$appnest_root/packages/appnest_renderer"
flutter test
cd "$appnest_root/appnest_flutter"
flutter test
cd "$appnest_root/appnest_server"
dart test --concurrency=1
cd "$appnest_root"
dart run scripts/restart_smoke.dart
