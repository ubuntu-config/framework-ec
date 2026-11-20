#!/bin/sh
#
# Prints the names of the build image, which Dockerfile defines, and of the test image, which Dockerfile.test makes from
# it, as BUILD_IMAGE=<name> and TEST_IMAGE=<name> lines, the format of a dotenv file. Each image is tagged with the
# first 12 hex digits of the SHA-256 of the Dockerfiles it is made from, so that a changed Dockerfile names a new image,
# while with unchanged Dockerfiles CI and local builds keep using the image built before.
#
#
# Usage
# -----
#   image-tags.sh [REPOSITORY]
#
#   REPOSITORY  the image repository, registry.gitlab.com/ubuntu-config/framework-ec by default

set -eu

dir=$(dirname "$0")
repository=${1:-registry.gitlab.com/ubuntu-config/framework-ec}

build=$(sha256sum < "$dir/Dockerfile" | cut -c 1-12)
test=$(cat "$dir/Dockerfile" "$dir/Dockerfile.test" | sha256sum | cut -c 1-12)

echo "BUILD_IMAGE=$repository/build:$build"
echo "TEST_IMAGE=$repository/test:$test"
