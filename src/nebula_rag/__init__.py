"""Local, security-focused RAG and academic source ingestion components."""

from .chunking import ChunkingConfig, chunk_document
from .models import ExtractedDocument, SourceConfig, TextChunk

__all__ = ["ChunkingConfig", "ExtractedDocument", "SourceConfig", "TextChunk", "chunk_document"]
