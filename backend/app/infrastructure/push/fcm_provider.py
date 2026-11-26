import asyncio
import re
from collections.abc import Sequence
from datetime import UTC, datetime, timedelta
from pathlib import Path

import httpx
import jwt
from pydantic import BaseModel, Field


class ServiceAccount(BaseModel):
    project_id: str = Field(pattern=r"^[a-zA-Z0-9_:-]{1,128}$")
    client_email: str
    private_key: str = Field(repr=False)


class FcmPushProvider:
    def __init__(self, service_account_file: Path) -> None:
        self.service_account_file = service_account_file
        self._lock = asyncio.Lock()
        self._credentials: ServiceAccount | None = None
        self._access: tuple[str, datetime] | None = None

    async def _authenticate(self, client: httpx.AsyncClient) -> tuple[str, str]:
        async with self._lock:
            if self._credentials is None:
                raw = await asyncio.to_thread(self.service_account_file.read_text, encoding="utf-8")
                self._credentials = ServiceAccount.model_validate_json(raw)
            credentials = self._credentials
            now = datetime.now(UTC)
            if self._access is None or self._access[1] <= now:
                endpoint = "https://oauth2.googleapis.com/token"
                assertion = jwt.encode(
                    {
                        "iss": credentials.client_email,
                        "scope": "https://www.googleapis.com/auth/firebase.messaging",
                        "aud": endpoint,
                        "iat": now,
                        "exp": now + timedelta(hours=1),
                    },
                    credentials.private_key,
                    algorithm="RS256",
                )
                response = await client.post(
                    endpoint,
                    data={
                        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                        "assertion": assertion,
                    },
                )
                response.raise_for_status()
                result = response.json()
                token = result["access_token"]
                if not isinstance(token, str) or not re.fullmatch(r"[\x21-\x7e]+", token):
                    raise ValueError("Invalid service account access token")
                self._access = (
                    token,
                    now + timedelta(seconds=max(1, int(result["expires_in"]) - 60)),
                )
            return credentials.project_id, self._access[0]

    async def send_wakeup_nudge(self, tokens: Sequence[str], sender: str) -> bool:
        if not tokens:
            return False
        try:
            async with httpx.AsyncClient(timeout=4, follow_redirects=False) as client:
                project, access_token = await self._authenticate(client)
                results = await asyncio.gather(
                    *(
                        client.post(
                            f"https://fcm.googleapis.com/v1/projects/{project}/messages:send",
                            headers={"Authorization": f"Bearer {access_token}"},
                            json={
                                "message": {
                                    "token": token,
                                    "notification": {
                                        "title": "EcoTrack",
                                        "body": f"Друг {sender} будит вашего зверька!",
                                    },
                                    "data": {"deep_link": "ecotrack://home"},
                                }
                            },
                        )
                        for token in tokens[:20]
                    ),
                    return_exceptions=True,
                )
                return any(isinstance(r, httpx.Response) and r.is_success for r in results)
        except OSError, httpx.HTTPError, jwt.PyJWTError, ValueError, KeyError, TypeError:
            return False
