import 'package:car_listing_app/shared/dealer/dealer_socials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DealerSocials.normalize', () {
    test('turns handles into canonical profile URLs', () {
      expect(
        DealerSocials.normalize(DealerSocialNetwork.facebook, 'BestCarsErbil'),
        'https://www.facebook.com/BestCarsErbil',
      );
      expect(
        DealerSocials.normalize(DealerSocialNetwork.instagram, '@bestcars'),
        'https://www.instagram.com/bestcars',
      );
      expect(
        DealerSocials.normalize(DealerSocialNetwork.tiktok, 'bestcars.iq'),
        'https://www.tiktok.com/@bestcars.iq',
      );
    });

    test('accepts https host-allowlisted URLs', () {
      expect(
        DealerSocials.normalize(
          DealerSocialNetwork.instagram,
          'instagram.com/foo/',
        ),
        'https://instagram.com/foo/',
      );
    });

    test('rejects other hosts and javascript URLs', () {
      expect(
        DealerSocials.normalize(
          DealerSocialNetwork.instagram,
          'https://evil.example/phish',
        ),
        isNull,
      );
      expect(
        DealerSocials.normalize(
          DealerSocialNetwork.tiktok,
          'javascript:alert(1)',
        ),
        isNull,
      );
    });

    test('empty input is allowed', () {
      expect(DealerSocials.normalize(DealerSocialNetwork.facebook, '  '), '');
    });
  });

  test('fromDealerMap skips empty platforms', () {
    final links = DealerSocials.fromDealerMap({
      'dealership_socials': {
        'facebook': 'https://www.facebook.com/testdealer',
        'instagram': '',
      },
    });
    expect(links, hasLength(1));
    expect(links.first.network, DealerSocialNetwork.facebook);
    expect(links.first.handle, 'testdealer');
  });

  test('editHandle strips @ and URLs down to the username', () {
    expect(
      DealerSocials.editHandle(
        DealerSocialNetwork.facebook,
        'https://www.facebook.com/testdealer',
      ),
      'testdealer',
    );
    expect(
      DealerSocials.editHandle(
        DealerSocialNetwork.tiktok,
        'https://www.tiktok.com/@bestcars.iq',
      ),
      'bestcars.iq',
    );
  });
}
