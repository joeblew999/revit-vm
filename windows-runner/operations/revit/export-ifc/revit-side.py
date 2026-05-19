# -*- coding: utf-8 -*-
"""
revit-side.py — the IronPython 2.7 script that runs INSIDE Revit, called
by Revit Batch Processor (RBP) once per opened model.

Job: export the open model to IFC and write the file to a path the
outer Rust wrapper specified via env var.

Architecture context: see SERVICE.md ("Three layers per job") and
REVIT.md ("Why Revit batch automation is the hard part"). This file is
layer 2 — vendor-side companion to the Rust .exe. RBP loads it via
`task_script_file_path` in the .rps settings.

References (when extending this):
- jchristel's ModifyExportNWC_IFC.py (the canonical RBP IFC export):
  https://github.com/jchristel/SampleCodeRevitBatchProcessor/blob/master/Samples/Flows/ModifyExportNWC_IFC.py
- duHast (jchristel's Revit utility library, drop in for serious work):
  https://github.com/jchristel/SampleCodeRevitBatchProcessor/tree/master/src/duHast
- Revit API docs: https://www.revitapidocs.com/

Status: STARTER — minimum viable IFC export, run-once-in-RDP first to
validate, then iterate. Don't ship to production without testing on
real models.
"""

import clr
import os
import sys

# ---------------------------------------------------------------------
# DEBUG flag — True when running this script directly from Revit's
# Python shell (Manage → Macro Manager) for development. False when
# running under RBP via BatchRvt.exe. RBP provides `revit_script_util`;
# direct execution provides `doc`.
# ---------------------------------------------------------------------
DEBUG = False

if not DEBUG:
    import revit_script_util
    clr.AddReference("RevitAPI")
    clr.AddReference("RevitAPIUI")
    DOC = revit_script_util.GetScriptDocument()
    REVIT_FILE_PATH = revit_script_util.GetRevitFilePath()
else:
    # In debug, `doc` is provided by the Revit macro environment.
    DOC = doc  # noqa: F821 (provided at runtime)
    REVIT_FILE_PATH = DOC.PathName

import Autodesk.Revit.DB as DB


# ---------------------------------------------------------------------
# Output helper — RBP captures revit_script_util.Output() into its own
# log; in DEBUG we fall back to print().
# ---------------------------------------------------------------------
def output(msg):
    if not DEBUG:
        revit_script_util.Output(str(msg))
    else:
        print(msg)


# ---------------------------------------------------------------------
# Where to write the output. The Rust outer .exe sets REVIT_EXPORT_DIR
# in the environment before launching RBP. Falls back to a sane default
# so this script is debuggable standalone.
# ---------------------------------------------------------------------
EXPORT_DIR = os.environ.get("REVIT_EXPORT_DIR", r"Z:\output")
if not os.path.isdir(EXPORT_DIR):
    os.makedirs(EXPORT_DIR)


# ---------------------------------------------------------------------
# IFC export options. Default config exports the whole model (all
# elements visible in the chosen view filter). Start simple — IFC2x3
# is the broadest-compatibility spec; switch to IFC4 once a customer
# asks for it.
# ---------------------------------------------------------------------
def make_ifc_options():
    opts = DB.IFCExportOptions()
    opts.FileVersion = DB.IFCVersion.IFC2x3
    opts.WallAndColumnSplitting = True
    opts.ExportBaseQuantities = True
    opts.SpaceBoundaryLevel = 0  # no space boundaries (set 1 or 2 if needed)
    return opts


# ---------------------------------------------------------------------
# Main: export the open model to IFC.
# ---------------------------------------------------------------------
def export_to_ifc():
    base = os.path.splitext(os.path.basename(REVIT_FILE_PATH))[0] or "model"
    out_name = base + ".ifc"

    output("export-ifc: source={}".format(REVIT_FILE_PATH))
    output("export-ifc: target={}\\{}".format(EXPORT_DIR, out_name))

    opts = make_ifc_options()

    # Revit's Export() returns nothing on success; raises on failure.
    # The .ifc file lands at EXPORT_DIR\<base>.ifc.
    tx = DB.Transaction(DOC, "export-ifc")
    try:
        tx.Start()
        DOC.Export(EXPORT_DIR, out_name, opts)
        tx.Commit()
        output("export-ifc: success")
        return True
    except Exception as e:
        tx.RollBack()
        output("export-ifc: FAILED — {}".format(e))
        return False


# ---------------------------------------------------------------------
# Dialog suppression — RBP has its own built-in suppressor that handles
# most cases. Add overrides here only for dialogs RBP misses. See
# REVIT.md → "Popups, modals, …" for the full list of expected ones.
#
# Pattern (commented out — uncomment when you hit a real un-suppressed
# dialog):
#
# def on_dialog_box_showing(sender, args):
#     # log every dialog so we can grow the suppression list iteratively
#     output("dialog: id={} type={}".format(args.DialogId, type(args).__name__))
#     # auto-dismiss known-safe ones
#     if args.DialogId == "TaskDialog_Missing_Third_Party_Updaters":
#         args.OverrideResult(1)  # 1 = "Yes / OK / dismiss"
#
# if not DEBUG:
#     uiapp = revit_script_util.GetUIApplication()
#     uiapp.DialogBoxShowing += on_dialog_box_showing
# ---------------------------------------------------------------------


# Entry point — RBP runs this file top-to-bottom per opened model.
if __name__ == "__main__" or True:  # RBP doesn't set __name__
    ok = export_to_ifc()
    if not DEBUG and not ok:
        # signal failure to RBP — non-zero exit isn't possible from a
        # script_util script, so we throw to make sure RBP logs it
        raise Exception("export-ifc failed; see preceding output for details")
