from __future__ import annotations

import os
import secrets
import socket
import subprocess
import time
import uuid
from datetime import date
from pathlib import Path

import pytest

from nebula_rag.models import ExtractedDocument, TextChunk
from nebula_rag.repository import PostgresRagRepository


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20261124060000_rag_academic_documents.sql"
ASSERTIONS = ROOT / "tests/rag01_postgres_assertions.sql"
LIFECYCLE_MIGRATION = ROOT / "supabase/migrations/20261124070000_rag_document_lifecycle.sql"
CLASSIFICATION_MIGRATION = ROOT / "supabase/migrations/20261124080000_rag_classification_hybrid_search.sql"
API_ROLE_MIGRATION = ROOT / "supabase/migrations/20261124090000_rag_api_role.sql"
INGESTION_MIGRATION = ROOT / "supabase/migrations/20261124100000_rag_ingestion_roles.sql"
DEMO_GUARD_MIGRATION = ROOT / "supabase/migrations/20261124110000_rag_demo_content_guard.sql"
DEMO_GUARD_PREFLIGHT = ROOT / "scripts/rag/preflight_rag_demo_guard.sql"
DEMO_GUARD_VERIFIER = ROOT / "scripts/rag/verify_rag_demo_guard.sql"
INGESTION_ASSERTIONS = ROOT / "tests/rag_ingestion_rls_assertions.sql"
INGESTION_VERIFIER = ROOT / "scripts/rag/verify_rag_ingestion_security.sql"
INGESTION_PREFLIGHT = ROOT / "scripts/rag/preflight_rag_ingestion.sql"
OPERATIONAL_LOGIN_PRECHECK = ROOT / "scripts/rag/precheck_rag_operational_login.sql"
INGEST_LOGIN_VERIFIER = ROOT / "scripts/rag/verify_rag_ingest_login.sql"
REVIEWER_LOGIN_VERIFIER = ROOT / "scripts/rag/verify_rag_reviewer_login.sql"
PROFILE_PRECHECK = ROOT / "scripts/rag/precheck_rag_embedding_profile.sql"
PROFILE_CREATE = ROOT / "scripts/rag/create_rag_embedding_profile.sql"
PROFILE_VERIFY = ROOT / "scripts/rag/verify_rag_embedding_profile.sql"
DEPLOYMENT_VERIFIER = ROOT / "scripts/rag/verify_rag_deployment.sql"
LOGIN_PRECHECK = ROOT / "scripts/rag/precheck_rag_api_login.sql"
LOGIN_VERIFIER = ROOT / "scripts/rag/verify_rag_api_login.sql"
IMAGE = os.getenv("NEBULA_RAG_POSTGRES_IMAGE", "pgvector/pgvector:0.8.2-pg15")


def _run(*args: str, input_text: str | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(args),
        input=input_text,
        text=True,
        encoding="utf-8",
        capture_output=True,
        check=check,
    )


def _free_local_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


