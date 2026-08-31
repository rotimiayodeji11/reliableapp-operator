#!/usr/bin/env bash
set -euo pipefail
mkdir -p evidence
go test -race ./... 2>&1 | tee evidence/go-race.log
