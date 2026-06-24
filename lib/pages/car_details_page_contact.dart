part of 'car_details_page.dart';

mixin _CarDetailsPageContact on _CarDetailsPageInit {
  Widget _buildContactButtonsRow() {
    return CarDetailsContactBar(
      onWhatsApp: _openWhatsAppToSeller,
      onCall: _callSeller,
    );
  }

  Future<void> _callSeller() async {
    final String raw = sellerPhoneRawForContact(car) ?? '';
    final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.sellerPhoneNotAvailable)),
        );
      }
      return;
    }
    final Uri callUri = Uri.parse('tel:$digits');
    final launched = await launchUrl(callUri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (launched) {
      await AnalyticsService.trackCall(widget.carId.toString());
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to make call')),
      );
    }
  }

  bool get _hasDialableSellerPhone => hasDialableSellerPhone(car);

  Future<void> _openWhatsAppToSeller() async {
    if (car == null) return;
    final String? raw = sellerPhoneRawForContact(car);
    if (raw == null || raw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.sellerPhoneNotAvailable,
            ),
          ),
        );
      }
      return;
    }
    final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.sellerPhoneNotAvailable,
            ),
          ),
        );
      }
      return;
    }
    final String msg = Uri.encodeComponent(
      'Hi, I am interested in your ${_displayCarTitle(context).isNotEmpty ? _displayCarTitle(context) : 'car'}',
    );
    final Uri waApp = Uri.parse('whatsapp://send?phone=$digits&text=$msg');
    final Uri waWeb = Uri.parse('https://wa.me/$digits?text=$msg');
    bool launched = await launchUrl(
      waApp,
      mode: LaunchMode.externalNonBrowserApplication,
    ).catchError((_) => false);
    if (!launched) {
      launched = await launchUrl(
        waWeb,
        mode: LaunchMode.externalApplication,
      ).catchError((_) => false);
    }
    if (!launched) {
      launched = await launchUrl(
        waWeb,
        mode: LaunchMode.platformDefault,
      ).catchError((_) => false);
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.unableToOpenWhatsApp),
        ),
      );
    } else if (launched) {
      await AnalyticsService.trackMessage(widget.carId.toString());
    }
  }

  void _openCarzoChat() {
    if (car == null || !mounted) return;
    final loc = AppLocalizations.of(context)!;
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.loginRequired)));
      return;
    }

    final String carIdForChat =
        (car!['public_id'] ?? car!['id'] ?? widget.carId).toString().trim();
    if (carIdForChat.isEmpty) return;

    final String title = _displayCarTitle(context).isNotEmpty
        ? _displayCarTitle(context)
        : '${car!['brand'] ?? ''} ${car!['model'] ?? ''} ${car!['year'] ?? ''}'
              .trim();
    final String starterMessage =
        'Hi, I am interested in "$title". What is the price for this listing?';

    String? receiverId;
    String? receiverName;
    final seller = car!['seller'];
    if (seller is Map) {
      final m = Map<String, dynamic>.from(seller);
      final rid = m['id'];
      if (rid != null) {
        final s = rid.toString().trim();
        if (s.isNotEmpty) receiverId = s;
      }
      final fullName = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'
          .trim();
      final at = (m['account_type'] ?? '').toString().trim();
      final ds = (m['dealer_status'] ?? '').toString().trim();
      final dn = (m['dealership_name'] ?? '').toString().trim();
      if (at == 'dealer' && ds == 'approved' && dn.isNotEmpty) {
        receiverName = dn;
      } else if (at == 'dealer') {
        receiverName = fullName.isNotEmpty ? fullName : 'Dealer';
      } else {
        receiverName = (m['name'] ?? m['username'] ?? '').toString().trim();
        if (receiverName.isEmpty && fullName.isNotEmpty) {
          receiverName = fullName;
        }
        if (receiverName.isEmpty) {
          receiverName = null;
        }
      }
    }

    final myId = auth.userId?.toString().trim();
    if (receiverId != null &&
        myId != null &&
        myId.isNotEmpty &&
        receiverId == myId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.chatCarzoOwnListing)));
      return;
    }

    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => carzo_chat.ChatConversationPage(
            carId: carIdForChat,
            receiverId: receiverId,
            receiverName: receiverName,
            initialDraft: starterMessage,
            initialListingPreview: {
              'id': carIdForChat,
              'title': title,
              'price': car!['price'],
              'currency': car!['currency'],
              'location': car!['location'] ?? car!['city'],
              'image_url': car!['image_url'],
              'images': car!['images'],
              'brand': car!['brand'],
              'model': car!['model'],
              'trim': car!['trim'],
              'year': car!['year'],
            },
        ),
      ),
    );
  }

  Future<void> _shareCar() async {
    try {
      if (car == null) return;

      final String id = listingPrimaryId(car!).isNotEmpty
          ? listingPrimaryId(car!)
          : widget.carId.toString();

      await shareListingAsLinkOnly(
        id,
        context: context,
        listingTitle: _displayCarTitle(context),
      );

      // Track share for analytics
      await AnalyticsService.trackShare(widget.carId.toString());
    } catch (e) {
      appLog('Failed to share car: $e');
    }
  }
}
