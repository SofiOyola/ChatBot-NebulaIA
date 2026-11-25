from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass

from .models import ExtractedDocument, TextChunk


@dataclass(frozen=True)
class ChunkingConfig:
    max_chars: int = 1800
    overlap_chars: int = 180
    min_chars: int = 40

    def __post_init__(self) -> None:
        if self.max_chars < 100 or self.overlap_chars < 0 or self.overlap_chars >= self.max_chars:
            raise ValueError("invalid chunk size or overlap")
        if self.min_chars < 1 or self.min_chars > self.max_chars:
            raise ValueError("invalid minimum chunk size")


def _normalize(value: str) -> str:
    return re.sub(r"[ \t]+", " ", re.sub(r"\r\n?", "\n", value)).strip()


def chunk_document(document: ExtractedDocument, config: ChunkingConfig) -> list[TextChunk]:
    text = _normalize(document.content)
    if not text:
        return []
    chunks: list[TextChunk] = []
    start = 0
    while start < len(text):
        end = min(start + config.max_chars, len(text))
        if end < len(text):
            boundary = max(text.rfind("\n", start, end), text.rfind(". ", start, end))
            if boundary >= start + config.min_chars:
                end = boundary + 1
        content = text[start:end].strip()
        if content and (len(content) >= config.min_chars or not chunks):
            digest = hashlib.sha256(content.encode("utf-8")).hexdigest()
            chunks.append(TextChunk(len(chunks), f"{document.locator_prefix}:chunk-{len(chunks)}", content, digest))
        if end >= len(text):
            break
        start = max(end - config.overlap_chars, start + 1)
    return chunks
