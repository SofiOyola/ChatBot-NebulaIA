from pathlib import Path


SQL = (Path(__file__).resolve().parents[1] / "supabase/migrations/20261124070000_rag_document_lifecycle.sql").read_text(encoding="utf-8")


def test_lifecycle_quarantines_unreviewed_revisions_and_preserves_security():
    assert "is_current boolean NOT NULL DEFAULT false" in SQL
    assert "CHECK (NOT is_current OR validation_status = 'documented')" in SQL
    assert "documents_one_current_source_idx" in SQL
    assert "d.validation_status = 'documented' AND d.is_current" in SQL
    assert "SECURITY DEFINER SET search_path = ''" in SQL
    assert "FROM PUBLIC, anon, authenticated" in SQL
    assert "GRANT EXECUTE" not in SQL
    assert "GRANT SELECT" not in SQL.upper()


def test_lifecycle_migration_is_replayable_and_does_not_touch_private_students():
    assert SQL.count("ADD COLUMN IF NOT EXISTS") == 3
    assert "CREATE UNIQUE INDEX IF NOT EXISTS" in SQL
    assert "CREATE OR REPLACE FUNCTION" in SQL
    assert "student." not in SQL.lower()
    assert "auth.uid" not in SQL.lower()
