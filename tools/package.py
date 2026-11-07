"""Zip the addon for release, with only the files the game needs.

    python tools/package.py [output folder]

Writes <output>/SynastriaBuildSuite-<version>.zip with a top-level SynastriaBuildSuite/ folder (extract it into
Interface/AddOns): the .toc, the Lua files the .toc loads, and the textures.
"""
import os, re, sys, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DIST = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "dist")
NAME = "SynastriaBuildSuite"


def toc_info(addon):
    lines = open(os.path.join(addon, NAME + ".toc"), encoding="utf-8").read().splitlines()
    meta = dict(re.match(r"##\s*([^:]+):\s*(.*)", l).groups() for l in lines if re.match(r"##\s*[^:]+:", l))
    loaded = [l.strip().replace("\\", "/") for l in lines if l.strip() and not l.startswith("#")]
    return meta, loaded


def files_matching(addon, test):
    found = []
    for folder, _, names in os.walk(addon):
        for n in names:
            if test(n):
                found.append(os.path.relpath(os.path.join(folder, n), addon).replace("\\", "/"))
    return found


def main():
    addon = os.path.join(ROOT, NAME)
    meta, loaded = toc_info(addon)
    version = meta.get("Version", "0").strip()
    files = [NAME + ".toc"] + loaded + files_matching(addon, lambda n: n.lower().endswith((".tga", ".blp")))
    missing = [f for f in files if not os.path.isfile(os.path.join(addon, f))]
    if missing:
        sys.exit("not packaged, missing:\n  " + "\n  ".join(missing))
    stray = sorted(set(files_matching(addon, lambda n: n.endswith(".lua"))) - set(loaded))
    if stray:
        print("not in the .toc, left out: " + ", ".join(stray))
    os.makedirs(DIST, exist_ok=True)
    out = os.path.abspath(os.path.join(DIST, "%s-%s.zip" % (NAME, version)))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            z.write(os.path.join(addon, f), NAME + "/" + f)
    print("%s  (%d files, %.0f KB)" % (out, len(files), os.path.getsize(out) / 1024))


if __name__ == "__main__":
    main()
