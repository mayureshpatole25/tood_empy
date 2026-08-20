#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
scratch_dir="$(mktemp -d /tmp/empy-tood-window-geometry.XXXXXX)"
trap 'rm -rf "$scratch_dir"' EXIT

xcrun swiftc \
  -module-cache-path "$scratch_dir/module-cache" \
  "$project_root/Empy Tood/StickyWindowGeometry.swift" \
  "$project_root/scripts/WindowGeometryRegression.swift" \
  -o "$scratch_dir/window-geometry-regression"

"$scratch_dir/window-geometry-regression"
