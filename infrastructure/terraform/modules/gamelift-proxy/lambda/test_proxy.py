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


# ---- auth_mode = eos ---------------------------------------------------------------------

CLIENT = "xyza7891clientid"
GOOD = "eg1~good-token-with-enough-length"
OTHER_APP = "eg1~token-from-another-product"
EXPIRED = "eg1~expired-token-00000000000"


def load_eos(monkeypatch, **extra):
    proxy, calls = load(monkeypatch, FLEET_ID=FLEET, AUTH_MODE="eos", EOS_CLIENT_ID=CLIENT, **extra)
    introspections = []

    def fake_introspect(token):
        introspections.append(token)
        if token == GOOD:
            return 200, {"active": True, "client_id": CLIENT, "account_id": "acc0123456789", "expires_in": 7200}
        if token == OTHER_APP:
            return 200, {"active": True, "client_id": "someone-else", "account_id": "acc999", "expires_in": 7200}
        return 200, {"active": False}

    monkeypatch.setattr(proxy, "_introspect_eos_token", fake_introspect)
    return proxy, calls, introspections


def test_eos_requires_bearer(monkeypatch):
    proxy, calls, _ = load_eos(monkeypatch)
    status, body = post(proxy, "GameLift.DescribeGameSessions", {"StatusFilter": "ACTIVE"})
    assert status == 401 and body["__type"] == "UnauthorizedException"
    assert calls == []


@pytest.mark.parametrize("token,why", [(EXPIRED, "rejected"), (OTHER_APP, "different application")])
def test_eos_rejects_bad_tokens(monkeypatch, token, why):
    proxy, calls, _ = load_eos(monkeypatch)
    status, body = post(proxy, "GameLift.DescribeGameSessions", {"StatusFilter": "ACTIVE"}, {"Authorization": f"Bearer {token}"})
    assert status == 401 and why in body["message"]
    assert calls == []


def test_eos_good_token_pins_identity_and_caches(monkeypatch):
    proxy, calls, introspections = load_eos(monkeypatch)
    hdr = {"authorization": f"Bearer {GOOD}"}  # lower-case header name, as HTTP API delivers it
    status, _ = post(proxy, "GameLift.CreateGameSession", {"Name": "A", "MaximumPlayerSessionCount": 4, "CreatorId": "spoofed"}, hdr)
    assert status == 200 and calls[-1][1]["CreatorId"] == "acc0123456789"
    status, _ = post(proxy, "GameLift.CreatePlayerSession", {"GameSessionId": OWN_SESSION, "PlayerId": "spoofed"}, hdr)
    assert status == 200 and calls[-1][1]["PlayerId"] == "acc0123456789"
    assert introspections == [GOOD]  # second call served from cache


def test_none_mode_ignores_bearer(monkeypatch):
    proxy, calls = load(monkeypatch, FLEET_ID=FLEET)
    monkeypatch.setattr(proxy, "_introspect_eos_token", lambda t: (_ for _ in ()).throw(AssertionError("must not introspect")))
    status, _ = post(proxy, "GameLift.CreatePlayerSession", {"GameSessionId": OWN_SESSION, "PlayerId": "client-chosen"}, {"Authorization": "Bearer whatever-token-value"})
    assert status == 200 and calls[-1][1]["PlayerId"] == "client-chosen"
