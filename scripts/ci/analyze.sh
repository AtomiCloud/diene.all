#!/usr/bin/env bash
set -euo pipefail

dart pub get >/dev/null
dart analyze --fatal-infos
