#!/bin/bash

set -e

hash=$(git rev-parse --short HEAD)
zig=$(zig version)
host=$(hostname -s)
stamp=$(date -Iseconds)
mkdir -p "ref/bm"
bmfile="ref/bm/$host.txt"

zig build -Doptimize=ReleaseFast
echo "$stamp - $hash - $host - $zig" | tee -a $bmfile
zig-out/bin/bm-codec 2>&1 | tee -a $bmfile
zig-out/bin/bm-rocks 2>&1 | tee -a $bmfile

# vim:ts=2:sw=2:sts=2:et:ft=sh

