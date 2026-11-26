import asyncio
import os
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4, uuid7

import asyncpg
import pytest
from hypothesis import settings, strategies as st
from hypothesis.stateful import RuleBasedStateMachine, invariant, rule

from app.api.errors import CatalogException
from app.api.v1.activity_models import SyncDailyStepsRequest
from app.api.v1.ledger_shop_models import CartLineInput
from app.application.activity_service import sync_steps
from app.application.ledger_shop_service import checkout
from app.infrastructure.db.pool import configure_connection

pytestmark = pytest.mark.skipif("TEST_DATABASE_URL" not in os.environ, reason="requires PostGIS")
FREEZE = UUID("01950000-0000-7000-8000-000000000101")


class LedgerActivityMachine(RuleBasedStateMachine):
    def __init__(self) -> None:
        super().__init__()
        self.user = uuid7()
        self.today = datetime.now(UTC).date()
        self.max_steps: dict[int, int] = {}
        self.runner = asyncio.Runner()
        self.runner.run(self._setup())

    async def _setup(self) -> None:
        self.connection = await asyncpg.connect(os.environ["TEST_DATABASE_URL"])
        await configure_connection(self.connection)
        self.transaction = self.connection.transaction()
        await self.transaction.start()
        suffix = uuid4().hex.upper()
        await self.connection.execute(
            "INSERT INTO users (id, display_name, friend_code) VALUES ($1, 'Stateful user', $2)",
            self.user,
            f"ECO-{suffix[:4]}-{suffix[4:8]}",
        )
        await self.connection.execute(
            """
            INSERT INTO fz152_consent_journal (user_id, policy_version, action, consent_scope)
            VALUES ($1, 'test', 'granted', $2::jsonb)
            """,
            self.user,
            {
                "personal_data_152fz": True,
                "health_steps_sensor": True,
                "background_geolocation": False,
            },
        )

    @rule(day=st.integers(0, 2), steps=st.integers(0, 20_000))
    def record_steps(self, day: int, steps: int) -> None:
        async def submit_twice() -> None:
            body = SyncDailyStepsRequest(
                activity_date=self.today - timedelta(days=day),
                raw_sensor_steps=steps,
                timezone_offset_minutes=0,
            )
            key = uuid7()
            first = await sync_steps(self.connection, self.user, key, body)
            second = await sync_steps(self.connection, self.user, key, body)
            self.max_steps[day] = max(self.max_steps.get(day, 0), steps)
            assert first.validated_steps == self.max_steps[day]
            assert second.validated_steps == first.validated_steps
            assert second.points_delta_applied == 0
            assert second.points_balance == first.points_balance

        self.runner.run(submit_twice())

    @rule()
    def purchase_freeze(self) -> None:
        async def buy_twice() -> None:
            key = uuid7()
            body = [CartLineInput(shop_item_id=FREEZE, quantity=1)]
            try:
                order = await checkout(self.connection, self.user, key, body)
            except CatalogException as exc:
                assert exc.code in {"INSUFFICIENT_POINTS_BALANCE", "SHOP_DAILY_USER_LIMIT_EXCEEDED"}
                return
            assert await checkout(self.connection, self.user, key, body) == order

        self.runner.run(buy_twice())

    @invariant()
    def the_ledger_matches_the_balance(self) -> None:
        async def verify() -> None:
            row = await self.connection.fetchrow(
                """
                SELECT u.points_balance, u.lifetime_points_earned,
                       COALESCE(sum(p.points_delta), 0) AS ledger_balance,
                       COALESCE(sum(GREATEST(0, p.points_delta)), 0) AS ledger_earned
                FROM users u LEFT JOIN point_ledger p ON p.user_id = u.id
                WHERE u.id = $1 GROUP BY u.id
                """,
                self.user,
            )
            assert row is not None
            assert row["points_balance"] == row["ledger_balance"] >= 0
            assert row["lifetime_points_earned"] == row["ledger_earned"]

        self.runner.run(verify())

    def teardown(self) -> None:
        async def close() -> None:
            await self.transaction.rollback()
            await self.connection.close()

        try:
            self.runner.run(close())
        finally:
            self.runner.close()


TestLedgerActivity = LedgerActivityMachine.TestCase
TestLedgerActivity.settings = settings(max_examples=10, stateful_step_count=12, deadline=None)
