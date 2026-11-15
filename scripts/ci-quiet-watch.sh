#!/bin/sh
# CI only: run a command with its output in a log, and stop it if the log stays unchanged too long.
#
#   sh scripts/ci-quiet-watch.sh <quiet seconds> <log> <command...>
#
# A simulator launch that loses its process can leave xcodebuild waiting forever: on #163 a gallery shard logged
# "Failed to send signal 19" and then nothing for 52 minutes, until the job's limit cancelled it with no retry (#164).
# A working run writes a line at least every 2 minutes (the longest gap in that run's other three shards was 120 s, at
# boot). After <quiet seconds> with no new output, this appends "xcodebuild wrote nothing for N s" to the log, stops the
# command and exits 124. scripts/ci-ui-infra.sh counts that line as the machine's failure, so the shard gets its retry.
# Otherwise it exits with the command's own status.
set -u
quiet="$1"; log="$2"; shift 2
: > "$log"
"$@" >> "$log" 2>&1 &
pid=$!
nap="${OURO_QUIET_WATCH_NAP:-15}"
changed() { stat -f %m "$log" 2>/dev/null || stat -c %Y "$log"; }
while kill -0 "$pid" 2>/dev/null; do
  sleep "$nap"
  if [ $(($(date +%s) - $(changed))) -ge "$quiet" ] && kill -0 "$pid" 2>/dev/null; then
    echo "ci-quiet-watch: xcodebuild wrote nothing for $quiet s; stopped it (#164)" >> "$log"
    kill -TERM "$pid" 2>/dev/null
    sleep 10
    kill -KILL "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    exit 124
  fi
done
wait "$pid"
