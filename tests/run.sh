#!/bin/sh
# Runs every test outside the game. From anywhere: tests/run.sh
cd "$(dirname "$0")/.." || exit 1
set -e
luajit tests/name_test.lua
luajit tests/mailbox_test.lua DeliveriesForever.lua open
luajit tests/mailbox_test.lua DeliveriesForever.lua covered
echo "all tests passed"
