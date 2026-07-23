"""LangOS Python SDK — HTTP client for evaluation and integration."""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Any


class LangOSClient:
    def __init__(self, base_url: str = "http://127.0.0.1:9473") -> None:
        self.base_url = base_url.rstrip("/")

    def understand(self, request: dict[str, Any]) -> dict[str, Any]:
        return self._post("/v1/understand", request)

    def express(self, request: dict[str, Any]) -> dict[str, Any]:
        return self._post("/v1/express", request)

    def translate(self, request: dict[str, Any]) -> dict[str, Any]:
        return self._post("/v1/translate", request)

    def health(self) -> dict[str, Any]:
        return self._get("/v1/health")

    def _post(self, path: str, body: dict[str, Any]) -> dict[str, Any]:
        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(
            f"{self.base_url}{path}",
            data=data,
            headers={"content-type": "application/json"},
            method="POST",
        )
        return self._read(req)

    def _get(self, path: str) -> dict[str, Any]:
        req = urllib.request.Request(f"{self.base_url}{path}", method="GET")
        return self._read(req)

    def _read(self, req: urllib.request.Request) -> dict[str, Any]:
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"LangOS HTTP {exc.code}: {detail}") from exc
