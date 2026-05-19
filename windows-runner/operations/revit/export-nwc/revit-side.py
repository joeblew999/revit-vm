# -*- coding: utf-8 -*-
"""
revit-side.py — export the open Revit model to Navisworks Cache (.nwc).

Runs INSIDE Revit, called by Revit Batch Processor (RBP) per opened
model. Sibling to operations/revit/export-ifc/. Same shape, different
export options.

References:
- jchristel's ModifyExportNWC_IFC.py — original pattern
- Revit API: NavisworksExportOptions, Document.Export
"""

import clr
import os
import sys  # noqa: F401  (kept for parity with sibling scripts)

DEBUG = False

if not DEBUG:
    import revit_script_util
    clr.AddReference("RevitAPI")
    clr.AddReference("RevitAPIUI")
    DOC = revit_script_util.GetScriptDocument()
    REVIT_FILE_PATH = revit_script_util.GetRevitFilePath()
else:
    DOC = doc  # noqa: F821
    REVIT_FILE_PATH = DOC.PathName

import Autodesk.Revit.DB as DB


def output(msg):
    if not DEBUG:
        revit_script_util.Output(str(msg))
    else:
        print(msg)


EXPORT_DIR = os.environ.get("REVIT_EXPORT_DIR", r"Z:\output")
if not os.path.isdir(EXPORT_DIR):
    os.makedirs(EXPORT_DIR)


def make_nwc_options():
    """Default NWC export options. Tune in operation iteration."""
    opts = DB.NavisworksExportOptions()
    # Whole model, not selection. Other options:
    #   NavisworksExportScope.View         — current view only
    #   NavisworksExportScope.SelectedItems — pre-selected elements
    opts.ExportScope = DB.NavisworksExportScope.Model
    opts.Coordinates = DB.NavisworksCoordinates.Shared  # vs .Internal
    opts.ConvertElementProperties = True
    opts.ExportLinks = False  # set True if you want linked models inline
    opts.ExportRoomGeometry = False
    opts.ExportRoomAsAttribute = True
    return opts


def export_to_nwc():
    base = os.path.splitext(os.path.basename(REVIT_FILE_PATH))[0] or "model"
    out_name = base + ".nwc"

    output("export-nwc: source={}".format(REVIT_FILE_PATH))
    output("export-nwc: target={}\\{}".format(EXPORT_DIR, out_name))

    opts = make_nwc_options()

    tx = DB.Transaction(DOC, "export-nwc")
    try:
        tx.Start()
        DOC.Export(EXPORT_DIR, out_name, opts)
        tx.Commit()
        output("export-nwc: success")
        return True
    except Exception as e:
        tx.RollBack()
        output("export-nwc: FAILED — {}".format(e))
        return False


if __name__ == "__main__" or True:
    ok = export_to_nwc()
    if not DEBUG and not ok:
        raise Exception("export-nwc failed; see preceding output for details")
