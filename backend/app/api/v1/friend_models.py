from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import Field

from app.api.v1.auth_models import ContractModel

FriendshipStatus = Literal["pending", "accepted", "blocked"]
FriendAction = Literal["accept", "decline", "block"]
FRIEND_CODE = r"^ECO-[A-Z0-9]{4}-[A-Z0-9]{4}$"


class SendFriendRequestPayload(ContractModel):
    friend_code: str = Field(pattern=FRIEND_CODE)


class RespondFriendRequestPayload(ContractModel):
    action: FriendAction


class FriendshipRecord(ContractModel):
    id: UUID
    requester_id: UUID
    addressee_id: UUID
    status: FriendshipStatus
    created_at: datetime
    responded_at: datetime | None = None


class FriendProfileSummary(ContractModel):
    friendship_id: UUID
    user_id: UUID
    display_name: str
    friend_code: str
    avatar_url: str | None = None
    status: FriendshipStatus
    current_streak_days: int = Field(ge=0)
    equipped_accessory_code: str | None = None
    is_stats_visible_to_friends: bool
    weekly_co2_saved_grams: int | None = None
    weekly_steps: int | None = None
    can_send_wakeup_nudge_today: bool


class FriendsOverviewResponse(ContractModel):
    my_friend_code: str = Field(pattern=FRIEND_CODE)
    friends: list[FriendProfileSummary]
    incoming_requests: list[FriendProfileSummary]
    outgoing_requests: list[FriendProfileSummary]


class WakeupNudgeResponse(ContractModel):
    nudge_id: UUID
    receiver_id: UUID
    nudge_date: date
    push_delivered: bool
    sent_at: datetime


class LeaderboardEntry(ContractModel):
    rank: int = Field(ge=1)
    user_id: UUID
    display_name: str
    avatar_url: str | None = None
    equipped_accessory_code: str | None = None
    is_current_user: bool
    is_stats_visible: bool
    weekly_co2_saved_grams: int = Field(ge=0)
    weekly_steps: int = Field(ge=0)
    current_streak_days: int = Field(ge=0)


class FriendsLeaderboardResponse(ContractModel):
    iso_year: int
    iso_week: int
    week_start_date: date
    week_end_date: date
    entries: list[LeaderboardEntry]
