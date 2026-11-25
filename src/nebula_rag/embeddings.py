from __future__ import annotations

import hashlib
import math
import time
from dataclasses import dataclass
from typing import Protocol

import requests


class EmbeddingError(RuntimeError):
    pass


class EmbeddingProvider(Protocol):
    model: str
    dimension: int
    def embed_document(self, text: str, *, title: str) -> list[float]: ...
    def embed_query(self, text: str) -> list[float]: ...


def validate_vector(values: list[float], dimension: int, *, normalize: bool) -> list[float]:
    if len(values) != dimension or not all(math.isfinite(value) for value in values):
        raise EmbeddingError("provider returned an invalid embedding dimension or value")
    norm = math.sqrt(sum(value * value for value in values))
    if norm <= 0:
        raise EmbeddingError("provider returned a zero-norm embedding")
    return [value / norm for value in values] if normalize else values


@dataclass
class DeterministicTestEmbedding:
    dimension: int = 8
    model: str = "offline-deterministic-test-only"

    def _embed(self, text: str) -> list[float]:
        if not text.strip():
            raise EmbeddingError("text is required")
        values = [0.0] * self.dimension
        for token in text.lower().split():
            digest = hashlib.sha256(token.encode()).digest()
            values[int.from_bytes(digest[:2], "big") % self.dimension] += 1.0
        return validate_vector(values, self.dimension, normalize=True)

    def embed_document(self, text: str, *, title: str) -> list[float]:
        return self._embed(f"{title} {text}")

    def embed_query(self, text: str) -> list[float]:
        return self._embed(text)


@dataclass
class GeminiEmbeddingProvider:
    api_key: str
    model: str = "gemini-embedding-001"
    dimension: int = 768
    timeout_seconds: int = 30
    max_attempts: int = 2
    endpoint_root: str = "https://generativelanguage.googleapis.com/v1beta/models"

    def _embed(self, text: str, task_type: str, title: str | None = None) -> list[float]:
        if not self.api_key or not text.strip():
            raise EmbeddingError("API key and non-empty text are required")
        payload = {"content": {"parts": [{"text": text}]}, "taskType": task_type,
                   "output_dimensionality": self.dimension}
        if title:
            payload["title"] = title
        last_error: Exception | None = None
        for attempt in range(self.max_attempts):
            try:
                response = requests.post(f"{self.endpoint_root}/{self.model}:embedContent", json=payload,
                                         headers={"x-goog-api-key": self.api_key}, timeout=self.timeout_seconds)
                if response.status_code == 429 or response.status_code >= 500:
                    response.raise_for_status()
                if response.status_code >= 400:
                    raise EmbeddingError("embedding provider rejected the request")
                values = response.json()["embedding"]["values"]
                return validate_vector([float(value) for value in values], self.dimension, normalize=self.dimension != 3072)
            except EmbeddingError:
                raise
            except (requests.RequestException, KeyError, TypeError, ValueError) as exc:
                last_error = exc
                if attempt + 1 < self.max_attempts:
                    time.sleep(0.25 * (attempt + 1))
        raise EmbeddingError("embedding provider failed after limited retries") from last_error

    def embed_document(self, text: str, *, title: str) -> list[float]:
        return self._embed(text, "RETRIEVAL_DOCUMENT", title)

    def embed_query(self, text: str) -> list[float]:
        return self._embed(text, "RETRIEVAL_QUERY")
