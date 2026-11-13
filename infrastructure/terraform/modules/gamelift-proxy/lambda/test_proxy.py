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
    for k in ("FLEET_ID", "ALIAS_ID", "QUEUE_NAME", "AUTH_MODE", "EOS_CLIENT_ID", "LEADERBOARD_TABLE", "LEADERBOARD_INDEX", "LEADERBOARD_BOARDS"):
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


# ---- game session placement --------------------------------------------------------------

def test_placement_pins_queue_and_identity(monkeypatch):
    proxy, calls, _ = load_eos(monkeypatch, QUEUE_NAME="frontendui-dev")
    hdr = {"authorization": f"Bearer {GOOD}"}
    body = {"PlacementId": "p-1", "GameSessionQueueName": "evil-queue", "MaximumPlayerSessionCount": 99,
            "DesiredPlayerSessions": [{"PlayerId": "spoofed"}]}
    status, _ = post(proxy, "GameLift.StartGameSessionPlacement", body, hdr)
    assert status == 200
    sent = calls[-1][1]
    assert sent["GameSessionQueueName"] == "frontendui-dev"
    assert sent["MaximumPlayerSessionCount"] == 16
    assert sent["DesiredPlayerSessions"] == [{"PlayerId": "acc0123456789"}]
    status, _ = post(proxy, "GameLift.DescribeGameSessionPlacement", {"PlacementId": "p-1"}, hdr)
    assert status == 200 and calls[-1][1] == {"PlacementId": "p-1"}


def test_placement_rejects_extra_players(monkeypatch):
    proxy, calls = load(monkeypatch, QUEUE_NAME="frontendui-dev")
    status, body = post(proxy, "GameLift.StartGameSessionPlacement",
                        {"PlacementId": "p-2", "DesiredPlayerSessions": [{"PlayerId": "a"}, {"PlayerId": "b"}]})
    assert status == 400 and "Only the requesting player" in body["message"]
    assert calls == []


def test_stop_placement_passes_through(monkeypatch):
    """A client abandoning a PENDING placement cancels it; only its own PlacementId travels."""
    proxy, calls = load(monkeypatch, ALIAS_ID=ALIAS, QUEUE_NAME="frontendui-dev")
    status, _ = post(proxy, "GameLift.StopGameSessionPlacement", {"PlacementId": "p-3"})
    assert status == 200
    assert calls[-1] == ("GameLift.StopGameSessionPlacement", {"PlacementId": "p-3"})


def test_stop_placement_still_needs_identity_in_eos_mode(monkeypatch):
    proxy, calls, _ = load_eos(monkeypatch, QUEUE_NAME="frontendui-dev")
    status, body = post(proxy, "GameLift.StopGameSessionPlacement", {"PlacementId": "p-4"})
    assert status == 401 and body["__type"] == "UnauthorizedException"
    assert calls == []
    status, _ = post(proxy, "GameLift.StopGameSessionPlacement", {"PlacementId": "p-4"}, {"authorization": f"Bearer {GOOD}"})
    assert status == 200 and calls[-1][1] == {"PlacementId": "p-4"}


def test_allow_list_is_exactly_the_player_facing_set(monkeypatch):
    proxy, _ = load(monkeypatch, FLEET_ID=FLEET)
    assert proxy.ALLOWED_TARGETS == {
        "GameLift.CreateGameSession",
        "GameLift.DescribeGameSessions",
        "GameLift.CreatePlayerSession",
        "GameLift.StartGameSessionPlacement",
        "GameLift.DescribeGameSessionPlacement",
        "GameLift.StopGameSessionPlacement",
    }


# ---- leaderboard (DynamoDB stubbed) ------------------------------------------------------

TABLE = "frontendui-leaderboard"
ME = "acc0123456789"  # the account behind GOOD (see load_eos)


def item(player_id, name, score):
    return {"PlayerId": {"S": player_id}, "DisplayName": {"S": name}, "Score": {"N": str(score)}}


