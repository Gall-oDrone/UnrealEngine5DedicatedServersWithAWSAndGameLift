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

# Player authentication. "none": anyone who knows the URL may call (dev / tutorial).
# "eos": every request must carry `Authorization: Bearer <Epic access token>`; the token is
# introspected with Epic's tokenInfo endpoint and must be active and issued for EOS_CLIENT_ID.
AUTH_MODE = (os.environ.get("AUTH_MODE") or "none").lower()
EOS_CLIENT_ID = os.environ.get("EOS_CLIENT_ID", "")
# Optional: EOS client secret for Basic auth on tokenInfo, read once from SSM (SecureString).
EOS_CLIENT_SECRET_PARAM = os.environ.get("EOS_CLIENT_SECRET_PARAM", "")
EOS_TOKENINFO_URL = "https://api.epicgames.dev/epic/oauth/v2/tokenInfo"
_TOKEN_CACHE = {}  # sha256(token) -> (account_id, expires_epoch)
_TOKEN_CACHE_MAX_SECONDS = 600
_EOS_SECRET = {"value": None}

ALLOWED_TARGETS = {
    "GameLift.CreateGameSession",
    "GameLift.DescribeGameSessions",
    "GameLift.CreatePlayerSession",
}

# Operations that take a fleet/alias and therefore get it pinned from the environment.
FLEET_SCOPED = {"GameLift.CreateGameSession", "GameLift.DescribeGameSessions"}

# Alias -> fleet resolution cache (so an `update-alias` fleet swap is picked up within TTL).
_ALIAS_CACHE = {"fleet_id": "", "expires": 0.0}
_ALIAS_TTL_SECONDS = 300


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


def _call_gamelift(target, payload):
    """Signed POST to GameLift. Returns (status, raw_body)."""
    body = json.dumps(payload, separators=(",", ":"))
    request = urllib.request.Request(ENDPOINT, data=body.encode("utf-8"), method="POST", headers=_sigv4_headers(target, body))
    try:
        with urllib.request.urlopen(request, timeout=10) as resp:
            return resp.status, resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8")


def _pinned_fleet_id():
    """Fleet the proxy is locked to: FLEET_ID directly, or the alias' current target (cached)."""
    if FLEET_ID:
        return FLEET_ID
    if not ALIAS_ID:
        return ""
    import time

    now = time.time()
    if _ALIAS_CACHE["fleet_id"] and now < _ALIAS_CACHE["expires"]:
        return _ALIAS_CACHE["fleet_id"]
    status, raw = _call_gamelift("GameLift.DescribeAlias", {"AliasId": ALIAS_ID})
    if status == 200:
        fleet = (json.loads(raw).get("Alias") or {}).get("RoutingStrategy", {}).get("FleetId", "")
        if fleet:
            _ALIAS_CACHE.update(fleet_id=fleet, expires=now + _ALIAS_TTL_SECONDS)
            return fleet
    # Could not resolve (TERMINAL alias, permissions): fall back to whatever we last knew.
    return _ALIAS_CACHE["fleet_id"]


def _owned_session(session_id, fleet_id):
    # GameLift session ARNs: arn:aws:gamelift:<region>::gamesession/<fleet-id>/<location>/<gsess-id>
    return bool(fleet_id) and f":gamesession/{fleet_id}/" in session_id


def _eos_client_secret():
    """Client secret from SSM (optional). Cached for the life of the execution environment."""
    if _EOS_SECRET["value"] is not None:
        return _EOS_SECRET["value"]
    secret = ""
    if EOS_CLIENT_SECRET_PARAM:
        import boto3  # only imported when configured; stock Lambda runtime ships it

        secret = boto3.client("ssm").get_parameter(Name=EOS_CLIENT_SECRET_PARAM, WithDecryption=True)["Parameter"]["Value"]
    _EOS_SECRET["value"] = secret
    return secret


