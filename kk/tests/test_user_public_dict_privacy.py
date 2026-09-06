"""Public payloads must not leak account credentials or OTP bookkeeping.

User.to_dict() is embedded in unauthenticated listing and dealer responses, so
anything private here is scrapeable by anyone.
"""

from __future__ import annotations

from datetime import datetime, timezone

from kk.models import Car, DealerProfile, User

PRIVATE_KEYS = (
    "phone_number",
    "email",
    "contact_verified_phones",
    "dealership_verified_phones",
    "dealership_verified_emails",
    "last_login",
)

# H-05: exact dealer GPS coordinates. Non-round values so a rounding/coarsening
# regression would be caught (see test_map_location_returns_exact_values).
DEALER_LATITUDE = 33.123456
DEALER_LONGITUDE = 44.654321

MAP_LOCATION_KEYS = ("dealership_latitude", "dealership_longitude")


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
    user.dealership_latitude = DEALER_LATITUDE
    user.dealership_longitude = DEALER_LONGITUDE
    user.created_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
    user.last_login = datetime(2026, 2, 1, tzinfo=timezone.utc)
    return user


def _dealer_profile() -> DealerProfile:
    profile = DealerProfile()
    profile.public_id = "profile-1"
    profile.dealership_name = "Best Cars"
    profile.dealership_phone = "+9647709999999"
    profile.dealership_phones = ["+9647709999999"]
    profile.dealership_location = "Erbil"
    profile.dealership_emails = ["sales@bestcars.example"]
    profile.dealership_verified_emails = ["sales@bestcars.example"]
    profile.dealership_latitude = DEALER_LATITUDE
    profile.dealership_longitude = DEALER_LONGITUDE
    profile.is_featured = False
    profile.created_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
    profile.updated_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
    return profile


def test_public_user_dict_hides_account_credentials():
    data = _seller().to_dict()

    for key in PRIVATE_KEYS:
        assert key not in data, f"{key} must not appear in public user payload"


def test_public_user_dict_keeps_public_business_fields():
    data = _seller().to_dict()

    assert data["id"] == "seller-1"
    assert data["username"] == "seller_user"
    assert data["dealership_name"] == "Best Cars"
    # Dealership phones stay public (call-the-dealer UX). Emails are not in
    # public browse payloads.
    assert data["dealership_phone"] == "+9647709999999"
    assert data["dealership_phones"] == ["+9647709999999"]
    assert "dealership_emails" not in data
    assert data["has_dealership_email"] is True
    assert data["dealership_socials"] == {
        "instagram": "https://www.instagram.com/bestcars",
    }


def test_public_user_dict_hides_map_location_by_default():
    """H-05: exact GPS must not be part of the generic public shape — that
    dict is embedded in every listing's `seller` object (car/favorites feeds),
    which have no map feature and no need for exact coordinates."""
    data = _seller().to_dict()

    for key in MAP_LOCATION_KEYS:
        assert key not in data, f"{key} must not appear in the default public user payload"


def test_user_dict_include_map_location_returns_exact_coordinates():
    """H-05: the dealer-profile route opts in via include_map_location=True
    to power the intentional 'exact location on Google Maps' feature. Values
    must be exact — no rounding/coarsening."""
    data = _seller().to_dict(include_map_location=True)

    assert data["dealership_latitude"] == DEALER_LATITUDE
    assert data["dealership_longitude"] == DEALER_LONGITUDE


def test_private_user_dict_still_exposes_owner_fields():
    data = _seller().to_dict(include_private=True)

    assert data["phone_number"] == "+9647701234567"
    assert data["email"] == "seller@example.com"
    assert data["contact_verified_phones"] == ["+9647701234567"]
    assert data["dealership_verified_phones"] == ["+9647709999999"]
    assert data["dealership_emails"] == ["sales@bestcars.example"]
    assert data["last_login"] is not None
    # H-05: owner/admin (include_private=True) must keep receiving the exact,
    # unmodified coordinates, same as before this change.
    assert data["dealership_latitude"] == DEALER_LATITUDE
    assert data["dealership_longitude"] == DEALER_LONGITUDE


def test_dealer_profile_dict_hides_map_location_by_default():
    data = _dealer_profile().to_dict()

    for key in MAP_LOCATION_KEYS:
        assert key not in data, f"{key} must not appear in the default public dealer_profile payload"


def test_dealer_profile_dict_include_map_location_returns_exact_coordinates():
    data = _dealer_profile().to_dict(include_map_location=True)

    assert data["dealership_latitude"] == DEALER_LATITUDE
    assert data["dealership_longitude"] == DEALER_LONGITUDE


def test_dealer_profile_dict_include_private_returns_exact_coordinates():
    data = _dealer_profile().to_dict(include_private=True)

    assert data["dealership_latitude"] == DEALER_LATITUDE
    assert data["dealership_longitude"] == DEALER_LONGITUDE
    # Existing include_private behavior for other fields must be unchanged.
    assert data["dealership_emails"] == ["sales@bestcars.example"]


def test_public_listing_hides_contact_phones_and_vin():
    car = Car()
    car.public_id = "car-2"
    car.brand = "Toyota"
    car.model = "Camry"
    car.year = 2020
    car.vin = "JTDBR32E720012345"
    car.contact_phone = "+9647701112233"
    car.contact_phones = ["+9647701112233", "+9647704445566"]
    car.seller = _seller()

    public = car.to_dict()
    assert public["contact_phone"] is None
    assert public["contact_phones"] == []
    assert public["has_contact_phone"] is True
    assert public["contact_phone_masked"] is not None
    assert public["vin"] is None
    assert public["has_vin"] is True

    private = car.to_dict(include_private=True)
    assert private["contact_phone"] == "+9647701112233"
    assert private["contact_phones"] == ["+9647701112233", "+9647704445566"]
    assert private["vin"] == "JTDBR32E720012345"


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


def test_listing_seller_embed_hides_exact_dealer_map_location():
    """H-05: Car.to_dict() forwards include_private only (never
    include_map_location) into the embedded seller — the browse/detail/
    favorites feeds have no map feature and must not replicate the dealer's
    exact GPS coordinates.
    """
    car = Car()
    car.public_id = "car-1"
    car.brand = "Toyota"
    car.model = "Camry"
    car.year = 2020
    car.seller = _seller()

    public_seller = car.to_dict()["seller"]
    for key in MAP_LOCATION_KEYS:
        assert key not in public_seller, f"{key} leaked through public listing seller embed"

    # Owner/admin views (My Listings, admin dashboard) are unaffected: they
    # still receive the exact seller coordinates as before this change.
    private_seller = car.to_dict(include_private=True)["seller"]
    assert private_seller["dealership_latitude"] == DEALER_LATITUDE
    assert private_seller["dealership_longitude"] == DEALER_LONGITUDE
