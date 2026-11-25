from __future__ import annotations

import json


def handle_search_request(payload: object, service) -> tuple[int, dict]:
    if not isinstance(payload, dict):
        return 400, {"success": False, "error": "invalid_json_contract"}
    allowed = {"query", "limit", "threshold", "curriculum_scope"}
    if set(payload) - allowed or not isinstance(payload.get("query"), str):
        return 400, {"success": False, "error": "invalid_search_request"}
    try:
        result = service.search(payload["query"], limit=payload.get("limit", 5),
                                threshold=payload.get("threshold", 0.0),
                                curriculum_scope=payload.get("curriculum_scope", "old_9s_151c"))
        return 200, result
    except ValueError:
        return 400, {"success": False, "error": "invalid_search_request"}
    except Exception:
        return 503, {"success": False, "error": "rag_unavailable"}


def encode_response(payload: dict) -> bytes:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
