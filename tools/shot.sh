#!/bin/zsh
# Скриншот игры в окне Studio (работает и в Play): tools/shot.sh <имя> [папка] [full]
# По умолчанию обрезает до вьюпорта игры (без панелей Studio) и уменьшает до 800 px: ~1 тыс. токенов вместо ~3.
# full — всё окно Studio, 800 px. Окно Studio выводится на передний план.
# Бюджет: не больше ~10 снимков на задачу; серии — через tools/sheet.sh, одним листом.
DIR=${2:-/tmp/bt-shots}; mkdir -p $DIR
HERE=${0:A:h}
# window bounds (x,y,w,h): screencapture -l <id> stopped writing files, -R of the window rect works
R=$(swift $HERE/wins.swift 2>/dev/null | grep " - Roblox Studio " | head -1 | awk '{print $(NF-1)","$NF","$(NF-4)","$(NF-3)}')
[ -z "$R" ] && { echo "Studio window not found"; exit 1; }
caffeinate -u -t 2 # wake the display: a sleeping screen gives no window image
open -a /Applications/RobloxStudio.app; sleep 1
RAW=/tmp/bt_raw_$1.png # screencapture cannot write into ~/Desktop nor to dot-files
screencapture -x -o -R$R $RAW || exit 1
if [ "$3" = "full" ]; then VF="scale=800:-2"
else VF="crop=iw*0.744:ih*0.786:0:ih*0.133,scale=800:-2"; fi
ffmpeg -loglevel error -y -i $RAW -vf "$VF" $DIR/$1.png && rm -f $RAW && echo $DIR/$1.png
