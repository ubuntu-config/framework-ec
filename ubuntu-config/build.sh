#!/bin/sh
#
# Builds the firmware of a zmake project in the build image (Dockerfile), the way Framework builds its releases with
# "zmake build -v VERSION PROJECT" in the ChromiumOS SDK chroot, and checks that the image carries the version string
# zmake makes from the version, the project and the commit of the checkout, which ends with "+" for a tree with
# uncommitted changes. The output is in build/zephyr/<project>/output of the checkout. The Zephyr patches of the
# checkout are applied to the image's Zephyr first (apply-zephyr-patches.sh).
#
# The checkout has to be at /mnt/host/source/src/platform/ec, its path in the chroot: assertion messages contain source
# file paths, which -fmacro-prefix-map makes relative to the parent of the checkout, like
# EC_BASE/ec/build/zephyr/lilac/modules/ec/common/queue.c. The image contains the user and host name of the build
# machine as well, which the caller sets: ubuntu-config@framework-ec in CI and by default in build-ec.sh, and
# lotus@ip-172-26-3-226, the ones of Framework's build machine of lilac 4.0.2, for a build equal to the release.
#
#
# Usage
# -----
#   build.sh [VERSION [PROJECT]]
#
#   VERSION     base version string, which zmake extends to <project>-<version>-<commit>, by default the one in the file
#               version next to this script
#   PROJECT     zmake project, lilac by default

set -eu

EC=/mnt/host/source/src/platform/ec

version=${1:-$(cat "$(dirname "$0")/version")}
project=${2:-lilac}

"$(dirname "$0")/apply-zephyr-patches.sh"

cd "$EC"
zmake build -v "$version" "$project"

output=build/zephyr/$project/output
commit=$(git -c safe.directory="$EC" rev-parse HEAD)
name=$(grep -a -o -m 1 -E "$project-$version-[0-9a-f]+\+?" "$output/ec.bin" | head -n 1)
if [ -z "$name" ]; then
  echo "no $project-$version-<commit> version string in $output/ec.bin" >&2
  exit 1
fi
hash=${name##*-}
case $commit in
  "${hash%+}"*) ;;
  *)
    echo "$name in $output/ec.bin does not name the commit $commit" >&2
    exit 1
    ;;
esac

echo "$name"
sha256sum "$output/ec.bin"