def _introspect_eos_token(token):
    """POST tokenInfo. Returns (status, dict)."""
    import base64
    import urllib.parse

    headers = {"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"}
    secret = _eos_client_secret()
    if EOS_CLIENT_ID and secret:
        headers["Authorization"] = "Basic " + base64.b64encode(f"{EOS_CLIENT_ID}:{secret}".encode()).decode()
    data = urllib.parse.urlencode({"token": token}).encode("utf-8")
    request = urllib.request.Request(EOS_TOKENINFO_URL, data=data, method="POST", headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=8) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, json.loads(exc.read().decode("utf-8") or "{}")
        except ValueError:
            return exc.code, {}


def _authenticate(headers):
    """Returns (account_id, None) on success or (None, error_response)."""
    import time

    auth = headers.get("authorization", "")
    if not auth.lower().startswith("bearer ") or len(auth) < 16:
        return None, _error(401, "UnauthorizedException", "Sign in to Epic Online Services first (missing bearer token)")
    token = auth[7:].strip()

    key = hashlib.sha256(token.encode("utf-8")).hexdigest()
    now = time.time()
    cached = _TOKEN_CACHE.get(key)
    if cached and now < cached[1]:
        return cached[0], None

    status, info = _introspect_eos_token(token)
    if status != 200 or not info.get("active"):
        return None, _error(401, "UnauthorizedException", f"Epic token rejected (tokenInfo {status}, active={info.get('active')})")
    if EOS_CLIENT_ID and info.get("client_id") != EOS_CLIENT_ID:
        return None, _error(401, "UnauthorizedException", "Epic token was issued for a different application")
    account_id = info.get("account_id") or ""
    if not account_id:
        return None, _error(401, "UnauthorizedException", "Epic token has no account_id (client-credentials token?)")

    ttl = min(int(info.get("expires_in") or 0), _TOKEN_CACHE_MAX_SECONDS)
    if ttl > 0:
        _TOKEN_CACHE[key] = (account_id, now + ttl)
    return account_id, None


def handler(event, _context):
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    target = headers.get("x-amz-target", "")
    if target not in ALLOWED_TARGETS:
        return _error(400, "UnsupportedOperationException", f"Unsupported target: {target or '<none>'}")

    account_id = ""
    if AUTH_MODE == "eos":
        account_id, auth_error = _authenticate(headers)
        if auth_error:
            return auth_error

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

    pinned = ALIAS_ID or FLEET_ID
    owner_fleet = _pinned_fleet_id() if pinned else ""
    if target in FLEET_SCOPED:
        session_id = payload.get("GameSessionId", "")
        if target == "GameLift.DescribeGameSessions" and session_id:
            # Polling one session (client waits for ACTIVATING -> ACTIVE). GameLift accepts
            # exactly one of GameSessionId / FleetId / AliasId, so do not add the fleet; instead
            # make sure the session belongs to the pinned fleet.
            payload.pop("FleetId", None)
            payload.pop("AliasId", None)
            if pinned and not _owned_session(session_id, owner_fleet):
                return _error(400, "InvalidRequestException", "GameSessionId does not belong to this fleet")
        elif pinned:
            # Pin the fleet: shipped clients cannot be pointed at another fleet by editing an ini.
            if ALIAS_ID:
                payload.pop("FleetId", None)
                payload["AliasId"] = ALIAS_ID
            else:
                payload.pop("AliasId", None)
                payload["FleetId"] = FLEET_ID
        if target == "GameLift.CreateGameSession":
            payload["MaximumPlayerSessionCount"] = max(1, min(int(payload.get("MaximumPlayerSessionCount", 8)), 16))
    elif target == "GameLift.CreatePlayerSession" and pinned:
        if not _owned_session(payload.get("GameSessionId", ""), owner_fleet):
            return _error(400, "InvalidRequestException", "GameSessionId does not belong to this fleet")

    if account_id:
        # Identity comes from the verified token, never from the client body.
        if target == "GameLift.CreatePlayerSession":
            payload["PlayerId"] = account_id
        elif target == "GameLift.CreateGameSession":
            payload["CreatorId"] = account_id

    try:
        status, raw = _call_gamelift(target, payload)
        # GameLift errors are forwarded verbatim (status + body with __type / Message).
        return _response(status, raw_body=raw)
    except urllib.error.URLError as exc:
        return _error(502, "ProxyUpstreamException", f"Could not reach GameLift: {exc.reason}")
