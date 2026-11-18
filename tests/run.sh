#!/bin/sh
# Runs every test outside the game. From anywhere: tests/run.sh
cd "$(dirname "$0")/.." || exit 1
set -e
luajit tests/name_test.lua
luajit tests/plugin_test.lua DeliveriesForever.lua vanilla
luajit tests/plugin_test.lua DeliveriesForever.lua daylight
echo "all tests passed"
