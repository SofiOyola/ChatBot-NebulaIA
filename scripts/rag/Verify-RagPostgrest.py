from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.request


def main() -> None:
    parser = argparse.ArgumentParser(description="Safe PostgREST contract check for an isolated RAG project")
    parser.add_argument("--allow-network", action="store_true")
    args = parser.parse_args()
    if not args.allow_network:
        raise SystemExit("SKIP: use --allow-network only for an isolated project")
    url = os.getenv("SUPABASE_TEST_URL", "").rstrip("/")
    key = os.getenv("SUPABASE_TEST_ANON_KEY", "")
    profile = os.getenv("RAG_TEST_PROFILE_ID", "")
    dimension_text = os.getenv("RAG_TEST_PROFILE_DIMENSION", "")
    if not url or not key or not profile or not dimension_text:
        raise SystemExit("SKIP: isolated PostgREST variables are incomplete")
    if "icsekpkuheckfkgkqosg" in url:
        raise SystemExit("BLOCKED: the known primary project is not allowed")
    dimension = int(dimension_text)
    if not 1 <= dimension <= 16000:
        raise SystemExit("SKIP: invalid test profile dimension")
    if input("Type PROBAR POSTGREST AISLADO to continue: ") != "PROBAR POSTGREST AISLADO":
        raise SystemExit("Cancelled without requests")
    vector = [0.0] * dimension
    vector[0] = 1.0
    body = json.dumps({"p_query_text": "verificacion tecnica rag", "p_query_embedding": vector,
                       "p_profile_id": profile, "p_curriculum_scope": "old_9s_151c",
                       "p_match_count": 3, "p_min_similarity": 0}).encode()
    request = urllib.request.Request(
        f"{url}/rest/v1/rpc/nebula_search_academic_chunks_hybrid", data=body, method="POST",
        headers={"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode())
            status = response.status
    except urllib.error.HTTPError as exc:
        exc.read()
        raise SystemExit(f"FAIL: PostgREST returned HTTP {exc.code}; body suppressed")
    if status != 200 or not isinstance(payload, list):
        raise SystemExit("FAIL: unexpected HTTP or JSON contract")
    required = {"document_title", "source_url", "locator", "content", "curriculum_scope", "rank_score"}
    if any(not required.issubset(item) or item.get("curriculum_scope") not in {"general", "old_9s_151c"}
           for item in payload):
        raise SystemExit("FAIL: unsafe or incomplete result contract")
    print(json.dumps({"status": "PASS", "http": status, "result_count": len(payload),
                      "old_curriculum_filter": True}, separators=(",", ":")))


if __name__ == "__main__":
    main()
