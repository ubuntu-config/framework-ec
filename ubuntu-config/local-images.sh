# Sourced by build-ec.sh and test-ec.sh, with dir set to the directory of this file. Sets BUILD_IMAGE and TEST_IMAGE to
# the names image-tags.sh gives the images, and defines ensure_build_image and ensure_test_image, each of which makes
# its image available to the local docker: the image it has already, else the one CI pushed to the registry, else one
# built from the Dockerfile.

eval "$("$dir/image-tags.sh")"

ensure_build_image() {
  docker image inspect "$BUILD_IMAGE" > /dev/null 2>&1 && return 0
  docker pull --quiet "$BUILD_IMAGE" > /dev/null 2>&1 && return 0
  # On the current base image, as CI builds a new image.
  docker build --pull --tag "$BUILD_IMAGE" - < "$dir/Dockerfile"
}

ensure_test_image() {
  docker image inspect "$TEST_IMAGE" > /dev/null 2>&1 && return 0
  docker pull --quiet "$TEST_IMAGE" > /dev/null 2>&1 && return 0
  ensure_build_image
  docker build --tag "$TEST_IMAGE" --build-arg "BASE=$BUILD_IMAGE" - < "$dir/Dockerfile.test"
}
