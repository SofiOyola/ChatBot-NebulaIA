from __future__ import annotations

import hashlib
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

import psycopg
import pytest

from nebula_rag.embeddings import DeterministicTestEmbedding
from nebula_rag.repository import PostgresRagRepository


ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = ROOT / "infrastructure/rag-local/.env.rag-local"
BASE_URL = "http://127.0.0.1:58091"


@dataclass
class HttpContext:
    tool_key: str = field(repr=False)
    admin_database_url: str = field(repr=False)
    api_database_url: str = field(repr=False)
    password: str = field(repr=False)
    api_password: str = field(repr=False)
    no_result_query: str


def _load_local_env() -> dict[str, str]:
    values = {}
    for raw in ENV_FILE.read_text(encoding="ascii").splitlines():
        if raw and not raw.startswith("#") and "=" in raw:
            key, value = raw.split("=", 1)
            values[key] = value
    return values


def _http(path: str, *, method: str = "POST", body: object | None = None,
          tool_key: str | None = None) -> tuple[int, object]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if tool_key is not None:
        headers["X-Nebula-Tool-Key"] = tool_key
    request = urllib.request.Request(BASE_URL + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        return exc.code, json.loads(raw) if raw else None


pytestmark = pytest.mark.skipif(
    os.getenv("NEBULA_RAG_HTTP_TEST") != "1",
    reason="NEBULA_RAG_HTTP_TEST no es 1; no se inicia el servidor HTTP local",
)


@pytest.fixture(scope="module")
def http_context():
    local = _load_local_env()
    password = local["RAG_LOCAL_DB_PASSWORD"]
    api_password = local["RAG_LOCAL_API_PASSWORD"]
    database_url = f"postgresql://postgres:{password}@127.0.0.1:55432/rag_local?connect_timeout=3"
    api_database_url = (f"postgresql://nebula_rag_api_login:{api_password}"
                        "@127.0.0.1:55432/rag_local?connect_timeout=3")
    provider = DeterministicTestEmbedding(dimension=3)
    test_urls: list[str] = []
    document_vectors: list[list[float]] = []
    with psycopg.connect(database_url, autocommit=True) as connection:
        repository = PostgresRagRepository(connection)
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT dc.chunk_id,d.title,dc.content
                FROM rag.document_chunks dc JOIN rag.documents d USING(document_id)
                ORDER BY dc.chunk_id
            """)
            base_chunks = cursor.fetchall()
        for chunk_id, title, content in base_chunks:
            vector = provider.embed_document(content, title=title)
            document_vectors.append(vector)
            repository.store_embedding(int(chunk_id), "local-synthetic-3d", vector)

        for index in range(7):
            url = f"https://http-test.invalid/context-{index}"
            test_urls.append(url)
            content = ((f"context fixture {index} alpha beta gamma delta epsilon. " * 100) + str(index))
            doc_hash = hashlib.sha256((url + content).encode()).hexdigest()
            chunk_hash = hashlib.sha256(content.encode()).hexdigest()
            with connection.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO rag.documents
                      (title,source_url,source_type,accessed_on,validation_status,scope,content_sha256,
                       is_current,reviewed_at,information_type,authority_level,validity_status,
                       curriculum_scope,program_key)
                    VALUES (%s,%s,'official',DATE '2026-11-25','documented','http-test',%s,
                            true,now(),'general','institutional_informative','current',
                            'old_9s_151c','systems-unab')
                    ON CONFLICT (source_url,content_sha256) DO UPDATE SET is_current=true
                    RETURNING document_id
                """, (f"HTTP context fixture {index}", url, doc_hash))
                document_id = int(cursor.fetchone()[0])
                cursor.execute("""
                    INSERT INTO rag.document_chunks(document_id,chunk_index,locator,content,content_sha256)
                    VALUES (%s,0,%s,%s,%s)
                    ON CONFLICT (document_id,chunk_index) DO UPDATE SET content=EXCLUDED.content
                    RETURNING chunk_id
                """, (document_id, f"http-test:context-{index}", content, chunk_hash))
                chunk_id = int(cursor.fetchone()[0])
            vector = provider.embed_document(content, title=f"HTTP context fixture {index}")
            document_vectors.append(vector)
            repository.store_embedding(chunk_id, "local-synthetic-3d", vector)

    candidates = ["zzzxxyy unique absence", "orthogonal missing evidence", "no matching local fixture"]
    no_result_query = next(
        candidate for candidate in candidates
        if max(sum(a * b for a, b in zip(provider.embed_query(candidate), vector))
               for vector in document_vectors) < 0.999999
    )
    tool_key = secrets.token_urlsafe(32)
    environment = os.environ.copy()
    environment.update({
        "RAG_DATABASE_URL": api_database_url,
        "NEBULA_RAG_TOOL_KEY": tool_key,
        "RAG_EMBEDDING_PROFILE_ID": "local-synthetic-3d",
        "RAG_EMBEDDING_PROVIDER": "deterministic-test-only",
        "RAG_EMBEDDING_DIMENSION": "3",
        "RAG_ALLOW_TEST_PROVIDER": "true",
        "RAG_HTTP_HOST": "127.0.0.1",
        "RAG_HTTP_PORT": "58091",
    })
    process = subprocess.Popen([sys.executable, "-m", "nebula_rag.server"], env=environment,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        try:
            if _http("/health", method="GET")[0] == 200:
                break
        except urllib.error.URLError:
            time.sleep(0.2)
    else:
        process.terminate()
        pytest.fail("local RAG HTTP server did not become ready")
    context = HttpContext(tool_key, database_url, api_database_url, password, api_password, no_result_query)
    try:
        yield context
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
        try:
            with psycopg.connect(database_url, autocommit=True) as connection:
                with connection.cursor() as cursor:
                    cursor.execute("DELETE FROM rag.documents WHERE source_url LIKE 'https://http-test.invalid/%'")
        except psycopg.Error:
            pass


def _search(context: HttpContext, **overrides):
    body = {"query": "curriculum credits", "limit": 5, "threshold": 0,
            "curriculum_scope": "old_9s_151c"}
    body.update(overrides)
    return _http("/v1/rag/search", body=body, tool_key=context.tool_key)


def test_unauthorized_requests_are_rejected_without_secret_leakage(http_context):
    for key in (None, "invalid-local-key"):
        status, payload = _http("/v1/rag/search", body={"query": "x"}, tool_key=key)
        assert status == 401 and payload == {"success": False, "error": "unauthorized"}
        serialized = json.dumps(payload)
        assert http_context.tool_key not in serialized
        assert http_context.password not in serialized and http_context.api_password not in serialized


def test_api_login_can_execute_search_but_cannot_read_or_mutate_private_tables(http_context):
    with psycopg.connect(http_context.api_database_url, autocommit=True) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT count(*) FROM public.nebula_search_academic_chunks("
                           "'[1,0,0]'::extensions.vector,'local-synthetic-3d',1,0)")
            assert cursor.fetchone()[0] >= 0
        for statement in (
            "SELECT count(*) FROM rag.documents",
            "INSERT INTO rag.documents(title) VALUES ('forbidden')",
            "UPDATE rag.documents SET title='forbidden'",
            "DELETE FROM rag.documents",
        ):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                with connection.cursor() as cursor:
                    cursor.execute(statement)


def test_invalid_contract_is_400(http_context):
    status, payload = _search(http_context, limit=21)
    assert status == 400 and payload["error"] == "invalid_search_request"


def test_results_are_traceable_and_restricted_to_allowed_scope(http_context):
    status, payload = _search(http_context, limit=2)
    assert status == 200 and payload["success"] is True and payload["result_count"] == 2
    forbidden = {"New 2027 fixture", "Pending fixture", "Historical fixture", "Unknown scope fixture"}
    assert forbidden.isdisjoint({source["title"] for source in payload["sources"]})
    for source in payload["sources"]:
        assert source["source_url"].startswith("https://")
        assert source["locator"]
        assert source["metadata"]["curriculum_scope"] in {"old_9s_151c", "general"}


def test_valid_search_can_return_no_results(http_context):
    status, payload = _search(http_context, query=http_context.no_result_query, threshold=1.0)
    assert status == 200 and payload == {"success": True, "result_count": 0, "sources": [], "context": ""}


def test_result_and_context_limits_are_enforced(http_context):
    status, payload = _search(http_context, limit=20)
    assert status == 200
    assert 1 <= payload["result_count"] <= 20
    assert len(payload["context"]) <= 12_000
    assert all(len(source["content"]) <= 3_000 for source in payload["sources"])


def test_mutating_or_unrelated_routes_do_not_exist(http_context):
    for path, method in (("/v1/rag/documents", "POST"), ("/v1/rag/embeddings", "POST"),
                         ("/v1/students", "GET"), ("/v1/rag/search", "PUT")):
        status, payload = _http(path, method=method, body={} if method != "GET" else None,
                                tool_key=http_context.tool_key)
        assert status == 404 and payload["error"] == "not_found"


def test_z_database_unavailable_is_safe_503_and_recovers(http_context):
    subprocess.run(["docker", "stop", "nebula-rag-local-postgres"], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        status, payload = _search(http_context)
        assert status == 503 and payload == {"success": False, "error": "rag_unavailable"}
        serialized = json.dumps(payload)
        assert http_context.password not in serialized and http_context.api_password not in serialized
        assert "postgresql://" not in serialized
    finally:
        subprocess.run(["docker", "start", "nebula-rag-local-postgres"], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            ready = subprocess.run(["docker", "exec", "nebula-rag-local-postgres", "pg_isready",
                                    "-U", "postgres", "-d", "rag_local"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if ready.returncode == 0:
                try:
                    with urllib.request.urlopen("http://127.0.0.1:53000/", timeout=2) as response:
                        if response.status == 200:
                            break
                except urllib.error.URLError:
                    pass
            time.sleep(0.5)
        else:
            pytest.fail("local PostgreSQL and PostgREST did not recover")
