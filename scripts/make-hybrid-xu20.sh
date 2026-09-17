#!/usr/bin/env bash
# make-hybrid-xu20.sh: the xu20 stock-chain image. One recipe serves both boards;
# see scripts/make-hybrid-stock.sh.
exec "$(dirname "$0")/make-hybrid-stock.sh" xu20 "$@"
