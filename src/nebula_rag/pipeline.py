from __future__ import annotations

from dataclasses import dataclass

from .chunking import ChunkingConfig, chunk_document


@dataclass
class IngestionPipeline:
    repository: object
    provider: object
    profile_id: str
    chunking: ChunkingConfig = ChunkingConfig()

    def stage(self, document) -> dict:
        chunks = chunk_document(document, self.chunking)
        if not chunks:
            raise ValueError("document produced no usable chunks")
        document_id, created = self.repository.stage_document(document, chunks)
        return {"document_id": document_id, "created": created, "chunk_count": len(chunks)}

    def embed_chunks(self, title: str, chunks_with_ids: list[tuple[int, str]]) -> int:
        stored = 0
        for chunk_id, content in chunks_with_ids:
            vector = self.provider.embed_document(content, title=title)
            self.repository.store_embedding(chunk_id, self.profile_id, vector)
            stored += 1
        return stored
