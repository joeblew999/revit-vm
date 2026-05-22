# Startup config for yoke (ai:ask / ai:chat tasks).
# Loaded once via --config; every subsequent LLM nu-tool call sees these defs.
# CWD is always the repo root (ai:* tasks set dir = "{{config_root}}").

# Friendly wrappers — call these directly from the nu tool without knowing paths.
# All shell out to existing scripts so there are no module resolution issues.

def vm-state [] { ^nu gui/state/aggregate.nu }
def vm-ip []    { ^nu lifecycle/dispatch.nu ip | str trim }
def vm-runs []  { ^nu state/runs.nu }
