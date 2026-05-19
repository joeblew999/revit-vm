# operations/revit/export-ifc

The first operation. Exports an open Revit model to IFC.

Layers (architecture context in [SERVICE.md](../../../../SERVICE.md) → "Three layers per job"):

1. **Vendor app**: Revit 2026 + Revit Batch Processor v1.12.1 (both pre-installed in the snapshot).
2. **Operation** — this directory:
   - `revit-side.py` — IronPython 2.7 that runs inside Revit, invoked by RBP per opened model. Calls `Document.Export(...)` with IFC2x3 options.
   - `revit-side.rps` — *(not yet generated)* RBP settings file pointing at `revit-side.py` and listing input models. Easiest to create via the RBP GUI once and commit.
   - `Cargo.toml` + `src/main.rs` — *(not yet written)* the Rust outer wrapper for service mode. Cross-compiles to `export-ifc.exe`, drives `BatchRvt.exe`, emits CF observability events.
3. **Job's input + params** — supplied per call via the orchestrator (input .rvt path, output dir, etc.).

## Status

- `revit-side.py`: **starter**, minimum-viable IFC export. Not validated against a real Revit model yet. Run-once-in-RDP first; iterate.
- Rust wrapper: **not started**. Personal-use mode doesn't need it — RBP runs the .py directly. Only needed for service mode (orchestrator + CF observability).
- `.rps` file: **not generated**. Create via RBP GUI once Revit + RBP are installed.

## How to validate (manual, inside Windows via RDP)

1. `mise run start` from the Mac — boot the VM, RDP in.
2. Install Revit (`\\host.lan\Data\install-revit.bat`), sign into your Autodesk account / trial.
3. RBP is installed alongside Revit by the same batch script. Launch RBP from the Start menu.
4. Open a small test .rvt model in Revit at least once (so Revit registers itself).
5. In RBP's GUI:
   - **Revit File List**: point at a folder with one or more test .rvt files. RBP can scan a folder.
   - **Task Script**: browse to `\\host.lan\Data\revit-side.py` (or wherever you've staged it). Set "Python" as the language.
   - **Session Settings**: pick the right Revit version, leave the rest at defaults.
6. Click *Run*. RBP launches Revit, opens each model, runs `revit-side.py` against it. Outputs land in `Z:\output\<model>.ifc`.
7. Check `Z:\output\` from the Mac via `mise run pull -- output/<model>.ifc`.

If it works on one model end-to-end: `mise run stop` to snapshot the validated state.

## Iterating from the starter

Most likely first changes you'll make:

- **Choose IFC version** — switch `IFCVersion.IFC2x3` → `IFC4` if a customer asks.
- **Filter what to export** — currently exports the whole model. To export specific 3D views (e.g. "NWCP_*"), follow @jchristel's pattern in `ModifyExportNWC_IFC.py` (linked in `revit-side.py` comments).
- **Dialog suppression** — uncomment the `DialogBoxShowing` block in `revit-side.py` if a real model surfaces a dialog RBP itself didn't dismiss. Log every dialog ID first, add overrides as you encounter them.
- **Drop in duHast** — once the operation matures, swap the direct `IFCExportOptions` call for `duHast.Revit.Exports.export_ifc.*`. duHast handles edge cases (third-party IFC exporter, coordinate systems, space boundaries) better than the built-in.

Reference (in priority order):
1. [jchristel's IFC/NWC export sample](https://github.com/jchristel/SampleCodeRevitBatchProcessor/blob/master/Samples/Flows/ModifyExportNWC_IFC.py) — closest-to-production pattern
2. [duHast library](https://github.com/jchristel/SampleCodeRevitBatchProcessor/tree/master/src/duHast) — when direct API calls aren't enough
3. [Revit API docs](https://www.revitapidocs.com/) — definitive reference
4. [RBP wiki / FAQ](https://github.com/bvn-architecture/RevitBatchProcessor/wiki/Revit-Batch-Processor-FAQ)

## When this graduates to service mode

Add the Rust wrapper (`Cargo.toml` + `src/main.rs`):

- Read `--job-id / --input / --output / --params` from CLI args.
- Compose a `.rps` settings file at run time pointing at this `revit-side.py` and the per-job input.
- `std::process::Command::new("BatchRvt.exe").args(["-s", &rps_path])` — spawn RBP.
- Tail RBP's log file, parse status, emit `phase_enter`/`phase_exit`/`error` events to the CF ingest Worker.
- `Drop` guard for `job_complete` so even panics produce a final event.
- See [SERVICE.md](../../../../SERVICE.md) → "Observability" for the event schema.

Cross-compile from Mac: `cargo build --release --target x86_64-pc-windows-msvc -p export-ifc`. `mise run push -- target/x86_64-pc-windows-msvc/release/export-ifc.exe`. Snapshot.
