from __future__ import annotations

import os
import re
from urllib.parse import quote

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Response


VOX_BASE_URL = "https://api.vox-vpn.com/partner/v1"
VOX_TIMEOUT_SECONDS = 15.0
LOCATION_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")


class VoxAPIError(Exception):
    def __init__(self, status_code: int, detail: str):
        self.status_code = status_code
        self.detail = detail
        super().__init__(f"Vox API returned {status_code}: {detail}")


class VoxClient:
    """Server-side Vox partner API client. Never log keys or returned configs."""

    def __init__(self, api_key: str | None = None, *, http_client=None):
        self.api_key = (api_key if api_key is not None else os.getenv("VOX_API_KEY", "")).strip()
        self.http_client = http_client

    def _request(self, method: str, path: str, *, params=None, json_body=None) -> dict:
        if not self.api_key:
            raise HTTPException(
                status_code=503,
                detail="Vox integration is not configured",
            )
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Accept": "application/json",
            "X-Vox-API-Version": "1.7.0",
        }
        try:
            if self.http_client is None:
                response = httpx.request(
                    method,
                    f"{VOX_BASE_URL}{path}",
                    headers=headers,
                    params=params,
                    json=json_body,
                    timeout=VOX_TIMEOUT_SECONDS,
                )
            else:
                response = self.http_client.request(
                    method,
                    f"{VOX_BASE_URL}{path}",
                    headers=headers,
                    params=params,
                    json=json_body,
                )
        except httpx.TimeoutException as exc:
            raise HTTPException(status_code=504, detail="Vox API timed out") from exc
        except httpx.HTTPError as exc:
            raise HTTPException(status_code=502, detail="Vox API is temporarily unreachable") from exc

        if response.status_code == 429:
            raise HTTPException(status_code=503, detail="Vox API rate limit reached; retry shortly")
        if response.status_code >= 500:
            raise HTTPException(status_code=503, detail="Vox API is temporarily unavailable")
        if response.status_code >= 400:
            # Do not forward arbitrary upstream response bodies to mobile clients.
            raise HTTPException(status_code=502, detail=f"Vox API rejected the request ({response.status_code})")
        try:
            payload = response.json()
        except ValueError as exc:
            raise HTTPException(status_code=502, detail="Vox API returned an invalid response") from exc
        if not isinstance(payload, dict):
            raise HTTPException(status_code=502, detail="Vox API returned an invalid response")
        return payload

    @staticmethod
    def external_id(device_id: str) -> str:
        # One Vox account per NOVA installation/device identity (stable across app launches).
        return f"nova_{device_id}"

    def ensure_user(self, external_id: str) -> dict:
        payload = self._request(
            "POST",
            "/users",
            json_body={"external_id": external_id, "label": "NOVA VPN"},
        )
        user = payload.get("user")
        if not isinstance(user, dict):
            raise HTTPException(status_code=502, detail="Vox API did not return a user")
        return user

    def locations(self, protocol: str = "vless") -> dict:
        payload = self._request("GET", "/locations", params={"protocol": protocol})
        locations = payload.get("locations")
        if not isinstance(locations, list):
            raise HTTPException(status_code=502, detail="Vox API returned an invalid locations list")
        return {"locations": locations}

    def config(self, external_id: str, location: str, protocol: str, device: int = 1) -> dict:
        self.ensure_user(external_id)
        path = f"/users/{quote(external_id, safe='')}/config"
        payload = self._request(
            "GET",
            path,
            params={"location": location, "protocol": protocol, "device": device},
        )
        if not isinstance(payload.get("config"), str) or not payload["config"]:
            raise HTTPException(status_code=502, detail="Vox API did not return a usable configuration")
        return payload


def install_vox_routes(app, *, require_client):
    router = APIRouter()
    vox = VoxClient()

    @router.get("/api/v1/vox/locations")
    def list_vox_locations(
        protocol: str = Query(default="vless", pattern="^(vless)$"),
        _: dict = Depends(require_client),
    ) -> dict:
        # The currently pinned NOVA Android engine is Xray-based; expose VLESS only.
        return vox.locations(protocol)

    @router.get("/api/v1/vox/config")
    def get_vox_config(
        location: str = Query(min_length=1, max_length=64),
        protocol: str = Query(default="vless", pattern="^(vless)$"),
        device: int = Query(default=1, ge=1, le=2),
        response: Response = None,
        claims: dict = Depends(require_client),
    ) -> dict:
        if not LOCATION_PATTERN.fullmatch(location):
            raise HTTPException(status_code=422, detail="Invalid Vox location identifier")
        if response is not None:
            response.headers["Cache-Control"] = "no-store"
        device_id = claims["sub"]
        external_id = vox.external_id(device_id)
        result = vox.config(external_id, location, protocol, device)
        # Config contains private credentials; never cache or log this response.
        return {
            "external_id": external_id,
            "location": result.get("location", location),
            "location_label": result.get("location_label"),
            "protocol": result.get("protocol", protocol),
            "config": result["config"],
            "vless": result.get("vless"),
            "xray_outbound": result.get("xray_outbound"),
        }

    app.include_router(router)
