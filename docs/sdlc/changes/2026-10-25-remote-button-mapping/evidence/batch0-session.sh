#!/bin/zsh
# Batch 0 guided measurement for the RC003. Count-driven: every step waits for a counted press, not a timer.
# Scratch tooling, not product code. Needs /tmp/b0/KeyTable and /tmp/b0/KeySink (built from the swift files here).
# Safety: restores the remote's mapping, the system volume and Utter on any exit.
# Manual clear if this script is ever killed hard:
#   hidutil property --matching '{"VendorID":10007,"ProductID":12984}' --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":30064771134,"HIDKeyboardModifierMappingDst":0}]}'

B=/tmp/b0; OUT=$B/out; LOG=$OUT/keytable.txt; STEPS=$OUT/steps.txt; INSTR=$B/instruction.txt
MATCH='{"VendorID":10007,"ProductID":12984}'
F5=30064771134
ORIGINAL="{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":$F5,\"HIDKeyboardModifierMappingDst\":0}]}"
WORK_VOL=40
ORIG_VOL=$(osascript -e 'output volume of (get volume settings)')
QUIT_UTTER=0

note() { print -r -- "$(date +%H:%M:%S) $*" >> $STEPS }
show() { print -rn -- "$1" > $INSTR }
speak() { say -v Eddy "$1" }
chime() { afplay -v 1 /System/Library/Sounds/${1:-Tink}.aiff }
setvol() { osascript -e "set volume output volume ${1:-$WORK_VOL}" >/dev/null 2>&1 }
lines() { wc -l < $LOG | tr -d ' ' }
readback() { hidutil property --matching $MATCH --get UserKeyMapping > $OUT/$1 2>&1 }

restore() {
  trap - EXIT INT TERM HUP
  hidutil property --matching $MATCH --set "$ORIGINAL" >/dev/null 2>&1
  readback final-mapping-readback.txt
  setvol $ORIG_VOL
  : > $B/quit
  pkill -TERM -f $B/KeyTable 2>/dev/null
  (( QUIT_UTTER )) && open -a /Applications/Utter.app
  note "RESTORED mapping=original volume=$ORIG_VOL utter_reopened=$QUIT_UTTER"
}
trap restore EXIT INT TERM HUP