@pytest.mark.skipif(
    os.getenv("NEBULA_RAG_DOCKER_TEST") != "1",
    reason="NEBULA_RAG_DOCKER_TEST no es 1; no se inicia Docker automaticamente",
)
def test_rag01_on_disposable_postgres_with_pgvector_082():
    suffix = uuid.uuid4().hex[:12]
    container = f"nebula-rag01-it-{suffix}"
    password = secrets.token_urlsafe(24)
    port = _free_local_port()

    def docker_exec_sql(sql: str, *, check: bool = True) -> subprocess.CompletedProcess[str]:
        return _run(
            "docker", "exec", "-i", container,
            "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "rag01_test",
            input_text=sql,
            check=check,
        )

    try:
        _run(
            "docker", "run", "--detach", "--rm",
            "--name", container,
            "--label", "com.nebula.test=rag01-postgres-integration",
            "--publish", f"127.0.0.1:{port}:5432",
            "--env", f"POSTGRES_PASSWORD={password}",
            "--env", "POSTGRES_DB=rag01_test",
            IMAGE,
        )

        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            ready = _run(
                "docker", "exec", container,
                "psql", "-X", "-U", "postgres", "-d", "rag01_test", "-c", "SELECT 1",
                check=False,
            )
            if ready.returncode == 0:
                break
            time.sleep(1)
        else:
            pytest.fail("the disposable PostgreSQL container did not become ready")

        prerequisites = docker_exec_sql(
            "CREATE ROLE anon NOLOGIN;\n"
            "CREATE ROLE authenticated NOLOGIN;\n"
            "CREATE ROLE service_role NOLOGIN;\n"
            "CREATE SCHEMA extensions;\n"
            "CREATE EXTENSION vector WITH SCHEMA extensions;\n"
            "GRANT USAGE ON SCHEMA extensions TO anon, authenticated;\n"
        )
        assert prerequisites.returncode == 0

        version = docker_exec_sql(
            "SELECT e.extversion || '|' || n.nspname "
            "FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace "
            "WHERE e.extname='vector';"
        )
        assert "0.8.2|extensions" in version.stdout

        migration_sql = MIGRATION.read_text(encoding="utf-8")
        first_apply = docker_exec_sql(migration_sql)
        assert first_apply.returncode == 0

        assertions = docker_exec_sql(ASSERTIONS.read_text(encoding="utf-8"))
        assert "RAG01_POSTGRES_ASSERTIONS_PASS" in assertions.stdout

        for role in ("anon", "authenticated"):
            denied = docker_exec_sql(
                f"SET ROLE {role}; SELECT count(*) FROM rag.documents;",
                check=False,
            )
            assert denied.returncode != 0
            assert "permission denied" in denied.stderr.lower()

            rpc_denied = docker_exec_sql(
                f"SET ROLE {role}; SELECT count(*) FROM "
                "public.nebula_search_academic_chunks("
                "'[1,0,0]'::extensions.vector, 'synthetic-3d', 5, 0);",
                check=False,
            )
            assert rpc_denied.returncode != 0
            assert "permission denied" in rpc_denied.stderr.lower()

        second_apply = docker_exec_sql(migration_sql)
        assert second_apply.returncode == 0

        post_reapply = docker_exec_sql(
            "SELECT count(*) FROM public.nebula_search_academic_chunks("
            "'[1,0,0]'::extensions.vector, 'synthetic-3d', 5, 0);"
        )
        assert "1" in post_reapply.stdout

        lifecycle_sql = LIFECYCLE_MIGRATION.read_text(encoding="utf-8")
        assert docker_exec_sql(lifecycle_sql).returncode == 0
        assert docker_exec_sql(lifecycle_sql).returncode == 0
        classification_sql = CLASSIFICATION_MIGRATION.read_text(encoding="utf-8")
        assert docker_exec_sql(classification_sql).returncode == 0
        assert docker_exec_sql(classification_sql).returncode == 0
        api_role_sql = API_ROLE_MIGRATION.read_text(encoding="utf-8")
        assert docker_exec_sql(api_role_sql).returncode == 0
        assert docker_exec_sql(api_role_sql).returncode == 0
        vector_type_regression = docker_exec_sql(
            "BEGIN READ ONLY; SET LOCAL search_path=extensions,public; "
            "SELECT pg_catalog.format_type(a.atttypid,a.atttypmod), "
            "a.atttypid=pg_catalog.to_regtype('extensions.vector') "
            "FROM pg_catalog.pg_attribute a "
            "WHERE a.attrelid='rag.chunk_embeddings'::pg_catalog.regclass "
            "AND a.attname='embedding' AND NOT a.attisdropped; ROLLBACK;"
        )
        assert "vector" in vector_type_regression.stdout
        assert "t" in vector_type_regression.stdout
        ingestion_preflight = docker_exec_sql(INGESTION_PREFLIGHT.read_text(encoding="utf-8"))
        assert "RAG_INGESTION_PREFLIGHT_PENDING_EXISTING_DOCUMENTS" in ingestion_preflight.stdout
        role_checks = docker_exec_sql(
            "SELECT rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls "
            "FROM pg_roles WHERE rolname='nebula_rag_api';"
        )
        assert "f" in role_checks.stdout
        denied = docker_exec_sql("SET ROLE nebula_rag_api; SELECT count(*) FROM rag.documents;", check=False)
        assert denied.returncode != 0 and "permission denied" in denied.stderr.lower()
        allowed = docker_exec_sql(
            "SET ROLE nebula_rag_api; SELECT count(*) FROM public.nebula_search_academic_chunks("
            "'[1,0,0]'::extensions.vector,'synthetic-3d',1,0);"
        )
        assert "1" in allowed.stdout
        verified = docker_exec_sql(DEPLOYMENT_VERIFIER.read_text(encoding="utf-8"))
        assert "RAG_DEPLOYMENT_SQL_VERIFIED" in verified.stdout
        prechecked = docker_exec_sql(LOGIN_PRECHECK.read_text(encoding="utf-8"))
        assert "RAG_LOGIN_NAME_AVAILABLE_AND_PERMISSION_ROLE_SAFE" in prechecked.stdout
        docker_exec_sql(
            "CREATE SCHEMA student; CREATE TABLE student.profiles(id bigint); "
            "REVOKE ALL ON SCHEMA student FROM PUBLIC; "
            "REVOKE ALL ON student.profiles FROM PUBLIC; "
            "CREATE ROLE nebula_rag_api_login LOGIN INHERIT NOSUPERUSER NOCREATEDB "
            "NOCREATEROLE NOREPLICATION NOBYPASSRLS; "
            "GRANT nebula_rag_api TO nebula_rag_api_login;"
        )
        login_verified = _run(
            "docker", "exec", "-i", container, "psql", "-X", "-v", "ON_ERROR_STOP=1",
            "-U", "nebula_rag_api_login", "-d", "rag01_test",
            input_text=LOGIN_VERIFIER.read_text(encoding="utf-8"),
        )
        assert "RAG_LIMITED_LOGIN_VERIFIED" in login_verified.stdout
        ingestion_sql = INGESTION_MIGRATION.read_text(encoding="utf-8")
        assert docker_exec_sql(ingestion_sql).returncode == 0
        assert docker_exec_sql(ingestion_sql).returncode == 0
        collision_preflight = docker_exec_sql(
            INGESTION_PREFLIGHT.read_text(encoding="utf-8"), check=False
        )
        assert collision_preflight.returncode != 0
        assert "ingestion role name collision detected" in collision_preflight.stderr
        ingestion_assertions = docker_exec_sql(INGESTION_ASSERTIONS.read_text(encoding="utf-8"))
        assert "RAG_INGESTION_RLS_ASSERTIONS_PASS" in ingestion_assertions.stdout
        ingestion_verified = docker_exec_sql(INGESTION_VERIFIER.read_text(encoding="utf-8"))
        assert "RAG_INGESTION_SECURITY_VERIFIED" in ingestion_verified.stdout
        demo_preflight = docker_exec_sql(DEMO_GUARD_PREFLIGHT.read_text(encoding="utf-8"))
        assert "RAG_DEMO_GUARD_PREFLIGHT_PENDING_EXISTING_DOCUMENTS" in demo_preflight.stdout
        demo_guard_sql = DEMO_GUARD_MIGRATION.read_text(encoding="utf-8")
        assert docker_exec_sql(demo_guard_sql).returncode == 0
        assert docker_exec_sql(demo_guard_sql).returncode == 0
        demo_guard_verified = docker_exec_sql(DEMO_GUARD_VERIFIER.read_text(encoding="utf-8"))
        assert "RAG_DEMO_GUARD_VERIFIED" in demo_guard_verified.stdout
        demo_collision = docker_exec_sql(DEMO_GUARD_PREFLIGHT.read_text(encoding="utf-8"),check=False)
        assert demo_collision.returncode != 0
        assert "column or constraint collision" in demo_collision.stderr
        for login_name, permission_role in (
            ("nebula_rag_ingest_login", "nebula_rag_ingest"),
            ("nebula_rag_reviewer_login", "nebula_rag_reviewer"),
        ):
            precheck = _run(
                "docker", "exec", "-i", container, "psql", "-X", "-v", "ON_ERROR_STOP=1",
                "-v", f"login_name={login_name}", "-v", f"permission_role={permission_role}",
                "-U", "postgres", "-d", "rag01_test",
                input_text=OPERATIONAL_LOGIN_PRECHECK.read_text(encoding="utf-8"),
            )
            assert "RAG_OPERATIONAL_LOGIN_PREFLIGHT_READY" in precheck.stdout
        docker_exec_sql(
            "CREATE ROLE nebula_rag_ingest_login LOGIN INHERIT NOSUPERUSER NOCREATEDB "
            "NOCREATEROLE NOREPLICATION NOBYPASSRLS; "
            "GRANT nebula_rag_ingest TO nebula_rag_ingest_login; "
            "CREATE ROLE nebula_rag_reviewer_login LOGIN INHERIT NOSUPERUSER NOCREATEDB "
            "NOCREATEROLE NOREPLICATION NOBYPASSRLS; "
            "GRANT nebula_rag_reviewer TO nebula_rag_reviewer_login;"
        )
        ingest_login_verified = _run(
            "docker", "exec", "-i", container, "psql", "-X", "-v", "ON_ERROR_STOP=1",
            "-U", "nebula_rag_ingest_login", "-d", "rag01_test",
            input_text=INGEST_LOGIN_VERIFIER.read_text(encoding="utf-8"),
        )
        assert "RAG_INGEST_LOGIN_VERIFIED" in ingest_login_verified.stdout
        reviewer_login_verified = _run(
            "docker", "exec", "-i", container, "psql", "-X", "-v", "ON_ERROR_STOP=1",
            "-U", "nebula_rag_reviewer_login", "-d", "rag01_test",
            input_text=REVIEWER_LOGIN_VERIFIER.read_text(encoding="utf-8"),
        )
        assert "RAG_REVIEWER_LOGIN_VERIFIED" in reviewer_login_verified.stdout
        profile_precheck = docker_exec_sql(PROFILE_PRECHECK.read_text(encoding="utf-8"))
        assert "RAG_EMBEDDING_PROFILE_PREFLIGHT_READY" in profile_precheck.stdout
        assert docker_exec_sql(PROFILE_CREATE.read_text(encoding="utf-8")).returncode == 0
        profile_verified = docker_exec_sql(PROFILE_VERIFY.read_text(encoding="utf-8"))
        assert "RAG_EMBEDDING_PROFILE_VERIFIED" in profile_verified.stdout
        duplicate_profile = docker_exec_sql(PROFILE_CREATE.read_text(encoding="utf-8"),check=False)
        assert duplicate_profile.returncode != 0
        assert "already exists" in duplicate_profile.stderr
        docker_exec_sql("UPDATE rag.documents SET is_current=true,validity_status='current',curriculum_scope='old_9s_151c' WHERE validation_status='documented';")

        import psycopg
        with psycopg.connect(host="127.0.0.1", port=port, dbname="rag01_test",
                             user="postgres", password=password) as connection:
            repository = PostgresRagRepository(connection)
            changed = ExtractedDocument(
                "Synthetic documented revision 2", "https://example.invalid/documented", "official",
                date(2026, 11, 25), "changed synthetic content", "fixture", "e" * 64,
                curriculum_scope="old_9s_151c", program_key="systems-unab",
            )
            changed_chunk = TextChunk(0, "fixture:revision-2", "changed synthetic content", "f" * 64)
            document_id, created = repository.stage_document(changed, [changed_chunk])
            assert created
            duplicate_id, duplicate_created = repository.stage_document(changed, [changed_chunk])
            assert duplicate_id == document_id and not duplicate_created
            before_approval = repository.search([1.0, 0.0, 0.0], "synthetic-3d", 5, 0)
            assert len(before_approval) == 1 and before_approval[0].title == "Synthetic documented"

            with connection.cursor() as cursor:
                cursor.execute("SELECT chunk_id FROM rag.document_chunks WHERE document_id=%s", (document_id,))
                chunk_id = int(cursor.fetchone()[0])
            repository.store_embedding(chunk_id, "synthetic-3d", [1.0, 0.0, 0.0])
            repository.store_embedding(chunk_id, "synthetic-3d", [1.0, 0.0, 0.0])
            repository.approve_document(document_id, "synthetic-3d")
            results = repository.search([1.0, 0.0, 0.0], "synthetic-3d", 5, 0)
            assert len(results) == 1 and results[0].title == "Synthetic documented revision 2"

            demo = ExtractedDocument(
                "Original demo", "https://demo.nebula.invalid/rag/demo", "third_party",
                date(2026, 11, 25), "demonstration only content", "fixture", "9" * 64,
                metadata={"demo_non_institutional": True,
                          "authorization": {"status": "approved"}},
                information_type="general", authority_level="secondary",
                validity_status="pending_review", curriculum_scope="general",
                publisher="Equipo NébulaIA", content_class="demo_non_institutional",
                authorization_status="approved", authorization_reference="internal:test",
                authorization_date=date(2026, 11, 25),
            )
            demo_id, _ = repository.stage_document(
                demo, [TextChunk(0, "fixture:demo", "demonstration only content", "0" * 64)])
            with connection.cursor() as cursor:
                cursor.execute("SELECT chunk_id FROM rag.document_chunks WHERE document_id=%s", (demo_id,))
                demo_chunk_id = int(cursor.fetchone()[0])
            repository.store_embedding(demo_chunk_id, "synthetic-3d", [1.0, 0.0, 0.0])
            repository.approve_document(demo_id, "synthetic-3d")
            results_after_demo = repository.search([1.0, 0.0, 0.0], "synthetic-3d", 10, 0)
            assert all(item.title != "Original demo" for item in results_after_demo)

            new_plan = ExtractedDocument(
                "Synthetic 2027 plan", "https://example.invalid/new-plan", "official",
                date(2026, 11, 25), "eight semesters and 134 credits", "fixture", "1" * 64,
                information_type="academic_curriculum", curriculum_scope="new_2027_8s_134c",
                program_key="systems-unab",
            )
            new_chunk = TextChunk(0, "fixture:new-plan", "eight semesters and 134 credits", "2" * 64)
            new_id, _ = repository.stage_document(new_plan, [new_chunk])
            with connection.cursor() as cursor:
                cursor.execute("SELECT chunk_id FROM rag.document_chunks WHERE document_id=%s", (new_id,))
                new_chunk_id = int(cursor.fetchone()[0])
            repository.store_embedding(new_chunk_id, "synthetic-3d", [1.0, 0.0, 0.0])
            repository.approve_document(new_id, "synthetic-3d")
            old_scope_results = repository.search([1.0, 0.0, 0.0], "synthetic-3d", 5, 0,
                                                  query_text="credits", curriculum_scope="old_9s_151c")
            assert len(old_scope_results) == 1
            assert old_scope_results[0].title == "Synthetic documented revision 2"
            rejected = ExtractedDocument(
                "Rejected synthetic", "https://example.invalid/rejected", "official",
                date(2026, 11, 25), "rejected content", "fixture", "7" * 64,
            )
            rejected_id, _ = repository.stage_document(
                rejected, [TextChunk(0, "fixture:rejected", "rejected content", "8" * 64)])
            repository.reject_document(rejected_id)

            authority_fixtures = [
                ("Normative synthetic", "https://example.invalid/normative", "institutional_normative", "3" * 64, "5" * 64),
                ("Informative synthetic", "https://example.invalid/informative", "institutional_informative", "4" * 64, "6" * 64),
            ]
            for title, url, authority, document_hash, chunk_hash in authority_fixtures:
                fixture = ExtractedDocument(
                    title, url, "official", date(2026, 11, 25), "student regulation article",
                    "fixture", document_hash, information_type="institutional_policy",
                    authority_level=authority, curriculum_scope="general",
                )
                fixture_id, _ = repository.stage_document(
                    fixture, [TextChunk(0, f"fixture:{authority}", "student regulation article", chunk_hash)])
                with connection.cursor() as cursor:
                    cursor.execute("SELECT chunk_id FROM rag.document_chunks WHERE document_id=%s", (fixture_id,))
                    fixture_chunk_id = int(cursor.fetchone()[0])
                repository.store_embedding(fixture_chunk_id, "synthetic-3d", [1.0, 0.0, 0.0])
                repository.approve_document(fixture_id, "synthetic-3d")
            ranked = repository.search([1.0, 0.0, 0.0], "synthetic-3d", 5, 0,
                                       query_text="student regulation article", curriculum_scope="old_9s_151c")
            titles = [item.title for item in ranked]
            assert titles.index("Normative synthetic") < titles.index("Informative synthetic")
    finally:
        _run("docker", "rm", "--force", "--volumes", container, check=False)
