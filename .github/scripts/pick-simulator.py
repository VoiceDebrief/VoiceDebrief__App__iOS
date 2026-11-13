#!/usr/bin/env python3
"""Print the UDID of an available simulator on the newest iOS runtime.

    pick-simulator.py [iPhone|iPad]     (default iPhone)

Prefers a plain "iPhone NN" or "iPad Pro …" so test runs are comparable.
Creates one if the runner has none.

On a self-hosted runner (RUNNER_ENVIRONMENT=self-hosted) it always creates a fresh device of the
same type and runtime, named "CI-tmp …", so several runners on one Mac never share a simulator.
The job deletes it at the end.
"""
import json, os, re, subprocess, sys

FAMILY = sys.argv[1] if len(sys.argv) > 1 else "iPhone"
PLAIN = r"iPhone \d+" if FAMILY == "iPhone" else r"iPad Pro.*"

def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout

def version(runtime_key):
    nums = re.findall(r"(\d+)", runtime_key.split("iOS-")[-1])
    return tuple(int(n) for n in nums)

devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j"))["devices"]
ios = sorted((k for k in devices if ".iOS-" in k), key=version, reverse=True)
for runtime in ios:
    phones = [d for d in devices[runtime] if d["name"].startswith(FAMILY)]
    if not phones:
        continue
    plain = [d for d in phones if re.fullmatch(PLAIN, d["name"])]
    pick = (plain or phones)[-1]
    if os.environ.get("RUNNER_ENVIRONMENT") == "self-hosted":
        tag = "-".join(os.environ.get(k, "") for k in ("GITHUB_RUN_ID", "GITHUB_JOB", "RUNNER_NAME"))
        udid = run("xcrun", "simctl", "create", f"CI-tmp {pick['name']} {tag}",
                   pick["deviceTypeIdentifier"], runtime).strip()
        print(f"Created CI-tmp {pick['name']} on {runtime.split('.')[-1]} ({udid})", file=sys.stderr)
        print(udid)
        sys.exit(0)
    print(f"Using {pick['name']} on {runtime.split('.')[-1]} ({pick['udid']})", file=sys.stderr)
    print(pick["udid"])
    sys.exit(0)

runtimes = json.loads(run("xcrun", "simctl", "list", "runtimes", "available", "-j"))["runtimes"]
ios_rt = [r for r in runtimes if r.get("platform") == "iOS"]
if not ios_rt:
    sys.exit("No iOS simulator runtime on this runner")
rt = ios_rt[-1]
dtype = [d for d in rt.get("supportedDeviceTypes", []) if d["name"].startswith(FAMILY)][-1]
udid = run("xcrun", "simctl", "create", f"CI {FAMILY}", dtype["identifier"], rt["identifier"]).strip()
print(f"Created {dtype['name']} on {rt['name']} ({udid})", file=sys.stderr)
print(udid)
