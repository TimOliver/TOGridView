#!/usr/bin/env python3
"""Build an iOS Simulator archive and verify its categories survive static linking.

Requires Xcode and a booted simulator. Run from any directory with:
    python3 Scripts/check-static-library.py --simulator booted
"""

import argparse
import platform
from pathlib import Path
import subprocess
import tempfile


def run(*args):
    subprocess.run(args, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", default="booted", help="Booted simulator name or UDID")
    args = parser.parse_args()
    sources = Path(__file__).resolve().parents[1] / "TOGridView"
    sdk = subprocess.check_output(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True
    ).strip()
    flags = [
        "-target", f"{platform.machine()}-apple-ios15.0-simulator",
        "-isysroot", sdk, "-fobjc-arc", "-fblocks", "-O2", "-Werror",
        "-I", str(sources),
    ]
    with tempfile.TemporaryDirectory(prefix="TOGridView-static-library-") as directory:
        output = Path(directory)
        objects = []
        for source in sorted(sources.glob("*.m")):
            obj = output / (source.stem + ".o")
            run("xcrun", "clang", *flags, "-c", str(source), "-o", str(obj))
            objects.append(str(obj))
        archive = output / "libTOGridView.a"
        run("xcrun", "libtool", "-static", "-o", str(archive), *objects)

        # Use only the public header, like a consumer. The runtime checks cover a
        # method from each category without importing the implementation header.
        client = output / "main.m"
        client.write_text(r'''#import "TOGridView.h"
#import <objc/runtime.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        Class gridClass = [TOGridView class];
        const char *selectors[] = {
            "layoutCells",
            "performInsertionAtIndices:animated:completionHandler:",
            "handleTouchesBegan:withEvent:",
            "prepareNextCell:"
        };
        for (unsigned int i = 0; i < sizeof(selectors) / sizeof(selectors[0]); i++) {
            if (class_getInstanceMethod(gridClass, sel_registerName(selectors[i])) == NULL) {
                fprintf(stderr, "Missing category method: %s\n", selectors[i]);
                return 1;
            }
        }
        puts("All four TOGridView categories loaded from the static library.");
    }
    return 0;
}
''')
        executable = output / "check-static-library"
        run("xcrun", "clang", *flags, str(client), str(archive),
            "-ObjC", "-Wl,-dead_strip", "-framework", "UIKit",
            "-framework", "Foundation", "-framework", "QuartzCore",
            "-framework", "CoreGraphics",
            "-o", str(executable))
        run("xcrun", "simctl", "spawn", args.simulator, str(executable))


if __name__ == "__main__":
    main()
