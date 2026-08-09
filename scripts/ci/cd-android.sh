#!/usr/bin/env bash
set -euo pipefail

echo "📦 Building the raichu Android donor..."
mkdir -p "${HOME}/.gradle"
gradle_properties="${HOME}/.gradle/gradle.properties"
touch "${gradle_properties}"
rg -q '^kotlin.compiler.execution.strategy=' "${gradle_properties}" || printf '%s\n' 'kotlin.compiler.execution.strategy=in-process' >>"${gradle_properties}"
rg -q '^org.gradle.jvmargs=' "${gradle_properties}" || printf '%s\n' 'org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g -XX:ReservedCodeCacheSize=320m' >>"${gradle_properties}"
rg -q '^org.gradle.caching=' "${gradle_properties}" || printf '%s\n' 'org.gradle.caching=true' >>"${gradle_properties}"

flutter pub get
flutter build appbundle \
  --release \
  --flavor raichu \
  --build-number=1 \
  --build-name=1.0.0 \
  --dart-define=FLUTTER_BASE_LANDSCAPE=raichu

echo "✅ Android donor built"