def fake_dynamodb(monkeypatch, proxy, rows, count_pages=None, fail=None):
    """rows: (player_id, name, score) in any order. Answers Query (top / COUNT) and GetItem."""
    ddb = []
    by_score = sorted(rows, key=lambda r: -r[2])
    pages = list(count_pages or [])

    def call(operation, payload):
        ddb.append((operation, payload))
        if fail and operation == fail[0]:
            return fail[1], {"__type": "com.amazonaws.dynamodb.v20120810#AccessDeniedException", "Message": "secret table arn"}
        if operation == "Query" and payload.get("Select") == "COUNT":
            if pages:
                count, more = pages.pop(0)
                return 200, {"Count": count, **({"LastEvaluatedKey": {"Board": {"S": "Main"}}} if more else {})}
            floor = float(payload["ExpressionAttributeValues"][":s"]["N"])
            return 200, {"Count": sum(1 for r in rows if r[2] > floor)}
        if operation == "Query":
            return 200, {"Items": [item(*r) for r in by_score[: payload["Limit"]]]}
        if operation == "GetItem":
            wanted = payload["Key"]["PlayerId"]["S"]
            found = [r for r in rows if r[0] == wanted]
            return 200, ({"Item": item(*found[0])} if found else {})
        raise AssertionError(f"unexpected DynamoDB operation {operation}")

    monkeypatch.setattr(proxy, "_call_dynamodb", call)
    return ddb


BOARD = [("p1", "Valkyrie", 900), ("p2", "Ronin", 700), ("p3", "Cinder", 700), ("p4", "Specter", 400), (ME, "Dgallo", 150)]


def test_leaderboard_unsupported_without_table(monkeypatch):
    proxy, calls = load(monkeypatch, FLEET_ID=FLEET)
    ddb = fake_dynamodb(monkeypatch, proxy, BOARD)
    status, body = post(proxy, "Leaderboard.GetTop", {"Board": "Main"})
    assert status == 400 and body["__type"] == "UnsupportedOperationException"
    assert ddb == [] and calls == []


def test_leaderboard_needs_identity_in_eos_mode(monkeypatch):
    proxy, calls, _ = load_eos(monkeypatch, LEADERBOARD_TABLE=TABLE)
    ddb = fake_dynamodb(monkeypatch, proxy, BOARD)
    status, body = post(proxy, "Leaderboard.GetTop", {"Board": "Main"})
    assert status == 401 and body["__type"] == "UnauthorizedException"
    assert ddb == [] and calls == []


def test_leaderboard_top_rows_ranked_and_anonymous(monkeypatch):
    proxy, calls = load(monkeypatch, FLEET_ID=FLEET, LEADERBOARD_TABLE=TABLE)
    ddb = fake_dynamodb(monkeypatch, proxy, BOARD)
    status, body = post(proxy, "Leaderboard.GetTop", {"Board": "Main", "Limit": 4})
    assert status == 200 and body["Board"] == "Main" and body["Caller"] is None
    # competition ranking: the two 700s share rank 2, the next row is 4
    assert [(e["Rank"], e["DisplayName"], e["Score"]) for e in body["Entries"]] == [
        (1, "Valkyrie", 900), (2, "Ronin", 700), (2, "Cinder", 700), (4, "Specter", 400)]
    assert "PlayerId" not in json.dumps(body)  # ids never leave the proxy
    assert calls == []  # nothing goes to GameLift
    (operation, query), = ddb  # no caller -> exactly one read
    assert operation == "Query" and query["TableName"] == TABLE and query["IndexName"] == "ByScore"
    assert query["ScanIndexForward"] is False and query["Limit"] == 4


@pytest.mark.parametrize("limit,sent", [(1000, 100), (0, 1), (-5, 1), ("7", 7), (None, 50)])
def test_leaderboard_limit_is_clamped(monkeypatch, limit, sent):
    proxy, _ = load(monkeypatch, LEADERBOARD_TABLE=TABLE)
    ddb = fake_dynamodb(monkeypatch, proxy, BOARD)
    payload = {"Board": "Main"} if limit is None else {"Board": "Main", "Limit": limit}
    status, _ = post(proxy, "Leaderboard.GetTop", payload)
    assert status == 200 and ddb[0][1]["Limit"] == sent


