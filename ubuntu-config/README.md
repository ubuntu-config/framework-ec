# Framework EC builds and tests

This directory builds the embedded controller (EC) firmware of the Framework Laptop 13 (AMD Ryzen AI 300), the zmake
project lilac, the way Framework builds its releases, and runs the test suites of the EC repository, locally and in
GitLab CI. Built as Framework's build machine, a clean checkout of a release commit gives the released image, except
for the build date.

It is part of [ubuntu-config](https://gitlab.com/ubuntu-config/ubuntu-config), the configuration of Ubuntu 26.04 with
GNOME 50 on a Framework Laptop 13 Pro, which this firmware runs on. See there for more about the laptop and its setup,
and for the fixes to the rest of the system.

The branch ubuntu-config starts at Framework's release 4.0.2, fdbf54948b5c "fwk: lilac: bump to v4.0.2" (the head of
fwk-lilac-refresh), and holds local changes on top of it. The other branches are Framework's, which this repository
mirrors from [Framework's EC repository](https://github.com/FrameworkComputer/EmbeddedController).

## Contents

- [Changes](#changes): what the branch ubuntu-config changes in Framework's release 4.0.2.
  - [Fixes](#fixes): the AC state, a lost temperature sensor, the charge sustainer, Linux's charge thresholds, UCSI,
    and Framework's own fixes after 4.0.2.
  - [Additions](#additions): the fan's duty cycle and control, and the battery's temperature, for Linux.
  - [Preferences](#preferences): no active discharge, and a quieter EC console.
  - [Test repairs](#test-repairs): the EC's test suites build and pass with Framework's code.
- [Flashing](#flashing): trying the firmware in RW, then making it permanent in RO.
- [Files](#files), [Images](#images), [CI](#ci), [Local use](#local-use), [Toolchain](#toolchain) and
  [Tests](#tests): how the firmware is built and tested.
- [GitHub mirror](#github-mirror).

## Changes

What the branch ubuntu-config changes in Framework's release 4.0.2, `git log fdbf54948b..ubuntu-config` in detail.

### Fixes

- **The AC state does not bounce when the charger is plugged or unplugged**
  ([issue 88](https://github.com/FrameworkComputer/EmbeddedController/issues/88)). The battery flags which the host
  reads could carry the AC state from before the change, so Linux's `ACAD/online` flipped three times within about
  150 ms. They now carry the AC state at the time they are written.
- **A temperature sensor which stops answering runs the fan at full speed**
  ([issue 69](https://github.com/FrameworkComputer/EmbeddedController/issues/69)). After days of uptime the I2C bus of
  the board's F75303 sensors can stall, and the driver kept reporting the last readings, so the fan followed frozen
  temperatures and could stay off while the processor heated up. The driver now reports a channel which failed three
  polls in a row as lost, the host sees it fail to read, and thermal control runs the fan at full speed while a sensor
  with a fan curve is lost. A suspend and resume frees the bus, and the fan follows the sensors again.
- **The charge stays in the sustain range**
  ([issue 102](https://github.com/FrameworkComputer/EmbeddedController/issues/102)). Connecting AC, and the host
  setting the charge thresholds, which Linux does at every write of a threshold and when `charge_behaviour` returns to
  `auto`, charged the battery to the upper threshold even with the charge already in the range. The charge is now
  kept, and the battery charges to the upper threshold only once it falls below the lower one.
- **Linux's charge thresholds hold with the firmware's own charge limit at 100%**
  ([SoftwareFirmwareIssueTracker issue 85](https://github.com/FrameworkComputer/SoftwareFirmwareIssueTracker/issues/85)).
  With the limit in the BIOS at 100%, the firmware cleared the charge sustainer every second, which removed the
  thresholds set from Linux. It now clears it once, when the limit changes to 100%.
- **The UCSI error status is read from the right byte**
  ([issue 89](https://github.com/FrameworkComputer/EmbeddedController/issues/89)).
- **The USB-C ports keep working after a jump or an EC reset**. An image which started with the laptop off after a
  jump between EC images, or after an EC reset other than a power-on, told both PD controllers the system power state
  G3. The controllers had kept running, and after that they no longer detected chargers or devices, until they lost
  power when the EC next hibernated. Such an image now leaves them in their state, and tells them G3 only when the
  laptop enters it, or after a power-on reset, when the controllers have just powered up as well.
- **A jump into this firmware survives a running fan or a lit side LED**
  ([Zephyr pull request 96203](https://github.com/zephyrproject-rtos/zephyr/pull/96203)). Zephyr's NPCX PWM driver
  checks its register access by writing the prescaler register before it switches the PWM off, and the register
  ignores writes while the PWM runs. After a jump the PWMs keep running as the previous image left them, so with the
  fan spinning or the side LED lit the new image halted while it started, and the EC restarted in RO. The build
  applies Nuvoton's fix from upstream Zephyr, which Framework's Zephyr lacks, from `zephyr/`.
- **An expansion card comes back after a reverse current error at power-on**. When the laptop powers on, a PD
  controller can report a reverse current error on a port which supplies an expansion card, like the HDMI Expansion
  Card. It then usually sends a hard reset and the card connects again, but after a jump it sometimes does not, and the
  port detects the card again only after the card is pulled out and inserted again. The EC now disables and enables a
  port which has no partner 5 seconds after a reverse current error, which brings the card back, at most once per
  power-on or resume.
- **Framework's fixes after 4.0.2**, from its later branches and
  [pull request 79](https://github.com/FrameworkComputer/EmbeddedController/pull/79): no crash on garbage PD data, an
  invalid PD port index rejected, the PD charge ceiling applied to the right controller, only F1 to F12 ignoring Fn
  Lock in the BIOS, and a typo.

### Additions

- **The fan's duty cycle and control for Linux**
  ([issue 98](https://github.com/FrameworkComputer/EmbeddedController/issues/98)). The upstream host commands
  `EC_CMD_PWM_GET_FAN_DUTY` and version 2 of `EC_CMD_THERMAL_AUTO_FAN_CTRL`, with which Linux's `cros_ec` hwmon device
  offers `pwm1` (the duty cycle), `pwm1_enable` (manual or automatic control) and the fan as a thermal cooling device.
- **The battery's temperature for Linux**. The EC reports it as the temperature sensor `battery_temp@b`, which Linux
  shows in the `cros_ec` hwmon device.

### Preferences

- **The charge sustainer never discharges the battery actively**. A charge above the upper threshold, as when the
  thresholds are set after a full charge, is kept and comes down as the battery discharges without AC, instead of the
  laptop running from its battery on AC until the charge reaches the upper threshold. A host which asks for no idle
  mode keeps the sustainer discharging.
- **Reads of the fan target stay out of the EC console**. Linux reads the fan target at every read of its hwmon
  attribute, and the EC counts these in its hourly summary of suppressed host commands instead of logging each.

### Test repairs

Eleven changes to Framework's Kconfig defaults, headers and tests make the configurations of the EC's test suites
build and pass with Framework's code, for example by matching the default task priorities to the tasks Framework adds,
and by building the PD host commands without a standalone PD chip. They do not change the firmware of lilac.

## Flashing

`framework_tool` flashes the firmware from Linux, as root, from version 0.6.6 on: earlier versions use an outdated
layout of the EC's flash, which leaves out the end of the RW image. The image is the `ec.bin` of a local build or of the
artifact of the `build` job of the commit's pipeline. Save a copy of the firmware the EC has first, with
`framework_tool --dump-ec-flash`.

The EC boots its RO copy and runs the RW copy only after a jump to it, so the firmware can be tried in RW, and any EC
reset returns to RO: the laptop off without AC for 30 seconds, after which the EC hibernates, an EC reboot, a battery
disconnect, or a BIOS update. A jump powers the laptop off at once, and the power button starts it again.

Framework's firmware lacks both jump fixes under Changes, so a jump into its RO, with `jump-ro`, or into RW while RW
holds its firmware, halts while the new image starts if the fan spins or the side LED is lit, and the EC restarts in
RO. And when its image starts with the laptop off after a jump or after an EC reset other than a power-on, as RO does
after such a restart, the USB-C ports can stop working until the EC hibernates (30 seconds off on battery). Before
such a jump, stop the fan with `framework_tool --fansetduty 0` and the keyboard backlight with
`framework_tool --kblight 0`, and darken the side LED, by unplugging the charger or with
`framework_tool --host-command 0x29 1 0 0 0 0 0 0 0 0`.

```sh
sudo framework_tool --flash-rw-ec ec.bin
sudo framework_tool --reboot-ec jump-rw    # powers off at once
sudo framework_tool --versions             # after the restart: "Current image: RW"
```

Flashing RO as well makes the firmware permanent. An RO which does not boot can be recovered only through the EC's
debug pads with a UART adapter, so only an image which ran well in RW is flashed there.

On battery, the EC's replies to host commands arrive corrupted from time to time while the processor uses its deepest
idle state ([SoftwareFirmwareIssueTracker issue 308](https://github.com/FrameworkComputer/SoftwareFirmwareIssueTracker/issues/308)),
which can make a flash fail, so it is best done on AC.

## Files

- `Dockerfile`: the build image, with the coreboot-sdk toolchain of GCC, picolibc and libstdc++ as chromiumos-overlay
  pins it (checked by SHA-256), Zephyr at the commit the boot banner of the released image names, CMSIS, and binman
  of u-boot, on tozd's Ubuntu noble base image.
- `Dockerfile.test`: the test image, the build image plus what the test suites need, see Tests.
- `image-tags.sh`: names both images by the hash of the Dockerfiles they are made from.
- `build.sh` and `test.sh`: build the firmware and run one test step, inside the images, in CI and locally.
- `zephyr/` and `apply-zephyr-patches.sh`: fixes from upstream Zephyr which the Zephyr commit of the release lacks, as
  patches, which `build.sh` and `test.sh` apply to the image's Zephyr. They come from the checkout which is built, so a
  checkout of one of Framework's releases builds with Zephyr unchanged.
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
- `build`: builds lilac with `build.sh`, as user ubuntu-config on host framework-ec like `build-ec.sh`, and keeps
  `build/zephyr/lilac/output/`, with `ec.bin`, as an artifact.
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

The image contains the user and host name of the build, ubuntu-config@framework-ec in CI and by default in
`build-ec.sh`. To check a release, build its commit in a worktree with `build-ec.sh -C <worktree> -R`, as user lotus on
host ip-172-26-3-226 like Framework's build machine of lilac 4.0.2, and compare the image with a dump of the EC flash
(`framework_tool --dump-ec-flash`): they differ only in the build date and in 0x7f000-0x7f04f, the flash storage which
the EC writes at runtime and which is erased in every built image. A user and host name of another length moves the
data after them, so the image differs throughout.

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

## GitHub mirror

There is also a [read-only GitHub mirror available](https://github.com/ubuntu-config/framework-ec),
if you need to fork the project there.
