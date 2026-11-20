#!/usr/bin/env python3
#
# Compares two EC images byte by byte and prints each differing range together with the printable text around it,
# so that differences which are only in the version string and the build date are easy to tell apart from code
# changes. It exits with 0 when every differing range lies within such text, and with 1 otherwise.
#
#
# Usage
# -----
#   compare-ec.py A.bin B.bin

import re
import sys

# The build information contains the version string, the build date and the builder, like
# "lilac-4.0.2-fdbf549 2026-06-08 05:27:31 lotus@ip-172-26-3-226", and the firmware IDs contain the version string
# alone. A trailing "+" marks a build from a dirty tree.
VERSION_TEXT = re.compile(rb"^[a-z0-9]+-[0-9.]+-[0-9a-f]{7,}\+?( \d{4}-\d\d-\d\d \d\d:\d\d:\d\d \S+)?$")


def text_around(data, start, end):
    """Returns the printable run of bytes which contains data[start:end], or None when the range is not printable."""
    if not all(0x20 <= byte < 0x7F for byte in data[start:end]):
        return None
    while start > 0 and 0x20 <= data[start - 1] < 0x7F:
        start -= 1
    while end < len(data) and 0x20 <= data[end] < 0x7F:
        end += 1
    return data[start:end]


def main():
    if len(sys.argv) != 3:
        print("usage: compare-ec.py A.bin B.bin", file=sys.stderr)
        return 2
    a = open(sys.argv[1], "rb").read()
    b = open(sys.argv[2], "rb").read()
    if len(a) != len(b):
        print(f"sizes differ: {len(a)} and {len(b)}")
        return 1

    # Differing bytes which are at most 8 bytes apart form one range.
    ranges = []
    for i in range(len(a)):
        if a[i] != b[i]:
            if ranges and i - ranges[-1][1] <= 8:
                ranges[-1][1] = i
            else:
                ranges.append([i, i])

    only_version = True
    for start, end in ranges:
        text_a = text_around(a, start, end + 1)
        text_b = text_around(b, start, end + 1)
        expected = (
            text_a is not None
            and text_b is not None
            and VERSION_TEXT.match(text_a)
            and VERSION_TEXT.match(text_b)
        )
        only_version = only_version and bool(expected)
        print(f"{start:#08x}-{end:#08x} {'version/date' if expected else 'OTHER'}: {text_a!r} {text_b!r}")
    print(f"{len(ranges)} differing ranges, {'only version and date' if only_version else 'NOT only version and date'}")
    return 0 if only_version else 1


if __name__ == "__main__":
    sys.exit(main())
