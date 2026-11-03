#!/usr/bin/env bash
# Runs a host and two pretend players in separate processes and checks they
# share one world. Usage, from the 2dmmo folder:
#   GODOT=/path/to/godot tests/net_test.sh
set -u
GODOT="${GODOT:-godot}"
PORT=24695
SAVE="user://net_test_world.json"
LOG=$(mktemp -d)

"$GODOT" --headless --path . -- --host --name=Host --port=$PORT --save=$SAVE --fresh > "$LOG/host.log" 2>&1 &
HOST=$!
sleep 2
"$GODOT" --headless --path . -- --join=127.0.0.1 --port=$PORT --name=Miner --bot=miner > "$LOG/miner.log" 2>&1 &
MINER=$!
sleep 6
"$GODOT" --headless --path . -- --join=127.0.0.1 --port=$PORT --name=Watcher --bot=watcher > "$LOG/watcher.log" 2>&1 &
WATCHER=$!

wait $MINER; MINER_RESULT=$?
wait $WATCHER; WATCHER_RESULT=$?
sleep 1
kill $HOST 2>/dev/null; wait $HOST 2>/dev/null

grep -h "^BOT\|ERROR" "$LOG/miner.log" "$LOG/watcher.log"
echo "--- host log"
grep -v "^Godot Engine" "$LOG/host.log" | head -20
if [ $MINER_RESULT -eq 0 ] && [ $WATCHER_RESULT -eq 0 ]; then
	echo "NETWORK TEST PASSED"
else
	echo "NETWORK TEST FAILED (logs in $LOG)"
	exit 1
fi
