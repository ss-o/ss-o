#!/usr/bin/env bash

set -eo pipefail

for dockerfile in $(echo Dockerfile.* | sort); do
	docker build -t "env:$(cut -d . -f 2- <<<"$dockerfile")" -f "$dockerfile" .
done
