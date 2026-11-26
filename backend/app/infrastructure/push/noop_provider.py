from collections.abc import Sequence


class NoopPushProvider:
    async def send_wakeup_nudge(self, tokens: Sequence[str], sender: str) -> bool:
        return False
