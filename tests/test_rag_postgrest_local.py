from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

import pytest


BASE = "http://127.0.0.1:53000"


def _request(path: str, body: dict | None = None) -> tuple[int, object]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(BASE + path, data=data,
                                     method="GET" if data is None else "POST",
                                     headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = None
        return exc.code, payload


pytestmark = pytest.mark.skipif(
    os.getenv("NEBULA_RAG_POSTGREST_TEST") != "1",
    reason="NEBULA_RAG_POSTGREST_TEST no es 1; no se llama al PostgREST local",
)


def test_private_tables_are_not_exposed():
    status, _ = _request("/documents?select=*")
    assert status in {401, 404}


@pytest.mark.parametrize("name,body", [
    ("nebula_search_academic_chunks", {
        "p_query_embedding": "[1,0,0]", "p_profile_id": "local-synthetic-3d",
        "p_match_count": 10, "p_min_similarity": 0,
    }),
    ("nebula_search_academic_chunks_hybrid", {
        "p_query_text": "curriculum credits", "p_query_embedding": "[1,0,0]",
        "p_profile_id": "local-synthetic-3d", "p_curriculum_scope": "old_9s_151c",
        "p_match_count": 10, "p_min_similarity": 0,
    }),
])
def test_anonymous_postgrest_cannot_execute_rag_rpcs(name, body):
    status, _ = _request(f"/rpc/{name}", body)
    assert status in {401, 403, 404}
