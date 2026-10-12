"""Register a tenant with the shared Realtime and Supavisor services.

Both management APIs authenticate with an HS256 JWT signed by the shared
API_JWT_SECRET. Upserts are idempotent, so the job is safe to re-run.
Exits non-zero on failure so `terraform apply` fails loudly.
"""
import base64
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.request

env = os.environ


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def admin_jwt() -> str:
    now = int(time.time())
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"role": "service_role", "iss": "staticbot", "iat": now, "exp": now + 600}).encode())
    signature = hmac.new(env["SHARED_API_JWT_SECRET"].encode(), f"{header}.{payload}".encode(), hashlib.sha256).digest()
    return f"{header}.{payload}.{b64url(signature)}"


def request(method: str, url: str, body: dict | None = None) -> tuple[int, str]:
    req = urllib.request.Request(
        url,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {admin_jwt()}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def with_retries(name: str, fn, attempts: int = 30, delay: float = 5.0):
    for attempt in range(1, attempts + 1):
        try:
            status, body = fn()
        except (urllib.error.URLError, ConnectionError, TimeoutError) as e:
            status, body = 0, str(e)
        if 200 <= status < 300:
            print(f"{name}: OK (HTTP {status})")
            return body
        print(f"{name}: attempt {attempt} got HTTP {status}: {body[:300]}", file=sys.stderr)
        time.sleep(delay)
    sys.exit(f"{name}: giving up")


tenant_id = env["TENANT_ID"]
db = {
    "db_host": env["TENANT_DB_HOST"],
    "db_port": env.get("TENANT_DB_PORT", "5432"),
    "db_name": env.get("TENANT_DB_NAME", "postgres"),
}

realtime_url = env["REALTIME_URL"].rstrip("/")
realtime_tenant = {
    "tenant": {
        "external_id": tenant_id,
        "name": tenant_id,
        "jwt_secret": env["TENANT_JWT_SECRET"],
        **({"jwt_jwks": json.loads(env["TENANT_JWT_JWKS"])} if env.get("TENANT_JWT_JWKS") else {}),
        "extensions": [{
            "type": "postgres_cdc_rls",
            "settings": {
                **db,
                "db_user": "supabase_admin",
                "db_password": env["TENANT_DB_PASSWORD"],
                "region": "local",
                "poll_interval_ms": 100,
                "poll_max_record_bytes": 1048576,
                "ssl_enforced": False,
            },
        }],
    }
}


def upsert_realtime():
    status, body = request("GET", f"{realtime_url}/api/tenants/{tenant_id}")
    if status == 200:
        return request("PUT", f"{realtime_url}/api/tenants/{tenant_id}", realtime_tenant)
    return request("POST", f"{realtime_url}/api/tenants", realtime_tenant)


supavisor_url = env["SUPAVISOR_URL"].rstrip("/")
supavisor_tenant = {
    "tenant": {
        "external_id": tenant_id,
        "db_host": db["db_host"],
        "db_port": int(db["db_port"]),
        "db_database": db["db_name"],
        "ip_version": "auto",
        "require_user": False,
        "auth_query": "SELECT * FROM pgbouncer.get_auth($1)",
        "default_max_clients": int(env.get("POOLER_MAX_CLIENT_CONN", "100")),
        "default_pool_size": int(env.get("POOLER_DEFAULT_POOL_SIZE", "15")),
        "users": [{
            "db_user": "pgbouncer",
            "db_password": env["TENANT_DB_PASSWORD"],
            "mode_type": "transaction",
            "pool_size": int(env.get("POOLER_DEFAULT_POOL_SIZE", "15")),
            "is_manager": True,
        }],
    }
}

with_retries("Realtime tenant", upsert_realtime)
with_retries("Supavisor tenant", lambda: request("PUT", f"{supavisor_url}/api/tenants/{tenant_id}", supavisor_tenant))
