from __future__ import annotations

import json
import urllib.error
import urllib.request

import pytest


pytestmark = pytest.mark.integration


@pytest.mark.parametrize("function", ["get_academic_history", "get_credit_progress"])
def test_anonymous_calls_are_rejected(rpc, function):
    status, payload = rpc(function)
    assert status in (401, 403), f"RPC anonimo no fue rechazado: HTTP {status}, {payload}"


def test_each_student_only_reads_own_history(rpc, rpc_context):
    status_a, history_a = rpc("get_academic_history", rpc_context["token_a"])
    status_b, history_b = rpc("get_academic_history", rpc_context["token_b"])
    assert status_a == 200, f"historial A fallo: HTTP {status_a}, {history_a}"
    assert status_b == 200, f"historial B fallo: HTTP {status_b}, {history_b}"
    assert len(history_a) == 5
    assert history_b == [], "el estudiante sin intentos recibio datos ajenos"
    assert {row["position_id"] for row in history_a} == {p[0] for p in rpc_context["positions"]}


def test_rpc_has_no_parameter_to_request_another_user(rpc, rpc_context):
    config = rpc_context["config"]
    request = urllib.request.Request(
        f"{config.url}/rest/v1/rpc/get_academic_history",
        data=json.dumps({"user_id": rpc_context["user_a"]}).encode(), method="POST",
        headers={"apikey": config.anon_key, "Authorization": f"Bearer {rpc_context['token_b']}",
                 "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            status, payload = response.status, response.read().decode()
    except urllib.error.HTTPError as exc:
        status, payload = exc.code, exc.read().decode()
    assert status in (400, 404), f"el RPC acepto seleccionar otro user_id: HTTP {status}, {payload}"


def _progress(rpc, context, token_key="token_a"):
    status, payload = rpc("get_credit_progress", context[token_key])
    assert status == 200, f"progreso fallo: HTTP {status}, {payload}"
    assert len(payload) == 1
    return payload[0]


def test_failed_course_adds_no_approved_credits(rpc, rpc_context):
    progress = _progress(rpc, rpc_context)
    failed_credits = rpc_context["positions"][0][1]
    approved = progress["verified_approved_credits"] + progress["reported_only_approved_credits"]
    expected = sum(p[1] for p in rpc_context["positions"][1:])
    assert approved == expected
    assert failed_credits > 0


def test_failed_then_passed_counts_course_once(rpc, rpc_context):
    progress = _progress(rpc, rpc_context)
    retaken_credits = rpc_context["positions"][1][1]
    other_verified = rpc_context["positions"][3][1]
    assert progress["verified_approved_credits"] == retaken_credits + other_verified


def test_verified_and_student_reported_credits_are_separate(rpc, rpc_context):
    progress = _progress(rpc, rpc_context)
    assert progress["reported_only_approved_credits"] == rpc_context["positions"][2][1]
    assert progress["verified_approved_credits"] == rpc_context["positions"][1][1] + rpc_context["positions"][3][1]
    assert progress["total_curriculum_credits"] == rpc_context["total_credits"]
    assert sum(progress[k] for k in ("verified_approved_credits", "reported_only_approved_credits",
                                      "pending_or_unverified_credits")) == progress["total_curriculum_credits"]


def _direct_student_request(context, method, path, body):
    config = context["config"]
    request = urllib.request.Request(
        f"{config.url}/rest/v1/{path}", data=json.dumps(body).encode(), method=method,
        headers={"apikey": config.anon_key, "Authorization": f"Bearer {context['token_a']}",
                 "Content-Type": "application/json", "Content-Profile": "student"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode()


def test_student_cannot_modify_grade_directly(rpc_context):
    status, payload = _direct_student_request(
        rpc_context, "PATCH", f"course_attempts?attempt_id=eq.{rpc_context['attempt_id']}", {"final_grade": 5.0})
    assert status in (401, 403, 404, 406), f"modificacion directa no fue rechazada: HTTP {status}, {payload}"


def test_student_cannot_declare_verified_grade(rpc_context):
    position = rpc_context["positions"][0][0]
    body = {"user_id": rpc_context["user_a"], "curriculum_id": rpc_context["curriculum_id"],
            "position_id": position, "attempt_number": 99, "final_grade": 5,
            "outcome": "passed", "source_type": "institution_verified"}
    status, payload = _direct_student_request(rpc_context, "POST", "course_attempts", body)
    assert status in (401, 403, 404, 406), f"declaracion verificada no fue rechazada: HTTP {status}, {payload}"


def test_student_without_history(rpc, rpc_context):
    status_history, history = rpc("get_academic_history", rpc_context["token_b"])
    progress = _progress(rpc, rpc_context, "token_b")
    assert status_history == 200 and history == []
    assert progress["verified_approved_credits"] == 0
    assert progress["reported_only_approved_credits"] == 0
    assert progress["pending_or_unverified_credits"] == progress["total_curriculum_credits"]
