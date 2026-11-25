from __future__ import annotations

import hashlib
import json
from dataclasses import replace
from datetime import date
from pathlib import Path
from urllib.parse import urlparse

from .extraction import extract_html
from .models import ExtractedDocument, SourceConfig


MAX_LOCAL_DEMO_BYTES = 1_000_000
REQUIRED_AUTHORIZATION_USES = {"extract", "chunk", "embed", "store", "present"}


def enrich_document(document: ExtractedDocument, source: SourceConfig,
                    authorization_metadata: dict | None = None) -> ExtractedDocument:
    metadata = dict(document.metadata)
    metadata.update({
        "demo_non_institutional": source.content_class == "demo_non_institutional",
        "content_class": source.content_class,
        "responsible_entity": source.responsible_entity,
        "authorization": authorization_metadata or {
            "status": source.authorization_status,
            "reference": source.authorization_reference,
            "date": source.authorization_date.isoformat() if source.authorization_date else None,
            "scope": list(source.authorization_scope),
        },
    })
    return replace(
        document,
        metadata=metadata,
        information_type=source.information_type,
        authority_level=source.authority_level,
        curriculum_scope=source.curriculum_scope,
        program_key=source.program_key,
        published_on=source.published_on or document.published_on,
        effective_from=source.effective_from,
        effective_to=source.effective_to,
        validity_status=source.validity_status,
        publisher=source.responsible_entity,
        content_class=source.content_class,
        authorization_status=source.authorization_status,
        authorization_reference=source.authorization_reference,
        authorization_date=source.authorization_date,
    )


def load_local_demo(source: SourceConfig, *, project_root: Path, url: str) -> ExtractedDocument:
    if not source.enabled:
        raise PermissionError("local demonstration source is disabled")
    if source.content_class != "demo_non_institutional" or source.source_type != "third_party" or \
       source.authority_level != "secondary" or source.information_type != "general" or \
       source.curriculum_scope != "general":
        raise PermissionError("local demonstration classification is unsafe")
    parsed = urlparse(url)
    if url != source.base_url or parsed.scheme != "https" or not parsed.hostname or \
       parsed.hostname not in source.allowed_hosts or not parsed.hostname.endswith(".invalid"):
        raise PermissionError("local demonstration canonical URL is invalid")
    if not source.local_file or not source.authorization_reference:
        raise PermissionError("local file and authorization evidence are required")
    pilot_root = (project_root / "docs" / "rag-pilot").resolve()
    document_path = (project_root / source.local_file).resolve()
    evidence_path = (project_root / source.authorization_reference).resolve()
    if pilot_root not in document_path.parents or pilot_root not in evidence_path.parents:
        raise PermissionError("local demonstration files must remain under docs/rag-pilot")
    body = document_path.read_bytes()
    if not body or len(body) > MAX_LOCAL_DEMO_BYTES:
        raise ValueError("local demonstration document size is invalid")
    evidence_bytes = evidence_path.read_bytes()
    evidence = json.loads(evidence_bytes.decode("utf-8"))
    if evidence.get("document_file") != document_path.name or \
       evidence.get("status") != source.authorization_status or \
       set(evidence.get("permitted_uses", [])) != set(source.authorization_scope):
        raise PermissionError("authorization evidence does not match source configuration")
    authorization = {
        "status": evidence.get("status"),
        "reference": source.authorization_reference,
        "date": evidence.get("authorization_date"),
        "authorized_by": evidence.get("authorized_by"),
        "permitted_uses": evidence.get("permitted_uses", []),
        "evidence_sha256": hashlib.sha256(evidence_bytes).hexdigest(),
    }
    document = extract_html(body, url=url, allowed_hosts=source.allowed_hosts,
                            accessed_on=date.today(), source_type=source.source_type)
    return enrich_document(document, source, authorization)


def assert_demo_staging_authorized(document: ExtractedDocument) -> None:
    if document.content_class != "demo_non_institutional":
        return
    authorization = document.metadata.get("authorization", {})
    if document.authorization_status != "approved" or authorization.get("status") != "approved" or \
       not authorization.get("authorized_by") or not authorization.get("date") or \
       set(authorization.get("permitted_uses", [])) != REQUIRED_AUTHORIZATION_USES:
        raise PermissionError("demonstration material is not approved for staging and embeddings")
