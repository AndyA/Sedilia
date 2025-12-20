#!/bin/bash

set -e

bm_node() {
  node bin/mule.js 
}

bm_deno() {
  deno run --allow-read --unstable-detect-cjs bin/mule.js 
}

bm_bun() {
  bun run bin/mule.js
}

bm_python3() {
  python3 bin/mule.py
}

for interp in node deno bun python3; do
  if which $interp >/dev/null 2>&1; then
    echo "# Benchmark: $interp"
    time "bm_$interp"
    echo
  else
    echo "# Skipping missing interpreter: $interp"
  fi
done

# vim:ts=2:sw=2:sts=2:et:ft=sh

