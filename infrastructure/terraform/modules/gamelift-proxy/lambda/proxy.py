"""
GameLift client-API proxy for Shipping builds of the FrontendUI project.

The game client (UFrontendSessionBackend_GameLift) POSTs the same JSON it would send to
GameLift directly, with the X-Amz-Target header naming the operation. This function
forwards the request to GameLift signed with the Lambda's own role (SigV4) and returns
GameLift's body and status code UNCHANGED, so the client keeps seeing the real error
"__type" (e.g. FleetCapacityExceededException drives its capacity-retry loop).

Only the three player-facing operations are allowed. Fleet / alias come from the
environment (FLEET_ID / ALIAS_ID): if set, the proxy forces them onto every request so a
shipped client cannot target someone else's fleet.

No third-party dependencies: urllib + the SigV4 recipe from the AWS docs.
"""

import datetime
import hashlib
import hmac
import json
import os
import urllib.error
import urllib.request

REGION = os.environ.get("GAMELIFT_REGION") or os.environ.get("AWS_REGION", "us-east-1")
FLEET_ID = os.environ.get("FLEET_ID", "")
ALIAS_ID = os.environ.get("ALIAS_ID", "")
HOST = f"gamelift.{REGION}.amazonaws.com"
ENDPOINT = f"https://{HOST}/"

ALLOWED_TARGETS = {
    "GameLift.CreateGameSession",
    "GameLift.DescribeGameSessions",
    "GameLift.CreatePlayerSession",
}

# Operations that take a fleet/alias and therefore get it pinned from the environment.
FLEET_SCOPED = {"GameLift.CreateGameSession", "GameLift.DescribeGameSessions"}


def _sign(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def _signing_key(secret, date_stamp, region, service):
    k_date = _sign(("AWS4" + secret).encode("utf-8"), date_stamp)
    k_region = _sign(k_date, region)
    k_service = _sign(k_region, service)
    return _sign(k_service, "aws4_request")


def _sigv4_headers(target, body):
    access_key = os.environ["AWS_ACCESS_KEY_ID"]
    secret_key = os.environ["AWS_SECRET_ACCESS_KEY"]
    session_token = os.environ.get("AWS_SESSION_TOKEN", "")

    now = datetime.datetime.now(datetime.timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")
    content_type = "application/x-amz-json-1.1"
    payload_hash = hashlib.sha256(body.encode("utf-8")).hexdigest()

    canonical_headers = f"content-type:{content_type}\nhost:{HOST}\nx-amz-date:{amz_date}\n"
    signed_headers = "content-type;host;x-amz-date"
    if session_token:
        canonical_headers += f"x-amz-security-token:{session_token}\n"
        signed_headers += ";x-amz-security-token"
    canonical_headers += f"x-amz-target:{target}\n"
    signed_headers += ";x-amz-target"

    canonical_request = f"POST\n/\n\n{canonical_headers}\n{signed_headers}\n{payload_hash}"
    scope = f"{date_stamp}/{REGION}/gamelift/aws4_request"
    string_to_sign = "AWS4-HMAC-SHA256\n{}\n{}\n{}".format(
        amz_date, scope, hashlib.sha256(canonical_request.encode("utf-8")).hexdigest()
    )
    signature = hmac.new(
        _signing_key(secret_key, date_stamp, REGION, "gamelift"),
        string_to_sign.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    headers = {
        "Content-Type": content_type,
        "X-Amz-Date": amz_date,
        "X-Amz-Target": target,
        "Authorization": (
            f"AWS4-HMAC-SHA256 Credential={access_key}/{scope}, "
            f"SignedHeaders={signed_headers}, Signature={signature}"
        ),
    }
    if session_token:
        headers["X-Amz-Security-Token"] = session_token
    return headers


def _response(status, body_obj=None, raw_body=None):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/x-amz-json-1.1"},
        "body": raw_body if raw_body is not None else json.dumps(body_obj),
    }


def _error(status, error_type, message):
    # Same shape GameLift uses, so the client's error parsing works for proxy errors too.
    return _response(status, {"__type": error_type, "message": message})


def handler(event, _context):
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    target = headers.get("x-amz-target", "")
    if target not in ALLOWED_TARGETS:
        return _error(400, "UnsupportedOperationException", f"Unsupported target: {target or '<none>'}")

    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        import base64

        raw = base64.b64decode(raw).decode("utf-8")
    try:
        payload = json.loads(raw) if raw.strip() else {}
        if not isinstance(payload, dict):
            raise ValueError("payload must be a JSON object")
    except ValueError as exc:
        return _error(400, "SerializationException", f"Invalid JSON body: {exc}")

    if target in FLEET_SCOPED:
        # Pin the fleet: shipped clients cannot be pointed at another fleet by editing an ini.
        if ALIAS_ID:
            payload.pop("FleetId", None)
            payload["AliasId"] = ALIAS_ID
        elif FLEET_ID:
            payload.pop("AliasId", None)
            payload["FleetId"] = FLEET_ID
        if target == "GameLift.CreateGameSession":
            payload["MaximumPlayerSessionCount"] = max(1, min(int(payload.get("MaximumPlayerSessionCount", 8)), 16))

    body = json.dumps(payload, separators=(",", ":"))
    request = urllib.request.Request(ENDPOINT, data=body.encode("utf-8"), method="POST", headers=_sigv4_headers(target, body))
    try:
        with urllib.request.urlopen(request, timeout=10) as resp:
            return _response(resp.status, raw_body=resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        # GameLift error: forward status + body verbatim (__type, message).
        return _response(exc.code, raw_body=exc.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        return _error(502, "ProxyUpstreamException", f"Could not reach GameLift: {exc.reason}")
