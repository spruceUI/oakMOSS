#!/usr/bin/env bash
# make-hybrid-zero40-stock.sh: the zero40 stock-chain image. One recipe serves both boards;
# see scripts/make-hybrid-stock.sh.
exec "$(dirname "$0")/make-hybrid-stock.sh" zero40 "$@"
