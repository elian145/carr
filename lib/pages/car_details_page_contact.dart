part of 'car_details_page.dart';

mixin _CarDetailsPageContact on _CarDetailsPageInit {
  Widget _buildContactButtonsRow() {
    return CarDetailsContactBar(
      onWhatsApp: _openWhatsAppToSeller,
      onCall: _callSeller,
    );
  }

  Future<bool> _confirmScamSafetyWarning() async {
    if (!mounted) return false;
    final loc = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(loc.scamSafetyWarningTitle),
          content: Text(loc.scamSafetyWarningBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.cancelAction),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.scamSafetyWarningContinue),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<List<String>> _resolveSellerPhones() async {
    var phones = sellerPhonesForContact(car);
    if (phones.isNotEmpty) return phones;
    if (!listingHasContactAvailability(car)) return const [];
    final listingId = (car != null && listingPrimaryId(car!).isNotEmpty)
        ? listingPrimaryId(car!)
        : widget.carId.toString();
    phones = await ApiService.getCarContactPhones(listingId);
    if (phones.isEmpty || car == null || !mounted) return phones;
    setState(() {
      car = {
        ...car!,
        'contact_phone': phones.first,
        'contact_phones': phones,
        'has_contact_phone': true,
      };
    });
    return phones;
  }

  Future<String?> _pickSellerPhone({required String title}) async {
    final phones = await _resolveSellerPhones();
    if (phones.isEmpty) return null;
    if (phones.length == 1) return phones.first;
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final loc = AppLocalizations.of(ctx)!;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final phone in phones)
                ListTile(
                  leading: const Icon(Icons.phone_outlined),
                  title: Text(phone),
                  onTap: () => Navigator.pop(ctx, phone),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(loc.cancelAction),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _callSeller() async {
    if (!await _confirmScamSafetyWarning()) return;
    final String? raw = await _pickSellerPhone(
      title: AppLocalizations.of(context)!.callSeller,
    );
    final String digits = (raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');
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
        SnackBar(content: Text(AppLocalizations.of(context)!.unableToMakeCall)),
      );
    }
  }

  bool get _hasDialableSellerPhone => hasDialableSellerPhone(car);

  Future<void> _openWhatsAppToSeller() async {
    if (car == null) return;
    if (!await _confirmScamSafetyWarning()) return;
    final String? raw = await _pickSellerPhone(
      title: AppLocalizations.of(context)!.chatOnWhatsApp,
    );
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
    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    final carTitle = _displayCarTitle(context);
    final String listingId = listingPrimaryId(car!).isNotEmpty
        ? listingPrimaryId(car!)
        : widget.carId.toString();
    final title = carTitle.trim().isNotEmpty
        ? carTitle.trim()
        : loc.whatsappListingInterestDefaultTitle;
    final String msg = Uri.encodeComponent(
      buildListingWhatsAppMessage(
        interestText: loc.whatsappListingInterestMessage(title),
        listingId: listingId,
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.loginRequired),
          action: SnackBarAction(
            label: loc.loginAction,
            onPressed: () => Navigator.pushNamed(context, '/login'),
          ),
        ),
      );
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
      AppPageRoute<void>(
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.failedToShareListing),
        ),
      );
    }
  }
}
