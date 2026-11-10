#!/bin/zsh
# Серия снимков окна Studio: tools/burst.sh <папка> [секунд=80] [шаг=1.5]
# Для T2.1: Play, на сервере DebugTutorTour = true (обучение идёт само и стоит по 3 с в каждой сцене),
# сразу запустить этот скрипт, потом выбрать кадры (docs/shots/t2.1/README.md).
# Кадры не открывать по одному: выбрать до 9 и склеить tools/sheet.sh.
DIR=${1:?folder}; SECS=${2:-80}; STEP=${3:-1.5}
HERE=${0:A:h}
mkdir -p $DIR
ID=$(swift $HERE/wins.swift 2>/dev/null | grep " - Roblox Studio " | head -1 | awk '{print $1}')
[ -z "$ID" ] && { echo "Studio window not found"; exit 1; }
caffeinate -u -t $SECS &
open -a /Applications/RobloxStudio.app; sleep 1
END=$((SECONDS + SECS)); N=0
while [ $SECONDS -lt $END ]; do
  N=$((N + 1)); F=$(printf "%s/burst_%03d.png" $DIR $N)
  screencapture -x -o -l $ID $F && ffmpeg -loglevel error -y -i $F -vf "crop=iw*0.744:ih*0.786:0:ih*0.133,scale=800:-2" $F.tmp.png && mv $F.tmp.png $F
  sleep $STEP
done
echo "$N shots in $DIR"
