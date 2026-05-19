# -*- coding: utf-8 -*-
"""
Mock the Revit / IronPython runtime so operation scripts import + run
end-to-end on Mac. Used by tests/run.py.

Mocks return REAL types (strings, ints, lists, bools) where operation
scripts feed return values into stdlib functions that won't accept
MagicMock — `os.path.basename(path)`, `json.dump(report, ...)`, etc.
Without that, operations that touch the filesystem or serialise model
metadata fail in the test harness despite being correct against real
Revit.

Catches: typos, wrong attribute names, missing imports, wrong arg counts.
Doesn't catch: Revit API behaviour mistakes (mock absorbs the call).
"""

import builtins
import os
import sys
from unittest.mock import MagicMock


FAKE_RVT_PATH = "/tmp/fake-model.rvt"


def _make_fake_doc():
    """A Document mock that returns real types where operation scripts
    pipe values into stdlib calls (os.path, json, len, etc.)."""
    doc = MagicMock(name="Document")
    doc.PathName = FAKE_RVT_PATH
    doc.IsWorkshared = False
    doc.IsFamilyDocument = False
    doc.GetWarnings.return_value = []
    doc.GetAllExternalFileReferences.return_value = []
    doc.Export.return_value = None
    return doc


def _make_collector_chain():
    """FilteredElementCollector(doc).OfClass(cls).GetElementCount() returns 0.
    Also iterable so `for x in collector` doesn't explode."""
    chain = MagicMock(name="FilteredElementCollector")
    chain.OfClass.return_value = chain       # chained OfClass(...)
    chain.OfCategory.return_value = chain    # chained OfCategory(...)
    chain.WhereElementIsNotElementType.return_value = chain
    chain.WhereElementIsElementType.return_value = chain
    chain.ToElements.return_value = []
    chain.GetElementCount.return_value = 0
    chain.__iter__ = lambda self: iter([])
    return chain


def install():
    """Idempotent setup of Revit/IronPython module mocks. Call from any
    test entrypoint before importing/exec'ing an operation script."""

    # --- modules ---
    # Order matters for dotted imports: Python resolves `import a.b.c` by
    # walking `sys.modules['a'].b.c`, NOT by looking up `sys.modules['a.b.c']`
    # directly. So if `sys.modules['Autodesk']` is a plain MagicMock, its
    # auto-created `.Revit` child won't match the `sys.modules['Autodesk.Revit']`
    # MagicMock we registered. We have to wire each parent.child = registered
    # submodule explicitly after creating them.
    module_names = [
        "clr",
        "System",
        "System.Core",
        "Autodesk",
        "Autodesk.Revit",
        "Autodesk.Revit.DB",
        "Autodesk.Revit.UI",
        "revit_script_util",
        "revit_file_util",
    ]
    for name in module_names:
        if name not in sys.modules:
            sys.modules[name] = MagicMock(name=name)
    # Wire parent.child for every dotted submodule so `import a.b.c` resolves
    # to the registered mock and not an auto-created stranger.
    for name in module_names:
        if "." in name:
            parent_name, attr = name.rsplit(".", 1)
            setattr(sys.modules[parent_name], attr, sys.modules[name])

    # --- revit_script_util — RBP's bridge to the running script ---
    rsu = sys.modules["revit_script_util"]
    fake_doc = _make_fake_doc()
    rsu.GetScriptDocument.return_value = fake_doc
    rsu.GetRevitFilePath.return_value = FAKE_RVT_PATH
    rsu.Output.return_value = None  # rsu.Output(str) — no return needed

    # --- Autodesk.Revit.DB — the actual API surface ---
    DB = sys.modules["Autodesk.Revit.DB"]
    DB.FilteredElementCollector.return_value = _make_collector_chain()

    # --- the `doc` builtin Revit's macro env injects when DEBUG=True ---
    if not hasattr(builtins, "doc"):
        builtins.doc = fake_doc

    # --- output dir env var ---
    os.environ.setdefault("REVIT_EXPORT_DIR", "/tmp/revit-test-export")
    os.makedirs(os.environ["REVIT_EXPORT_DIR"], exist_ok=True)
