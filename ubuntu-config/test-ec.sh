#!/bin/sh
#
# Runs the test suites of the EC repository on the committed state of a checkout, step after step, with test.sh in the
# test image, which CI uses as well, without network. Every step runs even when an earlier one fails, and the script
# exits with an error when any step failed.
#
# The tests run in a shared clone of the checkout in /tmp/framework-ec-test, so they write nothing into the checkout,
# and only committed changes are tested: HEAD, or the commit --ref names. Logs are written to test-logs/<time> next to
# this script, with the tested commit in the file commit.
#
#
# Usage
# -----
#   test-ec.sh [--ref REF] [-C CHECKOUT] [STEP...]
#
#   --ref REF   commit to test instead of HEAD
#   CHECKOUT    the checkout to test, by default the one this script is in
#   STEP        steps to run, all by default, which "test.sh --list" prints

set -eu

dir=$(cd "$(dirname "$0")" && pwd -P)
. "$dir/local-images.sh"

EC=/mnt/host/source/src/platform/ec
TEST=/tmp/framework-ec-test

checkout=$(cd "$dir/.." && pwd -P)
ref=
while [ $# -gt 0 ]; do
  case $1 in
    --ref | -C)
      if [ $# -lt 2 ]; then
        sed -n 's/^#   //p' "$0" >&2
        exit 2
      fi
      if [ "$1" = --ref ]; then
        ref=$2
      else
        checkout=$(realpath "$2")
      fi
      shift 2
      ;;
    *) break ;;
  esac
done
steps=${*:-$("$dir/test.sh" --list)}

ensure_test_image

rm -rf "$TEST"
mkdir -p "$TEST"
# The clone reads the objects of the checkout through git's alternates, so creating it copies only the working tree.
git clone -q --shared "$checkout" "$TEST/ec"
if [ -n "$ref" ]; then
  git -C "$TEST/ec" checkout -q --detach "$ref"
fi
logs=$dir/test-logs/$(date +%Y%m%d-%H%M%S)
mkdir -p "$logs"
git -C "$TEST/ec" log -1 --format='%H %s' > "$logs/commit"

failed=
for step in $steps; do
  echo "=== $step"
  if docker run --rm --network=none \
    -v "$TEST/ec:$EC" \
    -v "$checkout/.git:$checkout/.git:ro" \
    -v "$dir:/opt/ubuntu-config:ro" \
    "$TEST_IMAGE" \
    /opt/ubuntu-config/test.sh "$step" > "$logs/$step.log" 2>&1; then
    echo "=== $step: passed"
  else
    echo "=== $step: FAILED, see $logs/$step.log"
    failed="$failed $step"
  fi
  # The build directory of the legacy tests grows to several gigabytes, which the later steps need in /tmp, and every
  # legacy step builds everything again anyway. Twister keeps the build.ninja of every test and reports of hundreds of
  # megabytes, so of its output only the logs and twister.json stay.
  rm -rf "${TEST:?}/ec/build"
  if [ -d "$TEST/ec/twister-out-${step#twister-}" ]; then
    find "$TEST/ec/twister-out-${step#twister-}" -type f ! -name '*.log' ! -name twister.json -delete
    find "$TEST/ec/twister-out-${step#twister-}" -depth -type d -empty -delete
  fi
done

echo "logs: $logs"
if [ -n "$failed" ]; then
  echo "failed:$failed"
  exit 1
fi
