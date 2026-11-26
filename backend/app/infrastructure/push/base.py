from collections.abc import Sequence
from typing import Protocol


class PushNotificationProvider(Protocol):
    async def send_wakeup_nudge(self, tokens: Sequence[str], sender: str) -> bool: ...
