#!/bin/sh
# Unpacks a UI shard's downloaded build: sh scripts/ci-unpack-build.sh <tar> <into> <artifact name>
#
# The download can arrive cut short with no error from download-artifact: tar then says "Truncated tar archive" and no
# test runs, though other shards unpacked the same artifact whole (#157, twice). A tar that fails is downloaded once
# more from this run with gh (GH_TOKEN, and the job's `actions: read`) and unpacked again; a second failure fails.
set -eu
tar_file="$1"; into="$2"; name="$3"
mkdir -p "$into"
if tar -xf "$tar_file" -C "$into"; then exit 0; fi
echo "::warning title=Build download retried::$tar_file did not unpack; downloading $name once more (#157)."
again="$(mktemp -d)"
gh run download "$GITHUB_RUN_ID" --repo "$GITHUB_REPOSITORY" -n "$name" -D "$again"
tar -xf "$again/$(basename "$tar_file")" -C "$into"
