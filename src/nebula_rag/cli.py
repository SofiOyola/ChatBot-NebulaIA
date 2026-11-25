from __future__ import annotations

import argparse
import json
import os
from dataclasses import replace
from datetime import date
from pathlib import Path

import psycopg

from .chunking import ChunkingConfig, chunk_document
from .embeddings import GeminiEmbeddingProvider
from .models import SourceConfig
from .pipeline import IngestionPipeline
from .repository import PostgresRagRepository
from .scraper import AcademicFetcher
from .local_demo import assert_demo_staging_authorized, enrich_document, load_local_demo


def _optional_date(value) -> date | None:
    return date.fromisoformat(value) if value else None


def _source(path: str, name: str) -> SourceConfig:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    matches = [item for item in payload.get("sources", []) if item.get("name") == name]
    if len(matches) != 1:
        raise ValueError("source name must identify exactly one configured source")
    item = matches[0]
    return SourceConfig(
        name=item["name"], base_url=item["base_url"], allowed_hosts=tuple(item["allowed_hosts"]),
        source_type=item.get("source_type", "official"),
        allowed_path_prefixes=tuple(item.get("allowed_path_prefixes", ["/"])),
        requests_per_minute=int(item.get("requests_per_minute", 6)), enabled=bool(item.get("enabled", False)),
        information_type=item.get("information_type", "general"),
        authority_level=item.get("authority_level", "institutional_informative"),
        curriculum_scope=item.get("curriculum_scope", "unknown"),
        responsible_entity=item.get("responsible_entity"), program_key=item.get("program_key"),
        published_on=_optional_date(item.get("published_on")),
        effective_from=_optional_date(item.get("effective_from")),
        effective_to=_optional_date(item.get("effective_to")),
        validity_status=item.get("validity_status", "pending_review"),
        content_class=item.get("content_class", "institutional"),
        authorization_status=item.get("authorization_status", "pending"),
        authorization_reference=item.get("authorization_reference"),
        authorization_date=_optional_date(item.get("authorization_date")),
        authorization_scope=tuple(item.get("authorization_scope", [])),
        local_file=item.get("local_file"),
    )


def _database_url() -> str:
    value = os.getenv("RAG_DATABASE_URL", "")
    if not value:
        raise RuntimeError("RAG_DATABASE_URL is required at runtime")
    return value


def main() -> None:
    parser = argparse.ArgumentParser(description="Manual, review-gated Nébula academic ingestion")
    parser.add_argument("command", choices=("preview", "stage", "embed", "approve", "reject"))
    parser.add_argument("--sources", default="config/rag-sources.json")
    parser.add_argument("--source")
    parser.add_argument("--url")
    parser.add_argument("--document-id", type=int)
    args = parser.parse_args()

    if args.command in {"preview", "stage"}:
        if not args.source or not args.url:
            parser.error("--source and --url are required")
        source = _source(args.sources, args.source)
        if source.local_file:
            project_root = Path(__file__).resolve().parents[2]
            document = load_local_demo(source, project_root=project_root, url=args.url)
        else:
            document = enrich_document(AcademicFetcher().fetch(args.url, source), source)
        chunks = chunk_document(document, ChunkingConfig())
        if args.command == "preview":
            print(json.dumps({"title": document.title, "source_url": document.source_url,
                              "content_sha256": document.content_sha256, "chunk_count": len(chunks),
                              "responsible_entity": document.publisher,
                              "content_class": document.content_class,
                              "authorization_status": document.authorization_status,
                              "information_type": document.information_type,
                              "authority_level": document.authority_level,
                              "curriculum_scope": document.curriculum_scope},
                             ensure_ascii=False))
            return
        assert_demo_staging_authorized(document)
        with psycopg.connect(_database_url()) as connection:
            document_id, created = PostgresRagRepository(connection).stage_document(document, chunks)
            print(json.dumps({"document_id": document_id, "created": created,
                              "validation_status": "pending"}))
        return

    if not args.document_id:
        parser.error("--document-id is required")
    with psycopg.connect(_database_url()) as connection:
        repository = PostgresRagRepository(connection)
        if args.command == "approve":
            profile = os.getenv("RAG_EMBEDDING_PROFILE_ID", "")
            if not profile:
                raise RuntimeError("RAG_EMBEDDING_PROFILE_ID is required at runtime")
            repository.approve_document(args.document_id, profile)
        elif args.command == "reject":
            repository.reject_document(args.document_id)
        else:
            api_key = os.getenv("GEMINI_API_KEY", "")
            profile = os.getenv("RAG_EMBEDDING_PROFILE_ID", "")
            if not api_key or not profile:
                raise RuntimeError("GEMINI_API_KEY and RAG_EMBEDDING_PROFILE_ID are required at runtime")
            dimension = int(os.getenv("RAG_EMBEDDING_DIMENSION", "768"))
            provider = GeminiEmbeddingProvider(api_key, os.getenv("RAG_EMBEDDING_MODEL", "gemini-embedding-001"), dimension)
            count = IngestionPipeline(repository, provider, profile).embed_chunks(
                repository.document_title(args.document_id), repository.document_chunks(args.document_id))
            print(json.dumps({"document_id": args.document_id, "embeddings_stored": count}))


if __name__ == "__main__":
    main()
