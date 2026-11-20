# Build environment for Framework EC firmware which reproduces Framework's release builds. build.sh runs zmake in it,
# in CI and through build-ec.sh. The paths are those of a ChromiumOS checkout in the SDK chroot, where release builds
# run: the EC checkout is at /mnt/host/source/src/platform/ec.

# tozd's base image, which tozd rebuilds every day with the current packages of Ubuntu noble, so that a rebuild of this
# image brings them along, and CI shows whether the firmware still builds and passes its tests with them. Ubuntu noble
# has Python 3.12. The tests of zmake, which run in the image Dockerfile.test makes from this one, rely on argparse and
# pathlib internals which Python 3.13 changed.
FROM registry.gitlab.com/tozd/docker/base:ubuntu-noble

# clang preprocesses the devicetree (the host side of the coreboot-sdk toolchain) and serves binman as a preprocessor.
RUN apt-get update -q -q && \
  apt-get install --yes --no-install-recommends ca-certificates curl git zstd \
    python3 python3-yaml python3-pykwalify python3-ruamel.yaml python3-dateutil python3-packaging python3-pyelftools \
    python3-colorama python3-setuptools \
    python3-libfdt cmake ninja-build device-tree-compiler clang lld llvm && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

# zmake locates the checkout by its .repo directory and the Zephyr modules under src/third_party/zephyr.
RUN mkdir -p /mnt/host/source/.repo /mnt/host/source/src/platform/ec

# Zephyr at the commit which the boot banner of lilac 4.0.2 names. The banner shows "git describe --abbrev=12 --always",
# which is the abbreviated commit in a clone without tags.
RUN git init -q /mnt/host/source/src/third_party/zephyr/main && \
  cd /mnt/host/source/src/third_party/zephyr/main && \
  git fetch -q --depth 1 --no-tags https://github.com/FrameworkComputer/zephyr 8bdbcbbbe6bfecf4067379e9eae146c6d01c7f64 && \
  git checkout -q FETCH_HEAD

RUN git init -q /mnt/host/source/src/third_party/zephyr/cmsis && \
  cd /mnt/host/source/src/third_party/zephyr/cmsis && \
  git fetch -q --depth 1 --no-tags https://chromium.googlesource.com/chromiumos/third_party/zephyr/cmsis b45330c9efcf435003113ea14ba2c0fae407b0fa && \
  git checkout -q FETCH_HEAD

# zmake packs the image with binman, which runs from the u-boot tree with dtoc and u_boot_pylib next to it.
RUN git init -q /opt/u-boot && \
  cd /opt/u-boot && \
  git fetch -q --depth 1 --no-tags https://chromium.googlesource.com/chromiumos/third_party/u-boot 923f25080339770806369e41767f8d0464f2b451 && \
  git checkout -q FETCH_HEAD

# The coreboot-sdk toolchain as eclass/coreboot-sdk-ec-dependencies.eclass of chromiumos-overlay pins it from April 2025
# until August 2026: archives in the chromiumos-sdk bucket as <target>/<version>/<hash>, with their SHA-256. Each is
# extracted to /opt/coreboot-sdk/<target>.
RUN set -e; \
  for archive in \
    "arm-eabi/14.2.0-r4/ea40ddd1d190c3b48435c474c0b545719371813a 2c5ca3b84752e9ab5b987332741c47a614f6814ea796b26c737d9042bc7b0156" \
    "picolibc-arm-eabi/14.2.0-r2/422a2aa3e1ef891b5bece9a3deb696ff83840d2e d3d9ca67d21a670524ef8445f4b11700bdec8bd55b04b9c118f7404807bcc176" \
    "libstdcxx-arm-eabi/14.2.0-r2/5d7d82e150e44aa1968f1d366e267e6687b328ac 81d5387f4e87bc339bd70baa36ccb629780f82816302e30fc2093dfb9ba5afd0" \
  ; do \
    set -- $archive; \
    curl -sS -f -o /tmp/toolchain.tar.zst "https://storage.googleapis.com/chromiumos-sdk/toolchains/coreboot-sdk-$1.tar.zst"; \
    echo "$2  /tmp/toolchain.tar.zst" | sha256sum -c --quiet; \
    mkdir -p "/opt/coreboot-sdk/${1%%/*}"; \
    tar -xf /tmp/toolchain.tar.zst -C "/opt/coreboot-sdk/${1%%/*}"; \
    rm /tmp/toolchain.tar.zst; \
  done

# zmake runs from the EC checkout. With COREBOOT_SDK_ROOT set, it does not run util/coreboot_sdk.py, which downloads
# the toolchain which the eclass of a ChromiumOS checkout pins.
RUN printf '#!/bin/sh\nexec python3 -m zmake "$@"\n' > /usr/local/bin/zmake && chmod +x /usr/local/bin/zmake
ENV CROS_WORKON_SRCROOT=/mnt/host/source \
  PYTHONPATH=/mnt/host/source/src/platform/ec/zephyr/zmake \
  TOOL_PATH_binman=/opt/u-boot/tools/binman/binman \
  COREBOOT_SDK_ROOT=/opt/coreboot-sdk/arm-eabi \
  COREBOOT_SDK_ROOT_arm=/opt/coreboot-sdk/arm-eabi \
  COREBOOT_SDK_ROOT_picolibc_arm=/opt/coreboot-sdk/picolibc-arm-eabi \
  COREBOOT_SDK_ROOT_libstdcxx_arm=/opt/coreboot-sdk/libstdcxx-arm-eabi

WORKDIR /mnt/host/source/src/platform/ec
