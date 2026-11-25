from __future__ import annotations

import hmac
import json
import os
from wsgiref.simple_server import make_server

import psycopg

from .embeddings import DeterministicTestEmbedding, GeminiEmbeddingProvider
from .http_contract import encode_response, handle_search_request
from .repository import PostgresRagRepository
from .service import RagSearchService


def _required(name: str) -> str:
    value = os.getenv(name, "")
    if not value:
        raise RuntimeError(f"required environment variable is missing: {name}")
    return value


class Application:
    def __init__(self, database_url: str, tool_key: str, provider, profile_id: str) -> None:
        self.database_url, self.tool_key, self.provider, self.profile_id = database_url, tool_key, provider, profile_id

    def __call__(self, environ, start_response):
        if environ.get("PATH_INFO") == "/health" and environ.get("REQUEST_METHOD") == "GET":
            status, payload = 200, {"status": "ok"}
        elif environ.get("PATH_INFO") != "/v1/rag/search" or environ.get("REQUEST_METHOD") != "POST":
            status, payload = 404, {"success": False, "error": "not_found"}
        elif not hmac.compare_digest(environ.get("HTTP_X_NEBULA_TOOL_KEY", ""), self.tool_key):
            status, payload = 401, {"success": False, "error": "unauthorized"}
        else:
            try:
                length = int(environ.get("CONTENT_LENGTH") or 0)
                if length < 2 or length > 20_000:
                    raise ValueError
                request_payload = json.loads(environ["wsgi.input"].read(length).decode("utf-8"))
                with psycopg.connect(self.database_url) as connection:
                    service = RagSearchService(PostgresRagRepository(connection), self.provider, self.profile_id)
                    status, payload = handle_search_request(request_payload, service)
            except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
                status, payload = 400, {"success": False, "error": "invalid_json_contract"}
            except Exception:
                status, payload = 503, {"success": False, "error": "rag_unavailable"}
        body = encode_response(payload)
        start_response(f"{status} {'OK' if status < 400 else 'Error'}",
                       [("Content-Type", "application/json; charset=utf-8"), ("Content-Length", str(len(body)))])
        return [body]


def create_application() -> Application:
    dimension = int(os.getenv("RAG_EMBEDDING_DIMENSION", "768"))
    provider_name = os.getenv("RAG_EMBEDDING_PROVIDER", "gemini").lower()
    if provider_name == "deterministic-test-only":
        host = os.getenv("RAG_HTTP_HOST", "127.0.0.1")
        if os.getenv("RAG_ALLOW_TEST_PROVIDER", "").lower() != "true" or host not in {
            "127.0.0.1", "localhost", "::1"
        }:
            raise RuntimeError("deterministic provider is restricted to explicit loopback tests")
        provider = DeterministicTestEmbedding(dimension=dimension)
    elif provider_name == "gemini":
        provider = GeminiEmbeddingProvider(_required("GEMINI_API_KEY"),
                                           model=os.getenv("RAG_EMBEDDING_MODEL", "gemini-embedding-001"),
                                           dimension=dimension)
    else:
        raise RuntimeError("unsupported embedding provider")
    return Application(_required("RAG_DATABASE_URL"), _required("NEBULA_RAG_TOOL_KEY"), provider,
                       _required("RAG_EMBEDDING_PROFILE_ID"))


def main() -> None:
    app = create_application()
    host, port = os.getenv("RAG_HTTP_HOST", "127.0.0.1"), int(os.getenv("RAG_HTTP_PORT", "8091"))
    make_server(host, port, app).serve_forever()


if __name__ == "__main__":
    main()
