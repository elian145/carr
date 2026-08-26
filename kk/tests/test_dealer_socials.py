from kk.dealer_socials import clean_dealership_socials, public_dealership_socials


def test_handles_become_canonical_urls():
    cleaned, err = clean_dealership_socials(
        {
            "facebook": "BestCarsErbil",
            "instagram": "@bestcars",
            "tiktok": "bestcars.iq",
        }
    )
    assert err is None
    assert cleaned == {
        "facebook": "https://www.facebook.com/BestCarsErbil",
        "instagram": "https://www.instagram.com/bestcars",
        "tiktok": "https://www.tiktok.com/@bestcars.iq",
    }


def test_facebook_handle_accepts_spaces():
    cleaned, err = clean_dealership_socials({"facebook": "Best Cars Erbil"})
    assert err is None
    assert cleaned == {
        "facebook": "https://www.facebook.com/search/pages/?q=Best+Cars+Erbil"
    }

    cleaned, err = clean_dealership_socials(
        {"facebook": "https://www.facebook.com/Best Cars Erbil"}
    )
    assert err is None
    assert cleaned == {
        "facebook": "https://www.facebook.com/search/pages/?q=Best+Cars+Erbil"
    }


def test_full_urls_are_https_and_host_checked():
    cleaned, err = clean_dealership_socials(
        {
            "facebook": "http://m.facebook.com/pages/foo",
            "instagram": "instagram.com/foo/",
            "tiktok": "https://vm.tiktok.com/ZMabcd/",
        }
    )
    assert err is None
    assert cleaned["facebook"] == "https://m.facebook.com/pages/foo"
    assert cleaned["instagram"] == "https://instagram.com/foo/"
    assert cleaned["tiktok"] == "https://vm.tiktok.com/ZMabcd/"


def test_rejects_other_hosts_and_javascript():
    cleaned, err = clean_dealership_socials({"instagram": "https://evil.example/phish"})
    assert cleaned is None
    assert "Instagram" in (err or "")

    cleaned, err = clean_dealership_socials({"tiktok": "javascript:alert(1)"})
    assert cleaned is None
    assert "TikTok" in (err or "")


def test_empty_values_clear_links():
    cleaned, err = clean_dealership_socials({"facebook": "  ", "instagram": ""})
    assert err is None
    assert cleaned == {}


def test_public_payload_drops_unknown_and_empty_keys():
    assert public_dealership_socials(
        {"facebook": "https://www.facebook.com/a", "youtube": "https://youtube.com/x", "tiktok": ""}
    ) == {"facebook": "https://www.facebook.com/a"}
