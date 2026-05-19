# -*- coding: utf-8 -*-
"""
revit-side.py — read-only health report for the open Revit model.

Runs INSIDE Revit, called by Revit Batch Processor (RBP) per opened
model. **No modifications.** Writes a JSON report to the shared output
folder with element counts, warnings, link statuses, file metadata.

Useful as the cheapest first operation to verify the whole RBP pipeline
end-to-end: no Export() calls, no transactions, no risk to the model.

References:
- Revit API: FilteredElementCollector, Document.GetWarnings,
  Document.GetAllExternalFileReferences
"""

import clr
import json
import os
import sys  # noqa: F401

DEBUG = False

if not DEBUG:
    import revit_script_util
    clr.AddReference("RevitAPI")
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


def safe_count(collector_call):
    """Wrap a FilteredElementCollector chain in a try/except — some
    collector chains throw on certain document states (corrupt links,
    purgeable phases, etc.). Return -1 on failure so the count is
    visibly bogus rather than zero-which-could-be-real."""
    try:
        return collector_call().GetElementCount()
    except Exception as e:
        output("health-check: count failed — {}".format(e))
        return -1


def collect_report():
    """Build the health-report dict. Pure read-only — no Transactions."""
    report = {
        "file_path": REVIT_FILE_PATH,
        "file_name": os.path.basename(REVIT_FILE_PATH),
        "is_workshared": bool(getattr(DOC, "IsWorkshared", False)),
        "is_family_document": bool(getattr(DOC, "IsFamilyDocument", False)),
    }

    # Element counts by class — useful signals about model size.
    report["counts"] = {
        "wall": safe_count(lambda: DB.FilteredElementCollector(DOC).OfClass(DB.Wall)),
        "floor": safe_count(lambda: DB.FilteredElementCollector(DOC).OfClass(DB.Floor)),
        "room": safe_count(lambda: DB.FilteredElementCollector(DOC).OfClass(DB.SpatialElement)),
        "view": safe_count(lambda: DB.FilteredElementCollector(DOC).OfClass(DB.View)),
        "view_sheet": safe_count(lambda: DB.FilteredElementCollector(DOC).OfClass(DB.ViewSheet)),
        "view_family_type": safe_count(lambda: DB.FilteredElementCollector(DOC).OfClass(DB.ViewFamilyType)),
        "level": safe_count(lambda: DB.FilteredElementCollector(DOC).OfClass(DB.Level)),
        "grid": safe_count(lambda: DB.FilteredElementCollector(DOC).OfClass(DB.Grid)),
    }

    # Warnings — the GUI shows these in the "Review Warnings" dialog.
    # Headless models with hundreds of warnings often signal trouble.
    try:
        warnings = DOC.GetWarnings()
        report["warning_count"] = len(warnings)
    except Exception as e:
        output("health-check: warning fetch failed — {}".format(e))
        report["warning_count"] = -1

    # Linked files (Revit, CAD, IFC, PointCloud). Missing links surface
    # as ImportInstance with no path.
    try:
        refs = DOC.GetAllExternalFileReferences()
        report["external_file_reference_count"] = len(refs)
    except Exception as e:
        output("health-check: link fetch failed — {}".format(e))
        report["external_file_reference_count"] = -1

    return report


def write_report(report):
    base = os.path.splitext(os.path.basename(REVIT_FILE_PATH))[0] or "model"
    out_path = os.path.join(EXPORT_DIR, base + ".health.json")
    with open(out_path, "w") as f:
        json.dump(report, f, indent=2, sort_keys=True)
    output("health-check: report written to {}".format(out_path))


def run_health_check():
    output("health-check: source={}".format(REVIT_FILE_PATH))
    try:
        report = collect_report()
        write_report(report)
        output("health-check: success")
        return True
    except Exception as e:
        output("health-check: FAILED — {}".format(e))
        return False


if __name__ == "__main__" or True:
    ok = run_health_check()
    if not DEBUG and not ok:
        raise Exception("health-check failed; see preceding output for details")
