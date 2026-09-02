#!/usr/bin/env bash
# Compiles the generator into a single self-contained executable.
#
# The result needs no Dart SDK to run, which is what makes it usable from a
# GitHub Actions step, a Makefile, or anyone's PATH.
#
#   tool/build_binary.sh                            # for this machine
#   tool/build_binary.sh --output bin/vfg           # somewhere else
#   tool/build_binary.sh --target-os linux --target-arch arm64
#
# The only platforms Dart can cross compile to are the other Linux
# architectures, whatever the host is; a Windows or macOS binary has to be built
# on Windows or macOS. Naming the host's own platform is a no-op, so it is safe
# to pass the target through unconditionally.
set -euo pipefail

output=''
target_os=''
target_arch=''

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output) output="$2"; shift 2 ;;
    --target-os) target_os="$2"; shift 2 ;;
    --target-arch) target_arch="$2"; shift 2 ;;
    -h|--help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
      exit 0
      ;;
    *) echo "$0: unknown argument $1" >&2; exit 64 ;;
  esac
done

cd "$(dirname "$0")/.."
repository="$PWD"

if [ -z "$output" ]; then
  suffix=''
  case "${target_os:-$(uname -s)}" in
    windows|MINGW*|MSYS*|CYGWIN*) suffix='.exe' ;;
  esac
  output="$repository/build/bin/variable_font_generator$suffix"
fi
case "$output" in
  /*|[A-Za-z]:*) ;;
  *) output="$PWD/$output" ;;
esac
mkdir -p "$(dirname "$output")"

arguments=(bin/variable_font_generator.dart -o "$output")
if [ -n "$target_os" ]; then
  arguments+=(--target-os "$target_os")
fi
if [ -n "$target_arch" ]; then
  arguments+=(--target-arch "$target_arch")
fi

cd packages/variable_font_generator
dart pub get
dart compile exe "${arguments[@]}"

echo "$output"
