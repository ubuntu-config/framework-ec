#!/bin/sh
#
# Runs one step of the test suites of the EC repository in the test image (Dockerfile.test), the way ChromiumOS's
# builders run them with "firmware_builder.py test" (the legacy EC tests) and "zephyr/firmware_builder.py test" (the
# Zephyr tests), without code coverage. Twister writes its results to twister-out-<toolchain> in the checkout.
#
# The checkout has to be at /mnt/host/source/src/platform/ec, its path in the ChromiumOS SDK chroot, where the tests
# find the other modules of a ChromiumOS checkout, which the image provides.
#
# Two steps of ChromiumOS need compilers of its SDK which are not available outside it, so they are left out: the
# legacy host tests built with x86_64-cros-linux-gnu, and the on-device unit tests of the bloonchipper, dartmonkey and
# helipilot fingerprint boards, which ChromiumOS only compiles, with armv7m-cros-eabi.
#
#
# Usage
# -----
#   test.sh STEP
#   test.sh --list
#
#   STEP        the step to run, one of those --list prints

set -eu

EC=/mnt/host/source/src/platform/ec
STEPS="stack-analyzer util legacy legacy-asan zmake compliance twister-host twister-llvm"

if [ $# -ne 1 ]; then
  sed -n 's/^#   //p' "$0" >&2
  exit 2
fi
if [ "$1" = --list ]; then
  echo "$STEPS"
  exit 0
fi

cd "$EC"
jobs=$(nproc)
case $1 in
  stack-analyzer) exec extra/stack_analyzer/run_tests.sh ;;
  util) exec util/run_tests.sh ;;
  # firmware_builder.py builds the posix-based tests and the fuzzers and runs them. With -k, a test which does not
  # build does not stop the others.
  legacy) exec make -k runtests -j"$jobs" ;;
  # With a sanitizer, the makefiles select clang also for the default board, elm, a Cortex-M0, and so require the
  # arm-none-eabi-clang of the SDK just to read the makefiles. The tests themselves build for the host board.
  legacy-asan) exec make -k BOARD=host TEST_ASAN=y runtests -j"$jobs" ;;
  zmake) exec zephyr/zmake/run_tests.sh ;;
  compliance) exec util/zephyr_check_compliance_unittest.py ;;
  # Twister removes the build directory of every test as the run goes and keeps its logs, so that the output of
  # hundreds of tests which do not build fits into /tmp.
  twister-host | twister-llvm)
    toolchain=${1#twister-}
    exec ./twister --outdir "$EC/twister-out-$toolchain" -v -i --no-upload-cros-rdb --toolchain "$toolchain" \
      --runtime-artifact-cleanup all
    ;;
  *)
    echo "unknown step $1, the steps are: $STEPS" >&2
    exit 2
    ;;
esac
