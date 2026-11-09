#!/bin/zsh
# Скриншот окна Studio (работает и в Play): tools/shot.sh <имя> [папка]
# Выводит путь к PNG шириной 1400. Окно Studio выводится на передний план.
DIR=${2:-/tmp/bt-shots}; mkdir -p $DIR
HERE=${0:A:h}
ID=$(swift $HERE/wins.swift 2>/dev/null | grep " - Roblox Studio " | head -1 | awk '{print $1}')
[ -z "$ID" ] && { echo "Studio window not found"; exit 1; }
caffeinate -u -t 2 # wake the display: a sleeping screen gives no window image
open -a /Applications/RobloxStudio.app; sleep 1
screencapture -x -o -l $ID $DIR/full_$1.png && sips -Z 1400 $DIR/full_$1.png --out $DIR/$1.png >/dev/null && echo $DIR/$1.png
