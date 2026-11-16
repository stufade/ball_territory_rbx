#!/bin/zsh
# Preview sheet of ball renders on the UI panel colour: tools/art/blender/sheet.sh <out.jpg> <png>... (N per row, 256 px; COLS env, default 4)
OUT=${1:?out}; shift
N=$#; K=${COLS:-4}; C=$(( N < K ? N : K )); R=$(( (N + K - 1) / K ))
ARGS=(-f lavfi -i color=c=0x1f2244:s=$((C*256))x$((R*256))); F=""; P="[0]"
i=1; for f in "$@"; do ARGS+=(-i "$f"); x=$(( ((i-1) % K) * 256 )); y=$(( ((i-1) / K) * 256 ))
  F+="[$i]scale=256:256[s$i];${P}[s$i]overlay=$x:$y"; [[ $i -lt $N ]] && F+="[o$i];"; P="[o$i]"; i=$((i+1)); done
ffmpeg -loglevel error -y "${ARGS[@]}" -filter_complex "$F" -frames:v 1 -q:v 3 "$OUT" && echo "$OUT"
