# Framework EC builds and tests

This directory builds the embedded controller (EC) firmware of the Framework Laptop 13 (AMD Ryzen AI 300), the zmake
project lilac, the way Framework builds its releases, and runs the test suites of the EC repository, locally and in
GitLab CI. A clean checkout of a release commit gives the released image, except for the build date.

The branch ubuntu-config starts at Framework's release 4.0.2, fdbf54948b5c "fwk: lilac: bump to v4.0.2" (the head of
fwk-lilac-refresh), and holds local changes on top of it. The other branches are Framework's, as they are on GitHub.

## Files

- `Dockerfile`: the build image, with the coreboot-sdk toolchain of GCC, picolibc and libstdc++ as chromiumos-overlay
  pins it (checked by SHA-256), Zephyr at the commit the boot banner of the released image names, CMSIS, and binman
  of u-boot, on tozd's Ubuntu noble base image.
- `Dockerfile.test`: the test image, the build image plus what the test suites need, see Tests.
- `image-tags.sh`: names both images by the hash of the Dockerfiles they are made from.
- `build.sh` and `test.sh`: build the firmware and run one test step, inside the images, in CI and locally.
- `build-ec.sh` and `test-ec.sh`: run `build.sh` and `test.sh` in the images with the local docker.
- `local-images.sh`: makes an image available to the local docker, from the registry or built from its Dockerfile.
- `compare-ec.py`: compares two EC images and tells whether they differ only in their version strings and build
  dates.
- `version`: the base version string zmake makes the version of the image from, `<project>-<version>-<commit>`.
- `out/` and `test-logs/`: outputs of `build-ec.sh` and `test-ec.sh`, which git ignores.

## Images

Both images are kept in the container registry of the project, as `build:<hash>` and `test:<hash>` of
`registry.gitlab.com/ubuntu-config/framework-ec`, where the hash is that of their Dockerfiles. CI and the local scripts
use the image of the current Dockerfiles from there, and build it only when the registry does not have it. Nothing
deletes images from the registry.

The base image is `registry.gitlab.com/tozd/docker/base:ubuntu-noble`, which tozd rebuilds every day with the current
packages of Ubuntu noble, by its tag. A changed Dockerfile is therefore built on that day's base image, and the next
pipeline shows whether the firmware still builds and passes the tests with it. Ubuntu noble has Python 3.12, which
zmake's own tests need: they rely on argparse and pathlib internals which Python 3.13 changed. The firmware itself also
builds byte for byte the same on Ubuntu resolute.

## CI

`.gitlab-ci.yml` at the top of the repository runs, for every push of a branch which has it:

- `images`: builds and pushes the images the registry does not have yet, with docker-in-docker.
- `build`: builds lilac with `build.sh`, as user lotus on host ip-172-26-3-226 like Framework's build machine, and
  keeps `build/zephyr/lilac/output/`, with `ec.bin`, as an artifact.
- `test` and `test_large`: one job per step of `test.sh`. The legacy tests and twister run on GitLab's largest hosted
  runner, `saas-linux-2xlarge-amd64`. Each job keeps the output of its step in `test-logs/`, and twister's reports.

The checkout has to be at `/mnt/host/source/src/platform/ec`, its path in the ChromiumOS SDK chroot, which the jobs
bind-mount their checkout to.

## Local use

```sh
ubuntu-config/build-ec.sh                    # builds the checkout, output in ubuntu-config/out/<version string>
ubuntu-config/test-ec.sh                     # runs all test steps on HEAD, logs in ubuntu-config/test-logs/<time>
ubuntu-config/test-ec.sh zmake compliance    # runs only these steps
ubuntu-config/compare-ec.py A.bin B.bin
```

To check a release, build its commit in a worktree with `build-ec.sh -C <worktree>` and compare the image with a dump
of the EC flash (`framework_tool --dump-ec-flash`): they differ only in the build date and in 0x7f000-0x7f04f, the
flash storage which the EC writes at runtime and which is erased in every built image.

## Toolchain

zmake selects the coreboot-sdk toolchain for lilac. Without `COREBOOT_SDK_ROOT` in the environment it runs
`util/coreboot_sdk.py`, which downloads the archives which
`third_party/chromiumos-overlay/eclass/coreboot-sdk-ec-dependencies.eclass` of a ChromiumOS checkout pins, and the build
image sets it to the archives it contains instead. The pins changed on 2025-04-16 (Gerrit 6350060, GCC 14.2.0-r4 for
arm-eabi) and on 2026-08-14 (Gerrit 8253358, GCC 15.2.0), so a build of 4.0.2 in June 2026 used the 14.2.0 ones.
Framework's `flake.nix` uses the toolchain of the Zephyr SDK (GCC 12.2.0 of Zephyr SDK 0.16.9) and Zephyr e414f3a, which
give a different image.

## Tests

`test.sh` runs the steps of `firmware_builder.py test` and `zephyr/firmware_builder.py test`, which ChromiumOS's
builders run, without code coverage: `stack-analyzer`, `util`, `legacy` and `legacy-asan` (the legacy host tests,
without and with AddressSanitizer), `zmake` (zmake's own tests), `compliance`, and `twister-host` and `twister-llvm`
(the Zephyr tests with gcc and with clang). It leaves out the steps which need compilers of the ChromiumOS SDK: the
legacy host tests built with x86_64-cros-linux-gnu, and the on-device unit tests of the fingerprint boards, which
ChromiumOS only compiles, with armv7m-cros-eabi.

The test image adds to the build image what these need, as `Dockerfile.test` documents: 32-bit gcc, the libraries of
the legacy host tests, the Python modules of twister and of the EC's tests, the other modules of a ChromiumOS checkout
at the commits its manifest had on 2025-03-04, the date of the last upstream commit in the lilac branch,
libprotobuf-mutator, and Kitware's ninja with GNU make jobserver support, as the ChromiumOS SDK has it. Without the
jobserver, twister's parallel builds overload the machine and native_sim tests run into their timeouts. Compiler
wrappers add the flags of the ChromiumOS SDK's compiler wrapper, which upstream code relies on.

All steps pass on the branch ubuntu-config. Of twister's configurations, one only builds, by design.
