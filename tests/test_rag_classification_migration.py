import json
from pathlib import Path


SQL = (Path(__file__).resolve().parents[1] / "supabase/migrations/20261124080000_rag_classification_hybrid_search.sql").read_text(encoding="utf-8")
SOURCE_CONFIG = Path(__file__).resolve().parents[1] / "config/rag-sources.example.json"


def test_classification_and_old_curriculum_guard_are_enforced_in_sql():
    for value in ("old_9s_151c", "new_2027_8s_134c", "general", "unknown"):
        assert value in SQL
    assert "p_curriculum_scope NOT IN ('old_9s_151c','general')" in SQL
    assert "d.curriculum_scope IN ('general','old_9s_151c')" in SQL
    assert "d.validity_status='current'" in SQL
    assert "d.validation_status='documented'" in SQL
    assert "d.is_current" in SQL


def test_hybrid_search_is_qualified_private_and_bounded():
    assert "websearch_to_tsquery('pg_catalog.spanish'::regconfig" in SQL
    assert "USING gin (search_vector)" in SQL
    assert "OPERATOR(extensions.<=>)" in SQL
    assert "p_match_count NOT BETWEEN 1 AND 20" in SQL
    assert "SECURITY DEFINER SET search_path=''" in SQL
    assert "REVOKE ALL ON FUNCTION public.nebula_search_academic_chunks_hybrid" in SQL
    assert SQL.count("FROM PUBLIC, anon, authenticated") == 2
    assert "GRANT EXECUTE" not in SQL
    assert "student." not in SQL.lower()


def test_authority_priority_is_bounded_and_new_plan_is_not_publicly_selectable():
    assert "institutional_normative' THEN 0.05" in SQL
    assert "institutional_informative' THEN 0.03" in SQL
    assert "external_academic' THEN 0.01" in SQL
    assert "0.75*s.semantic_similarity" in SQL
    assert "p_curriculum_scope NOT IN ('old_9s_151c','general')" in SQL


def test_candidate_sources_are_disabled_and_2027_sources_are_explicitly_scoped():
    payload = json.loads(SOURCE_CONFIG.read_text(encoding="utf-8"))
    assert payload["sources"]
    assert all(source["enabled"] is False for source in payload["sources"])
    new_plan = [source for source in payload["sources"] if "2027" in source["name"]]
    assert len(new_plan) == 2
    assert all(source["curriculum_scope"] == "new_2027_8s_134c" for source in new_plan)
    assert payload["excluded_sources"][0]["name"] == "unab_intranet"
