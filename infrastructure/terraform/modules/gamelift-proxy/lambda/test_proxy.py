"""
Unit tests for the GameLift client proxy. No network: _call_gamelift is stubbed.

    python3 -m pytest infrastructure/terraform/modules/gamelift-proxy/lambda -q
"""

import importlib
import json
import os
import sys

import pytest

HERE = os.path.dirname(__file__)
FLEET = "fleet-a2a921a0-3c0f-4442-b469-5dc9c43d3792"
ALIAS = "alias-95973f5d-f49e-41b3-9130-459897714054"
OWN_SESSION = f"arn:aws:gamelift:us-east-1::gamesession/{FLEET}/custom-frontendui-dev/gsess-1"
FOREIGN_SESSION = "arn:aws:gamelift:us-east-1::gamesession/fleet-other/custom-x/gsess-2"


def load(monkeypatch, **env):
    for k in ("FLEET_ID", "ALIAS_ID"):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "AKIATEST")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "secret")
    for k, v in env.items():
        monkeypatch.setenv(k, v)
    sys.path.insert(0, HERE)
    import proxy

    proxy = importlib.reload(proxy)
    calls = []

    def fake_call(target, payload):
        calls.append((target, payload))
        if target == "GameLift.DescribeAlias":
            return 200, json.dumps({"Alias": {"AliasId": ALIAS, "RoutingStrategy": {"Type": "SIMPLE", "FleetId": FLEET}}})
        if target == "GameLift.CreateGameSession" and payload.get("Name") == "full":
            return 400, json.dumps({"__type": "FleetCapacityExceededException", "Message": "Unable to reserve a process"})
        return 200, json.dumps({"ok": True, "echo": payload})

    monkeypatch.setattr(proxy, "_call_gamelift", fake_call)
    return proxy, calls


def post(proxy, target, payload, headers=None):
    event = {"headers": {"x-amz-target": target, **(headers or {})}, "body": json.dumps(payload)}
    resp = proxy.handler(event, None)
    return resp["statusCode"], json.loads(resp["body"])


def test_rejects_unknown_target(monkeypatch):
    proxy, calls = load(monkeypatch, FLEET_ID=FLEET)
    status, body = post(proxy, "GameLift.DeleteFleet", {})
    assert status == 400 and body["__type"] == "UnsupportedOperationException"
    assert calls == []


def test_rejects_bad_json(monkeypatch):
    proxy, _ = load(monkeypatch, FLEET_ID=FLEET)
    resp = proxy.handler({"headers": {"x-amz-target": "GameLift.DescribeGameSessions"}, "body": "nope"}, None)
    assert resp["statusCode"] == 400 and json.loads(resp["body"])["__type"] == "SerializationException"


def test_pins_fleet_and_clamps_players(monkeypatch):
    proxy, calls = load(monkeypatch, FLEET_ID=FLEET)
    status, _ = post(proxy, "GameLift.CreateGameSession", {"Name": "A", "MaximumPlayerSessionCount": 99, "FleetId": "fleet-bogus", "AliasId": "alias-bogus"})
    assert status == 200
    sent = calls[-1][1]
    assert sent["FleetId"] == FLEET and "AliasId" not in sent and sent["MaximumPlayerSessionCount"] == 16


def test_pins_alias_when_configured(monkeypatch):
    proxy, calls = load(monkeypatch, ALIAS_ID=ALIAS)
    post(proxy, "GameLift.DescribeGameSessions", {"FleetId": "fleet-bogus", "StatusFilter": "ACTIVE"})
    sent = [c for c in calls if c[0] == "GameLift.DescribeGameSessions"][-1][1]
    assert sent["AliasId"] == ALIAS and "FleetId" not in sent


def test_describe_by_session_id_has_no_fleet(monkeypatch):
    """Client polls ACTIVATING sessions by id; GameLift accepts exactly one of GameSessionId/FleetId/AliasId."""
    proxy, calls = load(monkeypatch, FLEET_ID=FLEET)
    status, _ = post(proxy, "GameLift.DescribeGameSessions", {"GameSessionId": OWN_SESSION, "FleetId": FLEET})
    assert status == 200
    sent = calls[-1][1]
    assert sent == {"GameSessionId": OWN_SESSION}


@pytest.mark.parametrize("env", [{"FLEET_ID": FLEET}, {"ALIAS_ID": ALIAS}])
def test_foreign_session_rejected(monkeypatch, env):
    proxy, calls = load(monkeypatch, **env)
    status, body = post(proxy, "GameLift.DescribeGameSessions", {"GameSessionId": FOREIGN_SESSION})
    assert status == 400 and "does not belong" in body["message"]
    status, body = post(proxy, "GameLift.CreatePlayerSession", {"GameSessionId": FOREIGN_SESSION, "PlayerId": "p"})
    assert status == 400 and "does not belong" in body["message"]
    assert not [c for c in calls if c[0] == "GameLift.CreatePlayerSession"]


def test_own_session_allowed_via_alias(monkeypatch):
    proxy, calls = load(monkeypatch, ALIAS_ID=ALIAS)
    status, _ = post(proxy, "GameLift.CreatePlayerSession", {"GameSessionId": OWN_SESSION, "PlayerId": "p"})
    assert status == 200
    # alias resolved once, then cached
    post(proxy, "GameLift.CreatePlayerSession", {"GameSessionId": OWN_SESSION, "PlayerId": "q"})
    assert len([c for c in calls if c[0] == "GameLift.DescribeAlias"]) == 1


def test_gamelift_error_forwarded_verbatim(monkeypatch):
    proxy, _ = load(monkeypatch, FLEET_ID=FLEET)
    status, body = post(proxy, "GameLift.CreateGameSession", {"Name": "full", "MaximumPlayerSessionCount": 4})
    assert status == 400
    assert body["__type"] == "FleetCapacityExceededException"  # the client's retry loop keys on this


def test_no_pin_passes_client_fleet_through(monkeypatch):
    proxy, calls = load(monkeypatch)
    post(proxy, "GameLift.CreateGameSession", {"Name": "A", "FleetId": "fleet-client", "MaximumPlayerSessionCount": 2})
    assert calls[-1][1]["FleetId"] == "fleet-client"


def test_sigv4_headers_shape(monkeypatch):
    proxy, _ = load(monkeypatch, FLEET_ID=FLEET)
    h = proxy._sigv4_headers("GameLift.DescribeGameSessions", "{}")
    assert h["Authorization"].startswith("AWS4-HMAC-SHA256 Credential=AKIATEST/")
    assert "/us-east-1/gamelift/aws4_request" in h["Authorization"]
    assert "SignedHeaders=content-type;host;x-amz-date;x-amz-target" in h["Authorization"]
