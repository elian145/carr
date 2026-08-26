"""Public payloads must not leak account credentials or OTP bookkeeping.

User.to_dict() is embedded in unauthenticated listing and dealer responses, so
anything private here is scrapeable by anyone.
"""

from __future__ import annotations

from datetime import datetime, timezone

from kk.models import Car, User

PRIVATE_KEYS = (
    "phone_number",
    "email",
    "contact_verified_phones",
    "dealership_verified_phones",
    "dealership_verified_emails",
    "last_login",
)


def _seller() -> User:
    user = User()
    user.public_id = "seller-1"
    user.username = "seller_user"
    user.phone_number = "+9647701234567"
    user.email = "seller@example.com"
    user.first_name = "Sel"
    user.last_name = "Ler"
    user.is_verified = True
    user.is_admin = False
    user.account_type = "dealer"
    user.dealer_status = "approved"
    user.dealership_name = "Best Cars"
    user.dealership_phone = "+9647709999999"
    user.dealership_phones = ["+9647709999999"]
    user.dealership_verified_phones = ["+9647709999999"]
    user.contact_verified_phones = ["+9647701234567"]
    user.dealership_emails = ["sales@bestcars.example"]
    user.dealership_socials = {"instagram": "https://www.instagram.com/bestcars"}
    user.dealership_verified_emails = ["sales@bestcars.example"]
    user.created_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
    user.last_login = datetime(2026, 2, 1, tzinfo=timezone.utc)
    return user


def test_public_user_dict_hides_account_credentials():
    data = _seller().to_dict()

    for key in PRIVATE_KEYS:
        assert key not in data, f"{key} must not appear in public user payload"


def test_public_user_dict_keeps_public_business_fields():
    data = _seller().to_dict()

    assert data["id"] == "seller-1"
    assert data["username"] == "seller_user"
    assert data["dealership_name"] == "Best Cars"
    # Dealership contact details are deliberately public.
    assert data["dealership_phone"] == "+9647709999999"
    assert data["dealership_phones"] == ["+9647709999999"]
    assert data["dealership_emails"] == ["sales@bestcars.example"]
    assert data["dealership_socials"] == {
        "instagram": "https://www.instagram.com/bestcars",
    }


def test_private_user_dict_still_exposes_owner_fields():
    data = _seller().to_dict(include_private=True)

    assert data["phone_number"] == "+9647701234567"
    assert data["email"] == "seller@example.com"
    assert data["contact_verified_phones"] == ["+9647701234567"]
    assert data["dealership_verified_phones"] == ["+9647709999999"]
    assert data["last_login"] is not None


def test_placeholder_phone_email_never_returned():
    user = _seller()
    user.email = "0770123456@phone.local"

    assert "email" not in user.to_dict()
    assert "email" not in user.to_dict(include_private=True)


def test_listing_seller_embed_hides_account_credentials():
    car = Car()
    car.public_id = "car-1"
    car.brand = "Toyota"
    car.model = "Camry"
    car.year = 2020
    car.seller = _seller()

    public_seller = car.to_dict()["seller"]
    for key in PRIVATE_KEYS:
        assert key not in public_seller, f"{key} leaked through listing seller embed"

    # Owner/admin views (My Listings, admin dashboard) still need the real contact.
    assert car.to_dict(include_private=True)["seller"]["phone_number"] == (
        "+9647701234567"
    )