# wait_press FROM TIMEOUT MINHOLD -> sets P_PAGE P_USAGE P_HOLD; the voice key and vendor page 0xFF00 are ignored.
wait_press() {
  local from=$1 limit=$2 minhold=$3 start=$SECONDS res
  while (( SECONDS - start < limit )); do
    res=$(tail -n +$((from + 1)) $LOG | awk -v mh=$minhold '
      /HID page=/ {
        match($0,/^\[ *[0-9.]+\]/); t=substr($0,RSTART+1,RLENGTH-2)+0
        match($0,/page=[0-9]+/); pg=substr($0,RSTART+5,RLENGTH-5)+0
        match($0,/usage=[0-9]+/); us=substr($0,RSTART+6,RLENGTH-6)+0
        match($0,/value=-?[0-9]+/); v=substr($0,RSTART+6,RLENGTH-6)+0
        if (pg==65280 || us==62 || us==4294967295) next
        k=pg":"us
        if (v>0) { if (!(k in d)) d[k]=t }
        else if (k in d) { h=t-d[k]; delete d[k]; if (h>=mh) { print pg, us, h; exit } }
      }')
    if [[ -n $res ]]; then P_PAGE=${res%% *}; res=${res#* }; P_USAGE=${res%% *}; P_HOLD=${res#* }; return 0; fi
    sleep 0.25
  done
  return 1
}

# wait_count FROM TIMEOUT N PAGE USAGE: counted press-release pairs of one usage.
wait_count() {
  local from=$1 limit=$2 want=$3 pg=$4 us=$5 start=$SECONDS got
  while (( SECONDS - start < limit )); do
    got=$(tail -n +$((from + 1)) $LOG | awk -v pg=$pg -v us=$us '
      /HID page=/ && $0 ~ ("page=" pg " usage=" us " value=0 ") { n++ } END { print n+0 }')
    (( got >= want )) && return 0
    sleep 0.25
  done
  return 1
}

# wait_doubles FROM TIMEOUT N PAGE USAGE: counted double clicks (two downs under 0.6 s apart).
wait_doubles() {
  local from=$1 limit=$2 want=$3 pg=$4 us=$5 start=$SECONDS got
  while (( SECONDS - start < limit )); do
    got=$(tail -n +$((from + 1)) $LOG | awk -v pg=$pg -v us=$us '
      /HID page=/ && $0 ~ ("page=" pg " usage=" us " value=[1-9]") {
        match($0,/^\[ *[0-9.]+\]/); t=substr($0,RSTART+1,RLENGTH-2)+0
        if (prev > 0 && t - prev < 0.6) { n++; prev = 0 } else { prev = t }
      } END { print n+0 }')
    (( got >= want )) && return 0
    sleep 0.25
  done
  return 1
}

cg_in_window() { # FROM TO -> count of CG key/system events in a line window
  sed -n "$(( $1 + 1 )),$2p" $LOG | awk '/\] CG (keyDown|keyUp|sysdef)/ { n++ } END { print n+0 }'
}

: > $STEPS; rm -f $B/quit; show "准备中…"
note "START original_volume=$ORIG_VOL"
readback start-mapping-readback.txt
if [[ $(rg -c 'HIDKeyboardModifierMappingSrc' $OUT/start-mapping-readback.txt) != 1 ]] || ! rg -q "$F5" $OUT/start-mapping-readback.txt; then
  note "ABORT unexpected starting mapping"; exit 3
fi

osascript -e 'tell application id "com.opentype.voiceinput" to quit' >/dev/null 2>&1 && QUIT_UTTER=1
sleep 2
$B/KeySink &
sleep 1
$B/KeyTable $LOG 1800 &
sleep 1.5
if ! rg -q 'TAP created' $LOG || ! rg -q 'matchedDevices=1' $LOG; then note "ABORT tool not ready: $(head -3 $LOG | tr '\n' '|')"; exit 4; fi
setvol

names=(上 下 左 右 确定 返回 主页 菜单 电视 音量加 音量减)
expect=(82 81 80 79 "" "" "" "" "" "" "")
typeset -A KEY_PAGE KEY_USAGE

speak "测量开始。请不要碰电脑键盘和鼠标。准备好后，请按遥控器的上键。"
for i in {1..$#names}; do
  n=$names[$i]; show "【短按 $i/${#names}】请按一下：$n 键"
  from=$(lines); (( i > 1 )) && speak "请按${n}键"
  limit=45; (( i == 1 )) && limit=900
  tries=0; got=0
  while (( tries < 3 )); do
    if wait_press $from $limit 0; then
      if [[ -n $expect[$i] && $P_USAGE != $expect[$i] ]]; then
        speak "这不是${n}键，请再按${n}键"; from=$(lines); tries=$((tries + 1)); limit=45; continue
      fi
      got=1; break
    fi
    break
  done
  sleep 0.8
  if (( got )); then
    KEY_PAGE[$n]=$P_PAGE; KEY_USAGE[$n]=$P_USAGE
    note "P1 key=$n usage=$P_PAGE:$P_USAGE hold=$P_HOLD lines=$from-$(lines)"; chime Tink
  else
    note "P1 key=$n NOT_PRESSED lines=$from-$(lines)"; chime Basso
  fi
  [[ $n == 音量加 || $n == 音量减 ]] && setvol
done

speak "接下来测长按。每个键按住不放，大约两秒再松开。"
for n in $names; do
  [[ -z ${KEY_USAGE[$n]-} ]] && continue
  show "【长按】请按住 $n 键约 2 秒再松开"
  from=$(lines); speak "请长按${n}键"
  ok=0
  for attempt in 1 2 3 4; do
    if wait_press $from 15 1.2; then ok=1; break; fi
    (( attempt < 4 )) && speak "请按住不放，大约两秒"
  done
  sleep 1.0
  if (( ok )); then
    note "P2 key=$n usage=$P_PAGE:$P_USAGE hold=$P_HOLD lines=$from-$(lines)"; chime Glass
  else
    note "P2 key=$n NOT_HELD lines=$from-$(lines)"; chime Basso
  fi
  [[ $n == 音量加 || $n == 音量减 ]] && setvol
done
setvol

# P3: with two usages silenced by UserKeyMapping, the raw observer must still see every press and the CG layer none.
A_NAME=右; B_NAME=""
for cand in 音量加 确定; do
  [[ -z ${KEY_USAGE[$cand]-} ]] && continue
  B_NAME=$cand
  [[ ${KEY_PAGE[$cand]} != 7 ]] && break
done
if [[ -n ${KEY_USAGE[$A_NAME]-} && -n $B_NAME ]]; then
  src_a=$(( (${KEY_PAGE[$A_NAME]} << 32) | ${KEY_USAGE[$A_NAME]} ))
  src_b=$(( (${KEY_PAGE[$B_NAME]} << 32) | ${KEY_USAGE[$B_NAME]} ))
  hidutil property --matching $MATCH --set "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":$F5,\"HIDKeyboardModifierMappingDst\":0},{\"HIDKeyboardModifierMappingSrc\":$src_a,\"HIDKeyboardModifierMappingDst\":0},{\"HIDKeyboardModifierMappingSrc\":$src_b,\"HIDKeyboardModifierMappingDst\":0}]}" >/dev/null 2>&1
  sleep 2; readback p3-mapping-readback.txt
  note "P3 mapped A=$A_NAME($src_a) B=$B_NAME($src_b)"
  speak "现在测试静音。这两个键暂时不会有任何反应，这是正常的。"
  for n in $A_NAME $B_NAME; do
    show "【静音测试】请按 $n 键 3 次，每次之间停一下"
    vol_before=$(osascript -e 'output volume of (get volume settings)')
    from=$(lines); speak "请按${n}键三次"
    if wait_count $from 90 3 ${KEY_PAGE[$n]} ${KEY_USAGE[$n]}; then r=OK; chime Tink; else r=SHORT; chime Basso; fi
    sleep 1.0
    note "P3 key=$n presses=$r cg_events=$(cg_in_window $from $(lines)) volume_before=$vol_before volume_after=$(osascript -e 'output volume of (get volume settings)') lines=$from-$(lines)"
  done
  hidutil property --matching $MATCH --set "$ORIGINAL" >/dev/null 2>&1
  readback p3-after-restore-readback.txt
else
  note "P3 SKIPPED missing keys A=${KEY_USAGE[$A_NAME]-none} B=$B_NAME"
fi

# P5: natural double clicks on one key, for the double-click window.
D_NAME=确定; [[ -z ${KEY_USAGE[$D_NAME]-} ]] && D_NAME=右
speak "最后一项。请在${D_NAME}键上快速双击，一共十次，每次之间停大约一秒。"
show "【双击 0/10】请在 $D_NAME 键上快速双击，共 10 次"
from=$(lines)
if wait_doubles $from 300 10 ${KEY_PAGE[$D_NAME]} ${KEY_USAGE[$D_NAME]}; then r=OK; chime Glass; else r=SHORT; chime Basso; fi
sleep 1.0
note "P5 key=$D_NAME doubles=$r lines=$from-$(lines)"

show "全部完成，谢谢！"; speak "测量完成，谢谢。"
note "DONE"
