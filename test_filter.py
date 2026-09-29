Import("env")
import os
import sys

filter_val = None
try:
    with open(f"/proc/{os.getppid()}/cmdline", "rb") as fp:
        cmdline = fp.read().decode("latin1").split(chr(0))
    for i, arg in enumerate(cmdline):
        if arg in ("-f", "--filter") and i + 1 < len(cmdline):
            filter_val = cmdline[i + 1]
        elif arg.startswith("-f="):
            filter_val = arg.split("=", 1)[1]
        elif arg.startswith("--filter="):
            filter_val = arg.split("=", 1)[1]
except Exception:
    pass

def test_filter_middleware(env, node):
    path = node.srcnode().get_path()
    if "firmware/tests" in path:
        filename = os.path.basename(path)
        if filter_val and not filename.startswith(filter_val):
            return None
    return node

env.AddBuildMiddleware(test_filter_middleware)
