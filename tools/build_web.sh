#!/bin/bash
# Exports the web build and wraps it for publishing as an artifact (../build/site).
set -e
cd "$(dirname "$0")/.."
G=/home/claude/godot/Godot_v4.6.2-stable_linux.x86_64
rm -rf ../build/web && mkdir -p ../build/web
$G --headless --import >/dev/null 2>&1 || true
$G --headless --export-release "Web" ../build/web/index.html 2>&1 | grep -E "ERROR|error" | head -5 || true
rm -rf ../build/site && python3 tools/mkshell.py ../build/web ../build/site
ls -la ../build/site
