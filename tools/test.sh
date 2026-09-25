#!/usr/bin/env bash
# Runs the headless test suite, spread over several Godot processes.
#   tools/test.sh               run everything
#   tools/test.sh determinism   run only tests whose "file::method" contains the filter
#   tools/test.sh --quick       skip tests that took over QUICK_MS (default 5000) last time
#   tools/test.sh -j 4          at most 4 processes (default: half the CPU count); -j 1 runs in one
#   tools/test.sh --no-native   everything with GDScript ants only (no native kernel)
#   tools/test.sh --long ...    also the long runs (see test_nest_architecture.gd)
# Other --flags go on to the tests. Each test's time is kept in .godot/test_times.txt;
# it balances the processes (slowest tests first, each to the least loaded) and
# picks the --quick tier (new tests, with no time yet, are in it).
# Full output of every process: .godot/test_runs/.
# Set GODOT to override the Godot executable (default: godot on PATH).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
QUICK_MS="${QUICK_MS:-5000}"
TIMES=.godot/test_times.txt
RUNS=.godot/test_runs

# Half the logical CPUs: one per core (hyperthreads made each test ~2x slower).
jobs=$(( $(nproc 2>/dev/null || echo 8) / 2 ))
quick=0
pass=()
while [ $# -gt 0 ]; do
	case "$1" in
		-j) jobs="$2"; shift ;;
		-j*) jobs="${1#-j}" ;;
		--quick) quick=1 ;;
		*) pass+=("$1") ;;
	esac
	shift
done

# Scripts run with -s don't trigger a filesystem scan, so refresh the import
# cache (which holds the class_name table) first. Output is only shown on failure.
if ! import_log=$("$GODOT" --headless --path . --import 2>&1); then
	echo "$import_log"
	echo "Godot import failed" >&2
	exit 1
fi

rm -rf "$RUNS"
mkdir -p "$RUNS"
touch "$TIMES"
t_start=$(date +%s)

