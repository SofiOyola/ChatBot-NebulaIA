from __future__ import annotations

import json
import os
import secrets
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pytest


ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "tests" / "reports"


def _load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


_load_env_file(ROOT / ".env.test")


@dataclass(frozen=True)
class Config:
    url: str
    anon_key: str
    service_key: str
    database_url: str


def _request(url: str, *, method: str = "GET", headers: dict[str, str] | None = None,
             body: Any = None) -> tuple[int, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = raw
        return exc.code, payload


@pytest.fixture(scope="session")
def config() -> Config:
    if os.getenv("NEBULA_TEST_ENV", "").lower() != "true":
        pytest.skip("NEBULA_TEST_ENV no es true; se evita tocar un entorno no confirmado como aislado")
    names = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY", "TEST_DATABASE_URL"]
    missing = [name for name in names if not os.getenv(name)]
    if missing:
        pytest.skip("faltan variables para la integracion: " + ", ".join(missing))
    url = os.environ["SUPABASE_URL"].rstrip("/")
    if url in {"https://project-ref.supabase.co", "http://localhost"}:
        pytest.skip("SUPABASE_URL conserva un valor de ejemplo")
    return Config(url, os.environ["SUPABASE_ANON_KEY"], os.environ["SUPABASE_SERVICE_ROLE_KEY"],
                  os.environ["TEST_DATABASE_URL"])


def _admin_headers(config: Config) -> dict[str, str]:
    return {"apikey": config.service_key, "Authorization": f"Bearer {config.service_key}",
            "Content-Type": "application/json"}


def _create_user(config: Config, email: str, password: str) -> str:
    status, payload = _request(f"{config.url}/auth/v1/admin/users", method="POST",
                               headers=_admin_headers(config),
                               body={"email": email, "password": password, "email_confirm": True})
    if status not in (200, 201):
        pytest.fail(f"Auth Admin no pudo crear fixture ({status}): {payload}")
    return payload["id"]


def _token(config: Config, email: str, password: str) -> str:
    status, payload = _request(f"{config.url}/auth/v1/token?grant_type=password", method="POST",
                               headers={"apikey": config.anon_key, "Content-Type": "application/json"},
                               body={"email": email, "password": password})
    if status != 200:
        pytest.fail(f"Auth no emitio JWT para fixture ({status}): {payload}")
    return payload["access_token"]


@pytest.fixture(scope="session")
def rpc_context(config: Config):
    try:
        import psycopg
    except ImportError:
        pytest.skip("falta psycopg; ejecute: python -m pip install -r requirements-test.txt")

    run_id = f"{int(time.time())}-{secrets.token_hex(4)}"
    password_a = secrets.token_urlsafe(24)
    password_b = secrets.token_urlsafe(24)
    users: list[str] = []
    connection = None
    try:
        email_a = f"nebula.rpc.a.{run_id}@example.invalid"
        email_b = f"nebula.rpc.b.{run_id}@example.invalid"
        user_a = _create_user(config, email_a, password_a)
        users.append(user_a)
        user_b = _create_user(config, email_b, password_b)
        users.append(user_b)
        connection = psycopg.connect(config.database_url, autocommit=True)
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT cv.curriculum_id
                FROM academic.curriculum_versions cv
                JOIN academic.curriculum_positions cp USING (curriculum_id)
                GROUP BY cv.curriculum_id
                HAVING count(*) >= 4
                ORDER BY cv.curriculum_id LIMIT 1
            """)
            curriculum = cursor.fetchone()
            if curriculum is None:
                pytest.skip("el proyecto de pruebas no contiene un pensum con al menos cuatro posiciones")
            curriculum_id = curriculum[0]
            cursor.execute("""
                SELECT position_id, credits
                FROM academic.curriculum_positions
                WHERE curriculum_id = %s AND credits > 0
                ORDER BY semester, position_number LIMIT 4
            """, (curriculum_id,))
            positions = cursor.fetchall()
            if len(positions) < 4:
                pytest.skip("el pensum no tiene cuatro materias con creditos para los escenarios")
            cursor.executemany(
                "INSERT INTO student.profiles (user_id, curriculum_id, full_name) VALUES (%s, %s, %s)",
                [(user_a, curriculum_id, "Fixture RPC A"), (user_b, curriculum_id, "Fixture RPC B")],
            )
            attempts = [
                (user_a, curriculum_id, positions[0][0], 1, 2.5, "failed", "student_reported"),
                (user_a, curriculum_id, positions[1][0], 1, 2.8, "failed", "institution_verified"),
                (user_a, curriculum_id, positions[1][0], 2, 4.0, "passed", "institution_verified"),
                (user_a, curriculum_id, positions[2][0], 1, 4.2, "passed", "student_reported"),
                (user_a, curriculum_id, positions[3][0], 1, 4.5, "passed", "admin_recorded"),
            ]
            cursor.executemany("""
                INSERT INTO student.course_attempts
                    (user_id, curriculum_id, position_id, attempt_number, final_grade, outcome, source_type)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, attempts)
            cursor.execute("SELECT attempt_id FROM student.course_attempts WHERE user_id = %s ORDER BY attempt_id LIMIT 1",
                           (user_a,))
            attempt_id = cursor.fetchone()[0]
            cursor.execute("SELECT total_credits FROM academic.curriculum_versions WHERE curriculum_id = %s",
                           (curriculum_id,))
            total_credits = cursor.fetchone()[0]
        yield {
            "config": config, "curriculum_id": curriculum_id, "positions": positions,
            "user_a": user_a, "user_b": user_b, "attempt_id": attempt_id,
            "token_a": _token(config, email_a, password_a), "token_b": _token(config, email_b, password_b),
            "total_credits": total_credits,
        }
    finally:
        if connection is not None and users:
            with connection.cursor() as cursor:
                cursor.execute("DELETE FROM student.course_attempts WHERE user_id = ANY(%s::uuid[])", (users,))
                cursor.execute("DELETE FROM student.profiles WHERE user_id = ANY(%s::uuid[])", (users,))
            connection.close()
        for user_id in reversed(users):
            _request(f"{config.url}/auth/v1/admin/users/{user_id}", method="DELETE",
                     headers=_admin_headers(config))


@pytest.fixture
def rpc(rpc_context):
    def call(name: str, token: str | None = None) -> tuple[int, Any]:
        config = rpc_context["config"]
        headers = {"apikey": config.anon_key, "Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        return _request(f"{config.url}/rest/v1/rpc/{name}", method="POST", headers=headers, body={})
    return call


def pytest_sessionfinish(session, exitstatus):
    REPORTS.mkdir(parents=True, exist_ok=True)
    results = []
    for item in session.items:
        report = getattr(item, "_nebula_report", None)
        if report is None:
            status, explanation = "SKIP", "la prueba no llego a ejecutarse"
        elif report.skipped:
            status, explanation = "SKIP", str(report.longrepr)
        elif report.failed:
            status, explanation = "FAIL", str(report.longrepr)
        else:
            status, explanation = "PASS", "comprobacion completada"
        results.append({"test": item.nodeid, "status": status, "explanation": explanation})
    summary = {key: sum(r["status"] == key for r in results) for key in ("PASS", "FAIL", "SKIP")}
    (REPORTS / "latest.json").write_text(
        json.dumps({"summary": summary, "results": results}, ensure_ascii=False, indent=2), encoding="utf-8")


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    report = outcome.get_result()
    if report.when == "setup" and (report.failed or report.skipped):
        item._nebula_report = report
    elif report.when == "call":
        item._nebula_report = report
