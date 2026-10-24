#!/bin/zsh
# Usage: scripts/duo-host.sh <duo-sim-udid> <command…> — serves DuoHost requests (unfold, fold, shot <name>, light, dark) while <command> runs.
# The simulator can't unfold from the command line; devicectl appResize at the inner display's 669x951 pt is the same mid-session resize.
set -uo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
id=$1; shift
DIR=/tmp/opencody-duo-host
SHOTS=${DUO_SHOTS:-/tmp/opencody-duo-shots}
rm -rf $DIR; mkdir -p $DIR $SHOTS
session=""

fold() { [[ -n $session ]] && kill $session 2>/dev/null; session=""; }

serve() {
  while [[ -e $DIR/active ]]; do
    if [[ -f $DIR/request ]]; then
      req=$(<$DIR/request); rm $DIR/request
      case $req in
        unfold)
          fold
          # Starting often fails with "Resizing is not available on this device right now": retry.
          for _ in 1 2 3 4 5 6; do
            $DEVELOPER_DIR/usr/bin/devicectl device appResize start --device $id --preferred-size 669x951 >$DIR/session.log 2>&1 &
            session=$!
            for _ in {1..30}; do
              grep -q "Session active" $DIR/session.log && break
              kill -0 $session 2>/dev/null || break
              sleep 0.5
            done
            cat $DIR/session.log >>$DIR/log
            grep -q "Session active" $DIR/session.log && { sleep 2; break; }
            fold; sleep 2
          done ;;
        fold) fold; sleep 2 ;;
        # Display 5 is the resizable display; display 3 (the inner panel itself) stays black.
        "shot "*) xcrun simctl io $id screenshot --display=5 "$SHOTS/${req#shot }.png" >/dev/null 2>&1 ;;
        light|dark) xcrun simctl ui $id appearance $req ;;
      esac
      echo $req > $DIR/done
    fi
    sleep 0.3
  done
  fold
}

touch $DIR/active
trap 'rm -f $DIR/active' EXIT
serve &
server=$!
"$@"
status=$?
rm -f $DIR/active; wait $server
exit $status
