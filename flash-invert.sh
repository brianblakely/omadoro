#!/usr/bin/env bash
# Ease the Hyprland screen invert in and out, then restore whatever was set.

set -u

count=${1:-3}
on_s=${2:-0.14}
off_s=${3:-0.14}
steps=8

if ! [[ $count =~ ^[0-9]+$ ]] || ((count < 1)); then
  count=3
fi

if ! command -v hyprctl >/dev/null 2>&1; then
  echo "omadoro: hyprctl is unavailable" >&2
  exit 1
fi

runtime=${XDG_RUNTIME_DIR:-/tmp}/omadoro
mkdir -p "$runtime"
file_a=$runtime/invert-a.frag
file_b=$runtime/invert-b.frag
use_a=1

current=$(hyprctl getoption decoration:screen_shader 2>/dev/null | awk '
  /^str:/{
    sub(/^str:[[:space:]]*/, "")
    print
    exit
  }
')
if [[ $current == '[[EMPTY]]' || $current == 'null' ]]; then
  current=""
fi

lua_string() {
  printf '[[%s]]' "$1"
}

set_shader() {
  hyprctl eval "hl.config({ decoration = { screen_shader = $(lua_string "$1") } })" >/dev/null
}

restore() {
  set_shader "$current"
}
trap restore EXIT

write_amount() {
  local amount=$1
  local path=$2
  cat >"$path" <<EOF
#version 300 es
precision mediump float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    float amount = ${amount};
    fragColor = vec4(mix(pixColor.rgb, 1.0 - pixColor.rgb, amount), pixColor.a);
}
EOF
}

apply_amount() {
  local path
  if ((use_a)); then
    path=$file_a
    use_a=0
  else
    path=$file_b
    use_a=1
  fi
  write_amount "$1" "$path"
  set_shader "$path"
}

ease() {
  awk -v t="$1" 'BEGIN {
    if (t < 0) t = 0
    if (t > 1) t = 1
    printf "%.4f", 0.5 - 0.5 * cos(3.141592653589793 * t)
  }'
}

lerp() {
  awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN { printf "%.4f", a + (b - a) * t }'
}

fade() {
  local from=$1 to=$2 dur=$3
  local i t e amount
  local step_s
  step_s=$(awk -v d="$dur" -v n="$steps" 'BEGIN {
    s = d / n
    if (s < 0.012) s = 0.012
    printf "%.4f", s
  }')
  for ((i = 1; i <= steps; i++)); do
    t=$(awk -v i="$i" -v n="$steps" 'BEGIN { printf "%.4f", i / n }')
    e=$(ease "$t")
    amount=$(lerp "$from" "$to" "$e")
    apply_amount "$amount"
    sleep "$step_s"
  done
}

for ((i = 0; i < count; i++)); do
  fade 0 1 "$on_s"
  fade 1 0 "$off_s"
done
