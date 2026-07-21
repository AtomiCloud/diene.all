#!/usr/bin/env bash
set -euo pipefail

while IFS= read -r variable; do unset "${variable}"; done < <(env | sed -n 's/^\(NIX_[A-Za-z0-9_]*\)=.*/\1/p')
unset CC CXX LD AR NM RANLIB OBJCOPY OBJDUMP STRIP CPP CXXCPP \
  SDKROOT MACOSX_DEPLOYMENT_TARGET LD_DYLD_PATH LIBRARY_PATH \
  DYLD_LIBRARY_PATH CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH

export DEVELOPER_DIR="${DEVELOPER_DIR_OVERRIDE:-/Applications/Xcode.app/Contents/Developer}"
export PATH="${PATH}:/usr/bin:/bin:/usr/sbin:/sbin"

exec flutter "$@"
