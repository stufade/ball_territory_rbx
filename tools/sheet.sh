#!/bin/zsh
# Склеить кадры в один лист, чтобы открыть одним изображением: tools/sheet.sh <выход.jpg> <кадр>... (до 9, сетка 3x3, 400 px на кадр)
OUT=${1:?out}; shift
ARGS=(); for f in "$@"; do ARGS+=(-i "$f"); done
N=$#; COLS=$(( N < 3 ? N : 3 )); ROWS=$(( (N + 2) / 3 ))
FILTER=""; for i in $(seq 0 $((N-1))); do FILTER+="[$i]scale=400:260:force_original_aspect_ratio=decrease,pad=400:260:0:0[v$i];"; done
INS=""; for i in $(seq 0 $((N-1))); do INS+="[v$i]"; done
LAYOUT=""; for i in $(seq 0 $((N-1))); do x=$(( (i % 3) * 400 )); y=$(( (i / 3) * 260 )); LAYOUT+="${x}_${y}|"; done
ffmpeg -loglevel error -y "${ARGS[@]}" -filter_complex "${FILTER}${INS}xstack=inputs=${N}:layout=${LAYOUT%|}:fill=black" -frames:v 1 "$OUT" && echo "$OUT"
