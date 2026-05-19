# -*- coding: utf-8 -*-
"""
Test driver — runs every operation script under windows-runner/operations/
with mocked Revit modules. Catches:

  - Syntax errors (also caught by python:check, but cheap to redo here)
  - Import errors not caught by ruff (e.g. typo in a clr.AddReference)
  - Top-level exceptions during script execution (wrong function signature,
    bad attribute access, etc.)

Doesn't catch:
  - Wrong Revit API behaviour (mock absorbs any call)
  - Real-model edge cases (no real .rvt is involved)

Per-operation pass = the script runs to completion under mocks without
raising. Real validation still happens via RDP inside Revit, but this
catches the easy ~80% locally.
"""

import os
import sys
import traceback
from pathlib import Path

# Add tests/ to sys.path so we can import the mocks installer
sys.path.insert(0, str(Path(__file__).parent))
import revit_mocks  # noqa: E402

REPO_ROOT = Path(__file__).parent.parent
OPERATIONS_DIR = REPO_ROOT / "windows-runner" / "operations"


def find_operation_scripts():
    """Find all revit-side.py files under windows-runner/operations/."""
    return sorted(OPERATIONS_DIR.rglob("revit-side.py"))


def run_one(script_path):
    """Exec a single operation script with mocks in place. Return True on
    success, False on uncaught exception."""
    revit_mocks.install()
    with script_path.open("r", encoding="utf-8") as f:
        source = f.read()
    code = compile(source, str(script_path), "exec")
    # Force DEBUG path so the script doesn't try to call revit_script_util
    # functions whose mock returns might not match what the script expects.
    # We do this by injecting DEBUG=True into the script's globals BEFORE
    # exec — but the script also reassigns DEBUG at the top, so the
    # alternative is to just let the script run as-is (DEBUG=False by
    # default) and rely on mocks to absorb the calls.
    ns = {"__name__": "__main__"}
    try:
        exec(code, ns)
        return True, None
    except Exception:
        return False, traceback.format_exc()


def main():
    scripts = find_operation_scripts()
    if not scripts:
        print(f"no operation scripts found under {OPERATIONS_DIR}")
        return 0

    def rel(p):
        return p.relative_to(REPO_ROOT)

    fails = 0
    for s in scripts:
        ok, err = run_one(s)
        if ok:
            print(f"  PASS  {rel(s)}")
        else:
            print(f"  FAIL  {rel(s)}")
            for line in err.rstrip().splitlines():
                print(f"        {line}")
            fails += 1

    if fails:
        print(f"\n{fails}/{len(scripts)} failed")
        return 1
    print(f"\n{len(scripts)}/{len(scripts)} passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
