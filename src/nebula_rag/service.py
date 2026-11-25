from __future__ import annotations

from .security import build_untrusted_context, content_security_flags


class RagSearchService:
    MAX_CONTEXT_CHARS = 12_000
    MAX_SOURCE_CONTENT_CHARS = 3_000

    def __init__(self, repository, provider, profile_id: str) -> None:
        self.repository = repository
        self.provider = provider
        self.profile_id = profile_id

    def search(self, query: str, *, limit: int = 5, threshold: float = 0.0,
               curriculum_scope: str = "old_9s_151c") -> dict:
        if not isinstance(query, str) or not query.strip() or len(query) > 2000:
            raise ValueError("query must be a non-empty string of at most 2000 characters")
        if not 1 <= limit <= 20 or not 0 <= threshold <= 1:
            raise ValueError("invalid search limit or threshold")
        if curriculum_scope not in {"old_9s_151c", "general"}:
            raise ValueError("unsupported curriculum scope")
        vector = self.provider.embed_query(query)
        results = self.repository.search(vector, self.profile_id, limit, threshold,
                                         query_text=query, curriculum_scope=curriculum_scope)
        sources, context_chars = [], 0
        for result in results:
            if context_chars >= self.MAX_CONTEXT_CHARS:
                break
            available = min(self.MAX_SOURCE_CONTENT_CHARS, self.MAX_CONTEXT_CHARS - context_chars)
            content = result.content[:available]
            context_chars += len(content)
            sources.append({"title": result.title, "source_url": result.source_url,
                            "locator": result.locator, "similarity": result.similarity,
                            "metadata": result.metadata, "security_flags": content_security_flags(content),
                            "content": content, "truncated": len(content) < len(result.content)})
        context = build_untrusted_context(sources) if sources else ""
        while len(context) > self.MAX_CONTEXT_CHARS and sources:
            if len(sources) > 1:
                sources.pop()
            else:
                overhead = len(build_untrusted_context([{**sources[0], "content": ""}]))
                allowed = max(0, self.MAX_CONTEXT_CHARS - overhead)
                sources[0]["content"] = sources[0]["content"][:allowed]
                sources[0]["truncated"] = True
            context = build_untrusted_context(sources) if sources else ""
        return {"success": True, "result_count": len(sources), "sources": sources, "context": context}
