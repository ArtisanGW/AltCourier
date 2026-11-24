#!/bin/sh
# Runs every test outside the game. From anywhere: tests/run.sh
cd "$(dirname "$0")/.." || exit 1
set -e
luajit tests/name_test.lua
luajit tests/mailbox_test.lua open
luajit tests/mailbox_test.lua covered
luajit tests/categories_test.lua
luajit tests/exclusions_test.lua
luajit tests/release_test.lua
echo "all tests passed"
