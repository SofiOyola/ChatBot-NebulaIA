from __future__ import annotations

import json
import math
import os

from nebula_rag.embeddings import GeminiEmbeddingProvider


def main() -> None:
    api_key = os.getenv("GEMINI_API_KEY", "")
    if not api_key:
        raise SystemExit("GEMINI_API_KEY is required in process memory")
    provider = GeminiEmbeddingProvider(api_key, "gemini-embedding-001", 768)
    document = provider.embed_document(
        "Texto institucional neutro para validar el contrato tecnico del embedding.",
        title="Prueba tecnica controlada",
    )
    query = provider.embed_query("consulta tecnica controlada")
    result = {
        "model": provider.model,
        "expected_dimension": provider.dimension,
        "document_dimension": len(document),
        "query_dimension": len(query),
        "document_norm_ok": abs(math.sqrt(sum(value * value for value in document)) - 1.0) < 1e-5,
        "query_norm_ok": abs(math.sqrt(sum(value * value for value in query)) - 1.0) < 1e-5,
        "external_requests": 2,
    }
    if not all((result["document_dimension"] == 768, result["query_dimension"] == 768,
                result["document_norm_ok"], result["query_norm_ok"])):
        raise SystemExit("embedding contract validation failed")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
