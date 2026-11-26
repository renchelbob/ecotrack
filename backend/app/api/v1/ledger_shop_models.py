from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field

from app.api.v1.auth_models import ContractModel

ShopItemType = Literal[
    "partner_coupon",
    "partner_qr",
    "virtual_streak_freeze",
    "virtual_eco_donation",
    "mascot_accessory",
]
LedgerOperationType = Literal[
    "daily_steps_reward",
    "segment_annotation_delta",
    "streak_bonus",
    "challenge_reward",
    "badge_reward",
    "shop_purchase",
    "shop_refund",
    "admin_adjustment",
]
OrderStatus = Literal["completed", "redeemed", "refunded", "expired"]


class PointLedgerItem(ContractModel):
    id: UUID
    idempotency_key: UUID
    operation_type: LedgerOperationType
    points_delta: int
    co2_delta_grams: int
    reference_entity_type: str | None = None
    reference_entity_id: UUID | None = None
    description: str
    created_at: datetime


class PointLedgerListResponse(ContractModel):
    points_balance: int = Field(ge=0)
    lifetime_points_earned: int = Field(ge=0)
    total_count: int = Field(ge=0)
    items: list[PointLedgerItem]


class ShopPartnerSummary(ContractModel):
    id: UUID
    slug: str
    name: str
    category_name: str
    logo_asset_key: str
    is_fictional_disclaimer: str


class ShopCatalogItem(ContractModel):
    id: UUID
    sku: str
    item_type: ShopItemType
    title: str
    subtitle: str
    description: str
    price_points: int = Field(ge=1)
    stock_quantity: int | None = None
    max_per_user_per_day: int = Field(ge=1)
    accessory_code: str | None = None
    image_asset_key: str
    partner: ShopPartnerSummary | None = None


class ShopCatalogResponse(ContractModel):
    fictional_shop_banner_ru: str
    categories: list[str]
    items: list[ShopCatalogItem]


class CartLineInput(ContractModel):
    shop_item_id: UUID
    quantity: int = Field(ge=1, le=10, strict=True)


class CreateShopOrderRequest(ContractModel):
    items: list[CartLineInput] = Field(min_length=1, max_length=10)


class ShopOrderLineItem(ContractModel):
    id: UUID
    shop_item_id: UUID
    title: str
    item_type: ShopItemType
    quantity: int
    unit_price_points: int
    line_total_points: int
    coupon_code: str
    qr_payload: str
    expires_at: datetime | None = None
    redeemed_at: datetime | None = None


class ShopOrderDetail(ContractModel):
    id: UUID
    idempotency_key: UUID
    status: OrderStatus
    total_points: int = Field(ge=1)
    remaining_points_balance: int = Field(ge=0)
    item_count: int = Field(ge=1)
    line_items: list[ShopOrderLineItem]
    created_at: datetime


class ShopOrderListResponse(ContractModel):
    total_count: int = Field(ge=0)
    orders: list[ShopOrderDetail]