@pytest.mark.parametrize("payload,why", [({"Board": "Main", "Limit": "lots"}, "Limit"), ({"Board": "Hidden"}, "Unknown leaderboard"), ({"Board": ["Main"]}, "Unknown leaderboard")])
def test_leaderboard_rejects_bad_requests(monkeypatch, payload, why):
    proxy, _ = load(monkeypatch, LEADERBOARD_TABLE=TABLE)
    ddb = fake_dynamodb(monkeypatch, proxy, BOARD)
    status, body = post(proxy, "Leaderboard.GetTop", payload)
    assert status == 400 and body["__type"] == "InvalidRequestException" and why in body["message"]
    assert ddb == []


def test_leaderboard_boards_come_from_the_environment(monkeypatch):
    proxy, _ = load(monkeypatch, LEADERBOARD_TABLE=TABLE, LEADERBOARD_BOARDS="Main, Ranked")
    ddb = fake_dynamodb(monkeypatch, proxy, [])
    status, body = post(proxy, "Leaderboard.GetTop", {"Board": "Ranked"})
    assert status == 200 and body == {"Board": "Ranked", "Entries": [], "Caller": None}
    assert ddb[0][1]["ExpressionAttributeValues"] == {":b": {"S": "Ranked"}}


def test_leaderboard_marks_the_verified_caller_in_the_list(monkeypatch):
    proxy, _, _ = load_eos(monkeypatch, LEADERBOARD_TABLE=TABLE)
    ddb = fake_dynamodb(monkeypatch, proxy, BOARD)
    # the body names someone else: identity comes from the token, never from the client
    status, body = post(proxy, "Leaderboard.GetTop", {"Board": "Main", "Limit": 10, "PlayerId": "p1"}, {"authorization": f"Bearer {GOOD}"})
    assert status == 200
    flagged = [e for e in body["Entries"] if e.get("IsCaller")]
    assert flagged == [{"DisplayName": "Dgallo", "Score": 150, "Rank": 5, "IsCaller": True}]
    assert body["Caller"] == flagged[0]
    assert [op for op, _ in ddb] == ["Query"]  # found in the list: no extra reads


def test_leaderboard_caller_below_the_cut_gets_a_real_rank(monkeypatch):
    proxy, _, _ = load_eos(monkeypatch, LEADERBOARD_TABLE=TABLE)
    ddb = fake_dynamodb(monkeypatch, proxy, BOARD)
    status, body = post(proxy, "Leaderboard.GetTop", {"Board": "Main", "Limit": 2}, {"authorization": f"Bearer {GOOD}"})
    assert status == 200 and len(body["Entries"]) == 2 and not any(e.get("IsCaller") for e in body["Entries"])
    assert body["Caller"] == {"DisplayName": "Dgallo", "Score": 150, "Rank": 5, "IsCaller": True}
    assert [op for op, _ in ddb] == ["Query", "GetItem", "Query"]
    assert ddb[1][1]["Key"] == {"Board": {"S": "Main"}, "PlayerId": {"S": ME}}
    count = ddb[2][1]
    assert count["Select"] == "COUNT" and count["ExpressionAttributeValues"][":s"] == {"N": "150"}


def test_leaderboard_rank_count_follows_pages_and_admits_its_limit(monkeypatch):
    proxy, _, _ = load_eos(monkeypatch, LEADERBOARD_TABLE=TABLE)
    ddb = fake_dynamodb(monkeypatch, proxy, BOARD, count_pages=[(9000, True), (3000, False)])
    _, body = post(proxy, "Leaderboard.GetTop", {"Limit": 1}, {"authorization": f"Bearer {GOOD}"})
    assert body["Caller"]["Rank"] == 12001 and "RankIsLowerBound" not in body["Caller"]
    assert "ExclusiveStartKey" in ddb[-1][1]

    ddb = fake_dynamodb(monkeypatch, proxy, BOARD, count_pages=[(10000, True)] * 20)
    _, body = post(proxy, "Leaderboard.GetTop", {"Limit": 1}, {"authorization": f"Bearer {GOOD}"})
    pages = proxy._RANK_COUNT_MAX_PAGES
    assert body["Caller"]["Rank"] == pages * 10000 + 1 and body["Caller"]["RankIsLowerBound"] is True
    assert sum(1 for op, q in ddb if q.get("Select") == "COUNT") == pages


