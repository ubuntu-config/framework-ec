#!/bin/sh
#
# Applies the Zephyr patches of the checkout which is built or tested, the files ubuntu-config/zephyr/*.patch in it,
# to the Zephyr of the image, in file name order. They are fixes which the Zephyr commit of the release lacks, so a
# checkout without them, like one of Framework's releases, builds with the image's Zephyr unchanged. A patch which is
# applied already is skipped, so that several steps can run one after another in the same container.
#
#
# Usage
# -----
#   apply-zephyr-patches.sh

set -eu

EC=/mnt/host/source/src/platform/ec
ZEPHYR=/mnt/host/source/src/third_party/zephyr/main

for patch in "$EC"/ubuntu-config/zephyr/*.patch; do
  if [ ! -e "$patch" ]; then
    continue
  fi
  if git -C "$ZEPHYR" apply --check --reverse "$patch" 2> /dev/null; then
    continue
  fi
  git -C "$ZEPHYR" apply "$patch"
  echo "Zephyr: applied $(basename "$patch")"
done
