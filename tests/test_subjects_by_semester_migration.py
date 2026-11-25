from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "supabase/migrations/20261124015000_academic_catalog_base.sql"
SEED = ROOT / "supabase/migrations/20261124020000_academic_catalog_seed.sql"
MIGRATION = ROOT / "supabase/migrations/20261124050000_subjects_by_semester.sql"


def _split_sql_values(value_list: str) -> list[str]:
    values: list[str] = []
    start = 0
    depth = 0
    in_quote = False
    index = 0
    while index < len(value_list):
        char = value_list[index]
        if char == "'":
            if in_quote and index + 1 < len(value_list) and value_list[index + 1] == "'":
                index += 2
                continue
            in_quote = not in_quote
        elif not in_quote:
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            elif char == "," and depth == 0:
                values.append(value_list[start:index].strip())
                start = index + 1
        index += 1
    values.append(value_list[start:].strip())
    return values


def _position_rows() -> list[dict[str, int]]:
    rows = []
    pattern = re.compile(
        r"INSERT INTO academic\.curriculum_positions \((?P<columns>[^)]+)\) "
        r"VALUES \((?P<values>.+)\);$"
    )
    for line in SEED.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if not match:
            continue
        columns = [column.strip() for column in match.group("columns").split(",")]
        values = _split_sql_values(match.group("values"))
        record = dict(zip(columns, values, strict=True))
        rows.append({
            "semester": int(record["semester"]),
            "position_number": int(record["position_number"]),
            "credits": int(record["credits"]),
        })
    return rows


def test_workspace_schema_has_the_exact_columns_used_by_the_rpc():
    schema = BASE.read_text(encoding="utf-8")
    for required_fragment in (
        "CREATE TABLE curriculum_positions",
        "semester integer NOT NULL CHECK (semester BETWEEN 1 AND 9)",
        "credits integer NOT NULL CHECK (credits >= 0)",
        "CREATE TABLE courses",
        "code_evidence_id bigint",
        "evidence_kind text GENERATED ALWAYS AS ('official'::text) STORED",
        "evidence_status text GENERATED ALWAYS AS ('documented'::text) STORED",
        "CREATE TABLE requirement_coverage",
        "coverage text NOT NULL CHECK (coverage IN ('unknown', 'partial', 'complete', 'confirmed_absent'))",
        "CREATE TABLE course_requirements",
        "required_position_id text NOT NULL",
        "applicability text NOT NULL CHECK (applicability IN ('cohort_pending', 'applicable'))",
    ):
        assert required_fragment in schema


def test_seed_really_contains_51_unique_positions_and_151_credits():
    rows = _position_rows()
    assert len(rows) == 51
    assert sum(row["credits"] for row in rows) == 151
    assert {row["semester"] for row in rows} == set(range(1, 10))
    assert len({(row["semester"], row["position_number"]) for row in rows}) == 51


def test_rpc_uses_one_curriculum_position_as_each_result_row():
    sql = MIGRATION.read_text(encoding="utf-8")
    result_query = sql.split("RETURN QUERY", 1)[1]
    assert "FROM academic.curriculum_positions AS cp" in result_query
    assert "cp.credits" in result_query
    assert "SUM(cp.credits)" not in result_query
    assert "SELECT jsonb_agg(" in result_query
    assert "FROM academic.course_requirements AS relation" in result_query
    assert "ORDER BY cp.position_number" in result_query


def test_rpc_preserves_real_coverage_states_and_verified_codes_only():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "prerequisite_state.coverage AS prerequisite_coverage" in sql
    assert "corequisite_state.coverage AS corequisite_coverage" in sql
    assert "c.code_evidence_id IS NOT NULL" in sql
    assert "c.evidence_kind = 'official'" in sql
    assert "c.evidence_status = 'documented'" in sql
    assert "THEN c.institutional_code" in sql


def test_rpc_is_read_only_private_and_has_no_student_dependency():
    sql = MIGRATION.read_text(encoding="utf-8")
    lowered = sql.lower()
    assert "security definer" in lowered
    assert "set search_path = ''" in lowered
    assert "language plpgsql" in lowered
    assert not re.search(r"\b(insert|update|delete|merge|truncate)\b", lowered)
    assert "student." not in lowered
    assert "auth.uid" not in lowered
    assert "revoke all on function public.nebula_get_subjects_by_semester(integer) from public" in lowered
    assert "grant execute on function public.nebula_get_subjects_by_semester(integer) to anon, authenticated" in lowered
    assert not re.search(r"grant\s+select\s+on", lowered)
    assert not re.search(r"grant\s+.+\s+on\s+(all\s+tables|academic\.)", lowered)


def test_anon_receives_only_function_execute_not_academic_schema_access():
    sql = MIGRATION.read_text(encoding="utf-8").lower()
    grants = [line.strip() for line in sql.splitlines() if line.strip().startswith("grant ")]
    assert grants == [
        "grant execute on function public.nebula_get_subjects_by_semester(integer) to anon, authenticated;"
    ]
    assert "grant usage on schema academic" not in sql
    assert "grant select" not in sql


def test_rpc_validates_semester_and_catalog_invariants():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "p_semester NOT BETWEEN 1 AND 9" in sql
    assert "cv.term_count = 9" in sql
    assert "cv.position_count = 51" in sql
    assert "cv.total_credits = 151" in sql
    assert "matching_curricula > 1" in sql
