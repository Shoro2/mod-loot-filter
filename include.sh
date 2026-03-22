#!/usr/bin/env bash

MOD_LOOT_FILTER_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

source "$MOD_LOOT_FILTER_ROOT/conf/conf.sh.dist"

if [ -f "$MOD_LOOT_FILTER_ROOT/conf/conf.sh" ]; then
    source "$MOD_LOOT_FILTER_ROOT/conf/conf.sh"
fi