# The tests to run: "TEST name" lines; test files that don't load are failures.
list_out=$("$GODOT" --headless --path . -s res://tests/run_tests.gd -- --list ${pass[@]+"${pass[@]}"} 2>&1 || true)
load_fails=$(grep -E '^FAIL  ' <<< "$list_out" || true)
grep -E '^TEST ' <<< "$list_out" | cut -c6- | tr -d '\r' > "$RUNS/all.txt" || true
if [ -n "$load_fails" ]; then
	echo "$load_fails"
fi

skipped=0
if [ "$quick" = 1 ]; then
	awk -v max="$QUICK_MS" 'FILENAME == ARGV[1] { ms[$2] = $1; next } !($1 in ms) || ms[$1] <= max' \
		"$TIMES" "$RUNS/all.txt" > "$RUNS/selected.txt"
	skipped=$(( $(wc -l < "$RUNS/all.txt") - $(wc -l < "$RUNS/selected.txt") ))
else
	cp "$RUNS/all.txt" "$RUNS/selected.txt"
fi
total=$(wc -l < "$RUNS/selected.txt")
if [ "$total" = 0 ]; then
	echo "No tests match."
	[ -z "$load_fails" ]
	exit
fi
[ "$jobs" -gt "$total" ] && jobs=$total
[ "$jobs" -lt 1 ] && jobs=1

# Longest first, each to the shard with the least work so far. Unknown tests
# count as 5 s.
awk -v jobs="$jobs" -v dir="$RUNS" '
	FILENAME == ARGV[1] { ms[$2] = $1; next }
	{ print (($1 in ms) ? ms[$1] : 5000), $1 }
' "$TIMES" "$RUNS/selected.txt" | sort -rn | awk -v jobs="$jobs" -v dir="$RUNS" '
	BEGIN { for (s = 1; s <= jobs; s++) load[s] = 0 }
	{
		best = 1
		for (s = 2; s <= jobs; s++) if (load[s] < load[best]) best = s
		load[best] += $1
		print $2 > (dir "/shard" best ".txt")
	}
'

echo "Running $total tests in $jobs processes$([ "$skipped" -gt 0 ] && echo " ($skipped slow ones skipped by --quick)")..."

pids=()
cleanup() {
	for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null || true; done
}
trap cleanup INT TERM

for s in $(seq 1 "$jobs"); do
	(
		"$GODOT" --headless --path . -s res://tests/run_tests.gd -- \
			--tests-file="res://$RUNS/shard$s.txt" ${pass[@]+"${pass[@]}"} > "$RUNS/shard$s.log" 2>&1 \
			&& echo 0 > "$RUNS/shard$s.exit" || echo $? > "$RUNS/shard$s.exit"
	) &
	pids+=($!)
done

# Stream results as the processes print them.
declare -A shown
for s in $(seq 1 "$jobs"); do shown[$s]=0; done
report() {
	for s in $(seq 1 "$jobs"); do
		local lines
		lines=$(grep -E '^(PASS|FAIL)  |^      - ' "$RUNS/shard$s.log" 2>/dev/null | tr -d '\r' || true)
		[ -z "$lines" ] && continue
		local n
		n=$(wc -l <<< "$lines")
		if [ "$n" -gt "${shown[$s]}" ]; then
			tail -n +"$(( ${shown[$s]} + 1 ))" <<< "$lines"
			shown[$s]=$n
		fi
	done
}
while true; do
	report
	done_count=$(find "$RUNS" -name "shard*.exit" | wc -l)
	[ "$done_count" -ge "$jobs" ] && break
	sleep 1
done
wait
report

# Every test must have reported, and every process exited cleanly.
problems=()
for s in $(seq 1 "$jobs"); do
	code=$(cat "$RUNS/shard$s.exit")
	missing=0
	while read -r t; do
		[ -z "$t" ] && continue
		if ! grep -qE "^(PASS|FAIL)  $t \(" "$RUNS/shard$s.log"; then
			problems+=("FAIL  $t (no result: process $s exited with code $code - see $RUNS/shard$s.log)")
			missing=1
		fi
	done < "$RUNS/shard$s.txt"
	if [ "$code" != 0 ] && [ "$missing" = 0 ] && ! grep -qE '^FAIL  ' "$RUNS/shard$s.log"; then
		problems+=("FAIL  process $s exited with code $code - see $RUNS/shard$s.log")
	fi
done
for p in ${problems[@]+"${problems[@]}"}; do echo "$p"; done

# Remember each test's time (keeping the ones not run this time).
cat "$RUNS"/shard*.log | tr -d '\r' | sed -nE 's/^(PASS|FAIL)  ([^ ]+) \(([0-9]+) ms\)$/\3 \2/p' > "$RUNS/times.txt"
awk 'FILENAME == ARGV[1] { ms[$2] = $1; next } !($2 in ms) { print } END { for (t in ms) print ms[t], t }' \
	"$RUNS/times.txt" "$TIMES" | sort -k2 > "$TIMES.new" && mv "$TIMES.new" "$TIMES"

passed=$(cat "$RUNS"/shard*.log | grep -cE '^PASS  ' || true)
failed=$(( $(cat "$RUNS"/shard*.log | grep -cE '^FAIL  ' || true) + ${#problems[@]} + $(grep -c . <<< "$load_fails" || true) ))
echo
if [ "$failed" -gt 0 ]; then
	echo "Failures:"
	{ cat "$RUNS"/shard*.log | tr -d '\r' | grep -E '^FAIL  ' || true; echo "$load_fails"; } | grep . || true
	for p in ${problems[@]+"${problems[@]}"}; do echo "$p"; done
	echo
fi
echo "$passed passed, $failed failed in $(( $(date +%s) - t_start )) s ($jobs processes)$([ "$skipped" -gt 0 ] && echo ", $skipped skipped by --quick")"
[ "$failed" = 0 ]
