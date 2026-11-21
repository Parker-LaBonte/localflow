#!/usr/bin/env python3
"""Copy whisper-server and llama-server (Homebrew builds) plus every non-system library they load into
LocalFlow.app, and rewrite the load paths so the app runs on a Mac without Homebrew.

  Contents/Helpers/      whisper-server, llama-server, ggml backend plugins (*.so; ggml looks next to the executable)
  Contents/Frameworks/   libwhisper, libllama, libggml*, OpenSSL, ...

usage: bundle_engines.py <LocalFlow.app>
"""
import os, re, shutil, subprocess, sys

APP = sys.argv[1]
HELPERS = os.path.join(APP, "Contents/Helpers")
FRAMEWORKS = os.path.join(APP, "Contents/Frameworks")
BINARIES = ["whisper-server", "llama-server"]
BREW = subprocess.run(["brew", "--prefix"], capture_output=True, text=True).stdout.strip() or "/opt/homebrew"


def sh(*a):
    subprocess.run(a, check=True, capture_output=True)


def deps(path):
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True, check=True).stdout.splitlines()[1:]
    return [l.strip().split(" (")[0] for l in out]


def rpaths(path):
    out = subprocess.run(["otool", "-l", path], capture_output=True, text=True, check=True).stdout
    return re.findall(r"cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.+?) \(offset", out)


def resolve(ref, origin):
    """Turn a load command into a real file path, using the original file's rpaths."""
    if ref.startswith("@rpath/"):
        for rp in rpaths(origin):
            cand = os.path.join(rp.replace("@loader_path", os.path.dirname(origin)).replace("@executable_path", os.path.dirname(origin)), ref[7:])
            if os.path.exists(cand):
                return os.path.realpath(cand)
        raise SystemExit(f"can't resolve {ref} from {origin}")
    return os.path.realpath(ref) if ref.startswith(BREW) else None


shutil.rmtree(HELPERS, ignore_errors=True)
shutil.rmtree(FRAMEWORKS, ignore_errors=True)
os.makedirs(HELPERS)
os.makedirs(FRAMEWORKS)

# 1. Executables and ggml backend plugins.
copied = {}   # destination -> original path (for resolving its @rpath references)
for b in BINARIES:
    src = shutil.which(b) or os.path.join(BREW, "bin", b)
    if not os.path.exists(src):
        raise SystemExit(f"{b} not found: brew install whisper-cpp llama.cpp")
    dst = os.path.join(HELPERS, b)
    shutil.copy2(os.path.realpath(src), dst)
    copied[dst] = os.path.realpath(src)
libexec = os.path.join(BREW, "opt/ggml/libexec")
for f in sorted(os.listdir(libexec)):
    if f.endswith(".so"):
        dst = os.path.join(HELPERS, f)
        shutil.copy2(os.path.join(libexec, f), dst)
        copied[dst] = os.path.join(libexec, f)

# 2. Walk the dependency graph, copying every Homebrew library into Frameworks.
queue = list(copied.items())
while queue:
    dst, orig = queue.pop()
    for ref in deps(orig):
        real = resolve(ref, orig)
        if not real:
            continue   # system library
        name = os.path.basename(ref)
        lib_dst = os.path.join(FRAMEWORKS, name)
        if not os.path.exists(lib_dst):
            shutil.copy2(real, lib_dst)
            os.chmod(lib_dst, 0o755)
            copied[lib_dst] = real
            queue.append((lib_dst, real))

# 3. Rewrite load commands: every bundled library is @rpath/<name>, rpath points at Frameworks.
for dst, orig in copied.items():
    os.chmod(dst, 0o755)
    is_lib = dst.startswith(FRAMEWORKS)
    if is_lib:
        sh("install_name_tool", "-id", "@rpath/" + os.path.basename(dst), dst)
    for ref in deps(orig):
        if resolve(ref, orig):
            new = "@rpath/" + os.path.basename(ref)
            if new != ref:
                sh("install_name_tool", "-change", ref, new, dst)
    for rp in rpaths(dst):
        sh("install_name_tool", "-delete_rpath", rp, dst)
    sh("install_name_tool", "-add_rpath", "@loader_path" if is_lib else "@loader_path/../Frameworks", dst)

# 4. Nothing may still point into Homebrew.
for dst in copied:
    bad = [d for d in deps(dst) if d.startswith(BREW)]
    if bad:
        raise SystemExit(f"{dst} still links {bad}")
print(f"bundled {len(BINARIES)} engines, {sum(1 for d in copied if d.endswith('.so'))} backends, "
      f"{len(os.listdir(FRAMEWORKS))} libraries "
      f"({sum(os.path.getsize(p) for p in copied) / 1e6:.0f} MB)")
