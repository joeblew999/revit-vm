# -*- coding: utf-8 -*-
"""
revit-side.py — export every sheet in the open Revit model to a single
combined PDF.

Runs INSIDE Revit, called by Revit Batch Processor (RBP) per opened
model. Uses Revit 2022+'s native PDFExportOptions API — no third-party
PDF printer needed.

References:
- Revit API: PDFExportOptions, ViewSheet, FilteredElementCollector,
  Document.Export(folder, view_ids, pdf_export_options)
- jchristel sample for export-by-view patterns:
  https://github.com/jchristel/SampleCodeRevitBatchProcessor

Limitation: targets Revit 2022+. Older Revit needs the
ViewSet/PrintManager dance via a virtual PDF printer driver.
"""

import clr
import os
import sys  # noqa: F401

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


def collect_sheet_ids():
    """All ViewSheet IDs in the document, excluding any sheet templates."""
    collector = DB.FilteredElementCollector(DOC).OfClass(DB.ViewSheet)
    ids = []
    for sheet in collector:
        # ViewSheet.IsTemplate filters out the sheet-template entries that
        # appear alongside real sheets in some models.
        if not sheet.IsTemplate:
            ids.append(sheet.Id)
    return ids


def make_pdf_options(out_basename):
    """Default PDF export options. One combined PDF of all sheets."""
    opts = DB.PDFExportOptions()
    opts.FileName = out_basename
    opts.Combine = True  # single .pdf with all sheets; False = one per
    opts.PaperFormat = DB.ExportPaperFormat.Default
    opts.PaperOrientation = DB.PageOrientationType.Auto
    opts.PaperPlacement = DB.PaperPlacementType.Center
    opts.HideCropBoundaries = True
    opts.HideScopeBoxes = True
    opts.HideReferencePlane = True
    opts.HideUnreferencedViewTags = True
    return opts


def export_sheets_to_pdf():
    base = os.path.splitext(os.path.basename(REVIT_FILE_PATH))[0] or "model"
    out_name = base  # .pdf is appended by Revit

    sheet_ids = collect_sheet_ids()
    if not sheet_ids:
        output("export-pdf: no sheets in document — nothing to export")
        return True

    output("export-pdf: source={}".format(REVIT_FILE_PATH))
    output("export-pdf: sheets={}".format(len(sheet_ids)))
    output("export-pdf: target={}\\{}.pdf".format(EXPORT_DIR, out_name))

    opts = make_pdf_options(out_name)

    # PDF export is not transactional in the usual sense — Document.Export
    # for PDF doesn't need a Transaction wrapping. Use try/except anyway.
    try:
        # Use a .NET List<ElementId> if the API insists on it. Revit
        # generally accepts a Python list of ElementId here.
        DOC.Export(EXPORT_DIR, sheet_ids, opts)
        output("export-pdf: success")
        return True
    except Exception as e:
        output("export-pdf: FAILED — {}".format(e))
        return False


if __name__ == "__main__" or True:
    ok = export_sheets_to_pdf()
    if not DEBUG and not ok:
        raise Exception("export-pdf failed; see preceding output for details")