def test_leaderboard_caller_without_a_score(monkeypatch):
    proxy, _, _ = load_eos(monkeypatch, LEADERBOARD_TABLE=TABLE)
    ddb = fake_dynamodb(monkeypatch, proxy, BOARD[:4])
    status, body = post(proxy, "Leaderboard.GetTop", {"Limit": 10}, {"authorization": f"Bearer {GOOD}"})
    assert status == 200 and body["Caller"] is None and len(body["Entries"]) == 4
    assert [op for op, _ in ddb] == ["Query", "GetItem"]


def test_leaderboard_none_mode_takes_the_highlight_hint_from_the_body(monkeypatch):
    proxy, _ = load(monkeypatch, LEADERBOARD_TABLE=TABLE)
    fake_dynamodb(monkeypatch, proxy, BOARD)
    _, body = post(proxy, "Leaderboard.GetTop", {"Limit": 10, "PlayerId": "p3"})
    assert [e["DisplayName"] for e in body["Entries"] if e.get("IsCaller")] == ["Cinder"]
    _, body = post(proxy, "Leaderboard.GetTop", {"Limit": 10, "PlayerId": {"not": "a string"}})
    assert body["Caller"] is None


def test_leaderboard_storage_errors_stay_in_the_log(monkeypatch):
    proxy, _ = load(monkeypatch, LEADERBOARD_TABLE=TABLE)
    fake_dynamodb(monkeypatch, proxy, BOARD, fail=("Query", 400))
    status, body = post(proxy, "Leaderboard.GetTop", {"Board": "Main"})
    assert status == 502 and body["__type"] == "LeaderboardUnavailableException"
    assert "secret table arn" not in json.dumps(body) and TABLE not in json.dumps(body)


def test_leaderboard_survives_a_failed_caller_lookup(monkeypatch):
    proxy, _, _ = load_eos(monkeypatch, LEADERBOARD_TABLE=TABLE)
    fake_dynamodb(monkeypatch, proxy, BOARD, fail=("GetItem", 500))
    status, body = post(proxy, "Leaderboard.GetTop", {"Limit": 2}, {"authorization": f"Bearer {GOOD}"})
    assert status == 200 and len(body["Entries"]) == 2 and body["Caller"] is None


def test_leaderboard_rows_are_sanitised(monkeypatch):
    proxy, _ = load(monkeypatch, LEADERBOARD_TABLE=TABLE)
    rows = [("a", "N" * 80, 10**12), ("b", "   ", 12.9), ("c", "Low", -(10**12))]
    fake_dynamodb(monkeypatch, proxy, rows)
    _, body = post(proxy, "Leaderboard.GetTop", {"Limit": 10})
    top, middle, bottom = body["Entries"]
    assert top["Score"] == 2**31 - 1 and len(top["DisplayName"]) == 32
    assert middle == {"DisplayName": "Player", "Score": 12, "Rank": 2}
    assert bottom["Score"] == -(2**31 - 1)


def test_dynamodb_requests_are_signed_for_dynamodb(monkeypatch):
    proxy, _ = load(monkeypatch, LEADERBOARD_TABLE=TABLE)
    h = proxy._sigv4_headers("DynamoDB_20120810.Query", "{}", service="dynamodb", host="dynamodb.us-east-1.amazonaws.com",
                             region="us-east-1", content_type="application/x-amz-json-1.0")
    assert "/us-east-1/dynamodb/aws4_request" in h["Authorization"]
    assert h["Content-Type"] == "application/x-amz-json-1.0" and h["X-Amz-Target"] == "DynamoDB_20120810.Query"
