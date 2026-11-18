import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("dt", Path(__file__).with_name("prepare-dt.py"))
dt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dt)
nodes, _, _ = dt.read_dtb(Path(sys.argv[1]).read_bytes())
live = Path("/proc/device-tree")
handles = {p["phandle"]: n for n, p in nodes.items() if "phandle" in p}
for path, props in nodes.items():
    names = ("reg", "status", "no-map", "reusable", "compatible", "alignment") if path.startswith("/reserved-memory/") else ()
    if path == "/chosen":
        names = ("bbai64-tidl-profile",)
    if "memory-region" in props and ("/dsp@" in path or "/r5f@" in path):
        names = ("status", "firmware-name")
        current = (live / path[1:] / "memory-region").read_bytes()
        expected = props["memory-region"]
        if len(current) != len(expected):
            raise SystemExit(f"{path}: region count mismatch")
        for i in range(0, len(current), 4):
            region = live / handles[expected[i:i+4]][1:]
            if current[i:i+4] != (region / "phandle").read_bytes():
                raise SystemExit(f"{path}: phandle target mismatch at index {i//4}")
    for name in names:
        file = live / path[1:] / name
        actual = file.read_bytes() if file.exists() else None
        if props.get(name) != actual:
            raise SystemExit(f"{path}/{name}: differs from candidate")
print("candidate reservations and remoteproc references verified")
