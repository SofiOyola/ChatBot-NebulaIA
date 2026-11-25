from __future__ import annotations

import os
import secrets
import subprocess
import time
import uuid
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = [
    ROOT / "supabase/migrations/20261124060000_rag_academic_documents.sql",
    ROOT / "supabase/migrations/20261124070000_rag_document_lifecycle.sql",
    ROOT / "supabase/migrations/20261124080000_rag_classification_hybrid_search.sql",
    ROOT / "supabase/migrations/20261124090000_rag_api_role.sql",
    ROOT / "supabase/migrations/20261124100000_rag_ingestion_roles.sql",
    ROOT / "supabase/migrations/20261124110000_rag_demo_content_guard.sql",
]
READINESS = ROOT / "supabase/migrations/20261124120000_rag_profile_readiness.sql"
PREFLIGHT = ROOT / "scripts/rag/preflight_rag_profile_readiness.sql"
VERIFY = ROOT / "scripts/rag/verify_rag_profile_readiness.sql"
DEPLOYMENT_VERIFY = ROOT / "scripts/rag/verify_rag_deployment.sql"
PROFILE_CREATE = ROOT / "scripts/rag/create_rag_embedding_profile.sql"
IMAGE = os.getenv("NEBULA_RAG_POSTGRES17_IMAGE", "pgvector/pgvector:0.8.2-pg17")


