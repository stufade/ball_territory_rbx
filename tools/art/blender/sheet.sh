#!/bin/zsh
# Preview sheet of ball renders on the UI panel colour: tools/art/blender/sheet.sh <out.jpg> <png>... (4 per row, 256 px)
OUT=${1:?out}; shift
N=$#; C=$(( N < 4 ? N : 4 )); R=$(( (N + 3) / 4 ))
ARGS=(-f lavfi -i color=c=0x1f2244:s=$((C*256))x$((R*256))); F=""; P="[0]"
i=1; for f in "$@"; do ARGS+=(-i "$f"); x=$(( ((i-1) % 4) * 256 )); y=$(( ((i-1) / 4) * 256 ))
  F+="[$i]scale=256:256[s$i];${P}[s$i]overlay=$x:$y[o$i];"; P="[o$i]"; i=$((i+1)); done
ffmpeg -loglevel error -y "${ARGS[@]}" -filter_complex "${F%;}" -map "$P" -frames:v 1 "$OUT" && echo "$OUT"
