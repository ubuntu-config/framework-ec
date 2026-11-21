#!/bin/sh
#
# Builds the EC firmware of a checkout the way Framework builds its releases. It runs build.sh in the build image, which
# CI uses as well, without network, as user ubuntu-config on host framework-ec like CI, with the checkout mounted
# read-only at its path in the ChromiumOS SDK chroot and the build directory in /tmp/framework-ec-build. The output is
# copied to out/<version string> next to this script.
#
# With -R it builds as user lotus on host ip-172-26-3-226 like Framework's build machine of lilac 4.0.2, so that a clean
# checkout of a release commit gives the released image, except for the build date. The user and host name are in the
# image, and one of another length moves the data after it.
#
# Release builds run "zmake build -v VERSION PROJECT" in the ChromiumOS SDK chroot, and these parts of them are in the
# image or here:
# - zmake selects the coreboot-sdk toolchain for the project, with GCC, picolibc and libstdc++ in the versions which
#   chromiumos-overlay pins.
# - Zephyr is a git checkout of the commit which the boot banner of the released image names.
# - The checkout is at /mnt/host/source/src/platform/ec, its path in the chroot, and the build directory is build/zephyr
#   in it.
# - The image contains the user and host name of the build machine.
#
#
# Usage
# -----
#   build-ec.sh [-C CHECKOUT] [-R] [VERSION [PROJECT]]
#
#   CHECKOUT    the checkout to build, by default the one this script is in, for example a worktree of a release commit
#   -R          builds as Framework's build machine, to compare the image with a release
#   VERSION     base version string, which zmake extends to <project>-<version>-<commit>, by default the one in the file
#               version next to this script
#   PROJECT     zmake project, lilac by default

set -eu

dir=$(cd "$(dirname "$0")" && pwd -P)
. "$dir/local-images.sh"

EC=/mnt/host/source/src/platform/ec
BUILD=/tmp/framework-ec-build

checkout=$(cd "$dir/.." && pwd -P)
user=ubuntu-config
host=framework-ec
while [ $# -gt 0 ]; do
  case $1 in
    -C)
      if [ $# -lt 2 ]; then
        sed -n 's/^#   //p' "$0" >&2
        exit 2
      fi
      checkout=$(realpath "$2")
      shift 2
      ;;
    -R)
      user=lotus
      host=ip-172-26-3-226
      shift
      ;;
    *)
      break
      ;;
  esac
done
version=${1:-$(cat "$dir/version")}
project=${2:-lilac}

ensure_build_image

mkdir -p "$dir/out"
rm -rf "$BUILD"
mkdir -p "$BUILD"

# The checkout is mounted read-only, so the build cannot change it, and Python cannot write __pycache__ directories
# into it. The build directory is mounted over its build directory, which is in .gitignore and needs to exist as the
# mount point.
mkdir -p "$checkout/build"
# A checkout made with "git clone --shared" reads objects from the repositories its alternates file lists, so these are
# mounted read-only at their own paths, for zmake to find the commit.
set --
if [ -f "$checkout/.git/objects/info/alternates" ]; then
  while read -r alternate; do
    set -- "$@" -v "$alternate:$alternate:ro"
  done < "$checkout/.git/objects/info/alternates"
fi
docker run --rm --network=none \
  --hostname "$host" -e USER="$user" -e LOGNAME="$user" \
  -v "$checkout:$EC:ro" \
  -v "$BUILD:$EC/build" \
  -v "$dir:/opt/ubuntu-config:ro" \
  "$@" \
  "$BUILD_IMAGE" \
  /opt/ubuntu-config/build.sh "$version" "$project"

output=$BUILD/zephyr/$project/output
# build.sh checked the version string, which also names the output.
name=$(grep -a -o -m 1 -E "$project-$version-[0-9a-f]+\+?" "$output/ec.bin" | head -n 1)
rm -rf "${dir:?}/out/$name"
cp -a "$output" "$dir/out/$name"
echo "output in $dir/out/$name"