def _run(*args: str, input_text: str | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(list(args), input=input_text, text=True, encoding="utf-8",
                          capture_output=True, check=check)


@pytest.mark.docker
@pytest.mark.skipif(
    os.getenv("NEBULA_RAG_READINESS_DOCKER_TEST") != "1",
    reason="NEBULA_RAG_READINESS_DOCKER_TEST no es 1; no se inicia Docker",
)
def test_profile_readiness_on_disposable_postgres17_pgvector082():
    container = f"nebula-rag-readiness-it-{uuid.uuid4().hex[:12]}"
    password = secrets.token_urlsafe(24)

    def sql(statement: str, *, user: str = "postgres", check: bool = True):
        return _run("docker", "exec", "-i", container, "psql", "-X", "-v", "ON_ERROR_STOP=1",
                    "-U", user, "-d", "readiness_test", input_text=statement, check=check)

    vector = "[1," + ",".join("0" for _ in range(767)) + "]"
    try:
        _run("docker", "run", "--detach", "--rm", "--name", container,
             "--label", "com.nebula.test=rag-profile-readiness",
             "--env", f"POSTGRES_PASSWORD={password}", "--env", "POSTGRES_DB=readiness_test", IMAGE)
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if sql("SELECT 1;", check=False).returncode == 0:
                break
            time.sleep(1)
        else:
            pytest.fail("disposable PostgreSQL 17 did not become ready")

        sql("CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; CREATE ROLE service_role NOLOGIN; "
            "CREATE SCHEMA extensions; CREATE EXTENSION vector WITH SCHEMA extensions;")
        version = sql("SELECT current_setting('server_version'),e.extversion,n.nspname FROM pg_extension e "
                      "JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname='vector';")
        assert "17." in version.stdout and "0.8.2" in version.stdout and "extensions" in version.stdout

        for migration in MIGRATIONS:
            assert sql(migration.read_text(encoding="utf-8")).returncode == 0
        sql("CREATE ROLE nebula_rag_api_login LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE "
            "NOREPLICATION NOBYPASSRLS; GRANT nebula_rag_api TO nebula_rag_api_login;")
        assert sql(PROFILE_CREATE.read_text(encoding="utf-8")).returncode == 0

        preflight = sql(PREFLIGHT.read_text(encoding="utf-8"))
        assert "RAG_PROFILE_READINESS_PREFLIGHT_READY" in preflight.stdout
        assert sql(READINESS.read_text(encoding="utf-8")).returncode == 0

        inactive = sql("SELECT ready,profile_id,dimension FROM "
                       "public.nebula_get_rag_profile_readiness('gemini-embedding-001-768');",
                       user="nebula_rag_api_login")
        assert "f" in inactive.stdout and "gemini-embedding-001-768" in inactive.stdout and "768" in inactive.stdout

        sql("UPDATE rag.embedding_profiles SET status='active' "
            "WHERE profile_id='gemini-embedding-001-768';")
        active = sql("SELECT ready,dimension FROM public.nebula_get_rag_profile_readiness(" 
                     "'gemini-embedding-001-768');", user="nebula_rag_api_login")
        assert "t" in active.stdout and "768" in active.stdout
        original_search = sql("SELECT count(*) FROM public.nebula_search_academic_chunks_hybrid(" 
                              f"'probe','{vector}'::extensions.vector,'gemini-embedding-001-768',"
                              "'old_9s_151c',1,0);", user="nebula_rag_api_login")
        assert "0" in original_search.stdout

        sql("UPDATE rag.embedding_profiles SET provider='incompatible' "
            "WHERE profile_id='gemini-embedding-001-768';")
        incompatible = sql("SELECT ready IS FALSE,dimension FROM public.nebula_get_rag_profile_readiness(" 
                           "'gemini-embedding-001-768');", user="nebula_rag_api_login")
        assert "t" in incompatible.stdout and "768" in incompatible.stdout
        sql("UPDATE rag.embedding_profiles SET provider='google',status='inactive' "
            "WHERE profile_id='gemini-embedding-001-768';")

        sql("DELETE FROM rag.embedding_profiles WHERE profile_id='gemini-embedding-001-768';")
        absent = sql("SELECT ready IS FALSE,profile_id,dimension IS NULL FROM "
                     "public.nebula_get_rag_profile_readiness('gemini-embedding-001-768');",
                     user="nebula_rag_api_login")
        assert absent.stdout.count("t") >= 2 and "gemini-embedding-001-768" in absent.stdout
        sql("INSERT INTO rag.embedding_profiles(profile_id,provider,model,dimension,distance_metric,normalization,status) "
            "VALUES ('gemini-embedding-001-768','google','gemini-embedding-001',768,'cosine','unit_length','inactive');")

        unauthorized_id = sql("\\set VERBOSITY verbose\n"
                              "SELECT * FROM public.nebula_get_rag_profile_readiness('other-profile');",
                              user="nebula_rag_api_login", check=False)
        assert unauthorized_id.returncode != 0 and "22023" in unauthorized_id.stderr
        never_null = sql("SELECT ready IS NOT NULL FROM public.nebula_get_rag_profile_readiness(" 
                         "'gemini-embedding-001-768');", user="nebula_rag_api_login")
        assert "t" in never_null.stdout

        direct_select = sql("SELECT * FROM rag.embedding_profiles;", user="nebula_rag_api_login", check=False)
        assert direct_select.returncode != 0 and "permission denied" in direct_select.stderr.lower()
        for role in ("anon", "authenticated", "service_role", "nebula_rag_ingest", "nebula_rag_reviewer"):
            denied = sql(f"SET ROLE {role}; SELECT * FROM "
                         "public.nebula_get_rag_profile_readiness('gemini-embedding-001-768');", check=False)
            assert denied.returncode != 0 and "permission denied" in denied.stderr.lower()

        verified = sql(VERIFY.read_text(encoding="utf-8"))
        assert "RAG_PROFILE_READINESS_VERIFIED" in verified.stdout
        existing_rpcs = sql(DEPLOYMENT_VERIFY.read_text(encoding="utf-8"))
        assert "RAG_DEPLOYMENT_SQL_VERIFIED" in existing_rpcs.stdout
        collision = sql(READINESS.read_text(encoding="utf-8"), check=False)
        assert collision.returncode != 0 and "already exists" in collision.stderr
        assert "RAG_PROFILE_READINESS_VERIFIED" in sql(VERIFY.read_text(encoding="utf-8")).stdout

        sql("GRANT EXECUTE ON FUNCTION public.nebula_get_rag_profile_readiness(text) TO anon;")
        corrupted = sql(VERIFY.read_text(encoding="utf-8"), check=False)
        assert corrupted.returncode != 0 and "EXECUTE ACL" in corrupted.stderr
        sql("REVOKE EXECUTE ON FUNCTION public.nebula_get_rag_profile_readiness(text) FROM anon;")
        assert "RAG_PROFILE_READINESS_VERIFIED" in sql(VERIFY.read_text(encoding="utf-8")).stdout
    finally:
        _run("docker", "rm", "--force", "--volumes", container, check=False)
