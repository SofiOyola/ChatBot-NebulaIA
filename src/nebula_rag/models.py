from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Any, Literal


ValidationStatus = Literal["pending", "documented", "contradictory", "excluded"]


@dataclass(frozen=True)
class SourceConfig:
    name: str
    base_url: str
    allowed_hosts: tuple[str, ...]
    source_type: Literal["official", "third_party"] = "official"
    allowed_path_prefixes: tuple[str, ...] = ("/",)
    requests_per_minute: int = 6
    enabled: bool = False
    information_type: str = "general"
    authority_level: str = "institutional_informative"
    curriculum_scope: str = "unknown"
    responsible_entity: str | None = None
    program_key: str | None = None
    published_on: date | None = None
    effective_from: date | None = None
    effective_to: date | None = None
    validity_status: str = "pending_review"
    content_class: Literal["institutional", "demo_non_institutional"] = "institutional"
    authorization_status: Literal["pending", "approved", "rejected", "not_required"] = "pending"
    authorization_reference: str | None = None
    authorization_date: date | None = None
    authorization_scope: tuple[str, ...] = ()
    local_file: str | None = None


@dataclass(frozen=True)
class ExtractedDocument:
    title: str
    source_url: str
    source_type: Literal["official", "third_party"]
    accessed_on: date
    content: str
    locator_prefix: str
    content_sha256: str
    metadata: dict[str, Any] = field(default_factory=dict)
    information_type: str = "general"
    authority_level: str = "institutional_informative"
    validity_status: str = "pending_review"
    curriculum_scope: str = "unknown"
    program_key: str | None = None
    published_on: date | None = None
    effective_from: date | None = None
    effective_to: date | None = None
    publisher: str | None = None
    content_class: str = "institutional"
    authorization_status: str = "pending"
    authorization_reference: str | None = None
    authorization_date: date | None = None


@dataclass(frozen=True)
class TextChunk:
    index: int
    locator: str
    content: str
    content_sha256: str
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class SearchResult:
    title: str
    source_url: str
    locator: str
    content: str
    similarity: float
    metadata: dict[str, Any]
