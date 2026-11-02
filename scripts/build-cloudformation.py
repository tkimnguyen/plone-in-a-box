#!/usr/bin/env python3
"""Build src/aws/cloudformation.yaml from src/aws/cloudformation.in.yaml.

Embeds src/StackScript, gzip-compressed and base64-encoded, where the template
source contains @@STACKSCRIPT_GZIP_B64@@. EC2 limits user data to 16 KB, and the
script alone is larger than that, so it has to be compressed.

Usage:
    python3 scripts/build-cloudformation.py           # write the template
    python3 scripts/build-cloudformation.py --check   # exit 1 if it is out of date
"""

import base64
import gzip
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "src" / "StackScript"
SOURCE = ROOT / "src" / "aws" / "cloudformation.in.yaml"
TARGET = ROOT / "src" / "aws" / "cloudformation.yaml"
PLACEHOLDER = "@@STACKSCRIPT_GZIP_B64@@"
USER_DATA_LIMIT = 16 * 1024

HEADER = (
    "# GENERATED FILE - do not edit. Edit src/aws/cloudformation.in.yaml and run\n"
    "#   python3 scripts/build-cloudformation.py\n"
)


def build() -> str:
    script = SCRIPT.read_bytes()
    # mtime=0 keeps the output identical between runs, so CI can compare it.
    packed = base64.b64encode(gzip.compress(script, compresslevel=9, mtime=0)).decode("ascii")

    # Drop the source file's own header comment, which mentions the placeholder.
    lines = SOURCE.read_text().splitlines(keepends=True)
    while lines and lines[0].startswith("#"):
        lines.pop(0)
    body = "".join(lines)
    if body.count(PLACEHOLDER) != 1:
        sys.exit(f"{SOURCE} must contain {PLACEHOLDER} exactly once")

    # Rough size check of the user data the wrapper produces (packed script plus
    # a wrapper of well under 1 KB).
    if len(packed) + 1024 > USER_DATA_LIMIT:
        sys.exit(f"Embedded script is {len(packed)} bytes; too close to the 16 KB user data limit")

    return HEADER + body.replace(PLACEHOLDER, packed)


def main() -> None:
    output = build()
    if "--check" in sys.argv:
        current = TARGET.read_text() if TARGET.exists() else ""
        if current != output:
            sys.exit(
                f"{TARGET.relative_to(ROOT)} is out of date. "
                "Run: python3 scripts/build-cloudformation.py"
            )
        print(f"{TARGET.relative_to(ROOT)} is up to date")
        return
    TARGET.write_text(output)
    print(f"Wrote {TARGET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
