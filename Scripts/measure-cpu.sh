#!/bin/bash
set -euo pipefail

APP="build/Thock.app"
IDLE_SECONDS="${1:-20}"
BENCH_SECONDS="${2:-20}"
WARMUP=3

[ -d "$APP" ] || { echo "Missing $APP: run make build first." >&2; exit 1; }

launch() {
    pkill -x Thock 2>/dev/null || true
    sleep 1
    open -g "$APP" --args "$@"
    for _ in $(seq 50); do
        pid=$(pgrep -nx Thock || true)
        [ -n "$pid" ] && return
        sleep 0.1
    done
    echo "Thock did not start." >&2
    exit 1
}

sample() {
    local seconds=$1
    top -l $((seconds + 1)) -s 1 -pid "$pid" -stats cpu \
        | awk '/^%CPU/ { getline; n++; if (n > 1) { sum += $1; if ($1 > max) max = $1; count++ } }
               END { if (count) printf "mean %.2f %% | max %.1f %% | %d samples\n", sum / count, max, count }'
}

launch
sleep "$WARMUP"
echo "Idle ($IDLE_SECONDS s, pid $pid): $(sample "$IDLE_SECONDS")"
log show --last 2m --style compact --predicate "subsystem == \"io.github.dailyxplorer.thock\" AND category == \"audio\" AND processID == $pid" \
    | grep -oE 'Engine (started|start failed).*' | tail -1 || echo "Engine never started."
kill "$pid"
[ "$BENCH_SECONDS" -gt 0 ] || exit 0

launch --bench-typing "$BENCH_SECONDS"
sleep "$WARMUP"
echo "Synthetic typing, 17 events/s ($((BENCH_SECONDS - 2)) s, pid $pid): $(sample $((BENCH_SECONDS - 2)))"
sleep 3
log show --last 2m --style compact --predicate 'subsystem == "io.github.dailyxplorer.thock" AND category == "bench"' \
    | grep -o 'Bench done.*' | tail -1 || echo "No bench summary in the log."
kill "$pid"
