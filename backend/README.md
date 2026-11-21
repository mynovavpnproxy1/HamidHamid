# Backend

FastAPI API plus a separate authenticated owner dashboard at `/admin`. The database begins empty: no sample or presumed-working VPN servers are inserted.

## Local run

Python 3.12 is recommended. From `backend/`:

```sh
python -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Edit `.env`: set a unique administrator password (at least 16 characters) and a randomly generated `JWT_SECRET` (at least 32 random characters). Then run `set -a; . ./.env; set +a; uvicorn app.main:app --reload` on macOS/Linux. For PowerShell, set the environment variables separately. Never use the example values in a deployment.

The local dashboard is `http://127.0.0.1:8000/admin`; do not expose this development server to the public internet. `docker compose up --build` runs the container bound to loopback; put a properly configured HTTPS reverse proxy in front for any remote use.

Run backend tests from this directory with `pytest -q`.

## API

- `POST /api/v1/admin/login` — obtain a short-lived admin bearer token.
- `GET /api/v1/admin/servers` — authenticated list (no raw configurations).
- `POST /api/v1/admin/servers` — authenticated create.
- `GET /api/v1/admin/servers/{id}` — authenticated detail (includes raw configuration for owner editing).
- `PUT /api/v1/admin/servers/{id}` — authenticated update / configuration rotation.
- `DELETE /api/v1/admin/servers/{id}` — authenticated delete.
- `GET /api/v1/servers` — active server metadata only.
- `POST /api/v1/client/register` — register a device ID. New devices are saved as pending and receive HTTP 403 until approved.
- `GET /api/v1/admin/devices` — authenticated list of registered devices.
- `PUT /api/v1/admin/devices/{device_id}` — authenticated approve or revoke a device.
- `GET /api/v1/servers/{id}/config` — returns a profile only to a device holding a valid, short-lived client token and currently approved by the administrator. Missing/invalid tokens receive HTTP 401; unapproved devices receive HTTP 403. Responses are marked `no-store`.

Country metadata is shown to app clients only when the owner explicitly marks it verified. This is an administrative assertion, not automated IP geolocation. No ping, health, traffic, or user-count metrics are implemented or displayed. Protocol/profile format checks are syntactic and do not establish that a server is reachable or operational.

## Production blockers

Device approval is now implemented as a minimal owner-controlled access gate; it is not a complete paid-subscription or identity system. Before public launch, add stronger abuse controls and rate limiting at the reverse proxy, database backups and migrations, monitoring without secret logging, and independent security review. Configure the app with the deployed HTTPS API URL using `--dart-define=API_BASE_URL=...`. Never embed administrator credentials or a shared API secret in the APK. A profile delivered to a device can be extracted from that device. Configure HTTPS, secure backups, and credential rotation. SQLite is suitable only for a small single-instance deployment; use a managed database and migrations for scale.
