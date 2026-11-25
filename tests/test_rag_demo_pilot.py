from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import replace
from pathlib import Path

import pytest

from nebula_rag.cli import _source
from nebula_rag.local_demo import assert_demo_staging_authorized, load_local_demo


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config/rag-demo-pilot.json"
MIGRATION = (ROOT / "supabase/migrations/20261124110000_rag_demo_content_guard.sql").read_text(encoding="utf-8")
URL = "https://demo.nebula.invalid/rag/nebula-rag-demo.html"


def test_original_demo_metadata_is_explicit_and_non_institutional():
    source = _source(str(CONFIG), "nebula_original_demo")
    document = load_local_demo(source, project_root=ROOT, url=URL)
    assert document.source_type == "third_party"
    assert document.authority_level == "secondary"
    assert document.content_class == "demo_non_institutional"
    assert document.authorization_status == "pending"
    assert document.publisher == "Equipo del proyecto NébulaIA"
    assert document.metadata["demo_non_institutional"] is True
    assert document.metadata["authorization"]["status"] == "pending"
    assert "no es un reglamento" in document.content.lower()
    assert "no debe emplearse para responder preguntas normativas" in document.content.lower()
    assert "material de demostración" in document.content.lower()


def test_pending_demo_can_be_previewed_but_never_staged():
    source = _source(str(CONFIG), "nebula_original_demo")
    document = load_local_demo(source, project_root=ROOT, url=URL)
    with pytest.raises(PermissionError, match="not approved"):
        assert_demo_staging_authorized(document)
    approved = replace(document, authorization_status="approved",
                       metadata={**document.metadata, "authorization": {
                           "status": "approved", "authorized_by": "reviewer",
                           "date": "2026-11-25",
                           "permitted_uses": ["extract", "chunk", "embed", "store", "present"]}})
    assert_demo_staging_authorized(approved)


def test_offline_preview_uses_no_network_or_database_and_returns_safe_metadata():
    completed = subprocess.run(
        [sys.executable, "-m", "nebula_rag.cli", "preview", "--sources", str(CONFIG),
         "--source", "nebula_original_demo", "--url", URL],
        cwd=ROOT, text=True, encoding="utf-8", capture_output=True, check=True,
        env={**os.environ, "PYTHONIOENCODING": "utf-8"},
    )
    payload = json.loads(completed.stdout)
    assert payload["content_class"] == "demo_non_institutional"
    assert payload["authorization_status"] == "pending"
    assert payload["chunk_count"] == 1
    assert "content" not in payload


def test_cli_blocks_pending_demo_before_opening_a_database_connection():
    completed = subprocess.run(
        [sys.executable, "-m", "nebula_rag.cli", "stage", "--sources", str(CONFIG),
         "--source", "nebula_original_demo", "--url", URL],
        cwd=ROOT, text=True, encoding="utf-8", capture_output=True, check=False,
        env={key: value for key, value in {**os.environ, "PYTHONIOENCODING": "utf-8"}.items()
             if key != "RAG_DATABASE_URL"},
    )
    assert completed.returncode != 0
    assert "not approved for staging" in completed.stderr
    assert "RAG_DATABASE_URL is required" not in completed.stderr


def test_local_loader_rejects_path_escape_and_non_demo_classification():
    source = _source(str(CONFIG), "nebula_original_demo")
    with pytest.raises(PermissionError):
        load_local_demo(replace(source, local_file="README.md"), project_root=ROOT, url=URL)
    with pytest.raises(PermissionError):
        load_local_demo(replace(source, authority_level="institutional_normative"), project_root=ROOT, url=URL)


def test_migration_is_compatible_and_excludes_demo_from_both_production_searches():
    lowered = " ".join(MIGRATION.lower().split())
    assert "add column if not exists content_class text not null default 'institutional'" in lowered
    assert "documents_demo_safety_check" in lowered
    assert lowered.count("d.content_class='institutional'") == 2
    assert "demo_non_institutional" in lowered
    assert "grant insert (content_class,authorization_status,authorization_reference,authorization_date)" in lowered
    for forbidden in ("student.", "auth.", "get_academic_history", "get_credit_progress"):
        assert forbidden not in lowered
