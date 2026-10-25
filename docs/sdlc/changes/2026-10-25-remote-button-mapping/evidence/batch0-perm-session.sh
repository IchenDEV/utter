#!/bin/zsh
# Batch 0 permission measurement, guided and count-driven. Scratch tooling, not product code.
# Requires /tmp/b0/PermProbeB.app (ad hoc signed, fresh bundle id) and /tmp/b0/KeyTable (host-permission control).
B=/tmp/b0
OUT=$B/out
APP=/tmp/b0/PermProbeB.app
speak() { say -v Eddy "$1" }
chime() { afplay /System/Library/Sounds/${1:-Glass}.aiff }
until_line() { local f=$1 pat=$2 limit=$3 s=$SECONDS; while (( SECONDS - s < limit )); do rg -q "$pat" $f 2>/dev/null && return 0; sleep 0.5; done; return 1 }

rm -f $OUT/permB*.txt
$B/KeyTable $OUT/permB-control.txt 420 >/dev/null 2>&1 &
sleep 1

# Round 1: request first, open only after. The user answers the system prompt and Settings toggle.
open -n $APP --args $OUT/permB1.txt request 150
until_line $OUT/permB1.txt 'REQUEST returned' 15
speak "请看屏幕。如果出现系统弹窗，请点打开系统设置，然后开启 Batch0 PermProbe B 的开关。"
if until_line $OUT/permB1.txt 'READY2' 170; then
  chime Glass; speak "现在请在遥控器上，按右键三次，每次停一下。"
else
  speak "没有检测到授权，这一项记为未授权。"
fi
until_line $OUT/permB1.txt 'END' 90

# Round 2: a fresh process launched after the grant must open without a prompt.
open -n $APP --args $OUT/permB2.txt check 60
until_line $OUT/permB2.txt 'READY' 10
chime Glass; speak "最后一次。请再按右键三次。"
until_line $OUT/permB2.txt 'END' 80
speak "输入监控测量完成，谢谢。"
echo DONE > $OUT/permB-done.txt
