enum DealerSocialNetwork { facebook, instagram, tiktok }

class DealerSocialLink {
  const DealerSocialLink({
    required this.network,
    required this.url,
    required this.handle,
  });

  final DealerSocialNetwork network;
  final String url;
  final String handle;
}

class DealerSocials {
  static const networks = DealerSocialNetwork.values;
  static const _maxUrlLen = 300;

  static const _hosts = <DealerSocialNetwork, Set<String>>{
    DealerSocialNetwork.facebook: {
      'facebook.com',
      'www.facebook.com',
      'm.facebook.com',
      'web.facebook.com',
      'fb.com',
      'fb.me',
    },
    DealerSocialNetwork.instagram: {'instagram.com', 'www.instagram.com'},
    DealerSocialNetwork.tiktok: {
      'tiktok.com',
      'www.tiktok.com',
      'm.tiktok.com',
      'vm.tiktok.com',
      'vt.tiktok.com',
    },
  };

  static String key(DealerSocialNetwork network) {
    switch (network) {
      case DealerSocialNetwork.facebook:
        return 'facebook';
      case DealerSocialNetwork.instagram:
        return 'instagram';
      case DealerSocialNetwork.tiktok:
        return 'tiktok';
    }
  }

  static String label(DealerSocialNetwork network) {
    switch (network) {
      case DealerSocialNetwork.facebook:
        return 'Facebook';
      case DealerSocialNetwork.instagram:
        return 'Instagram';
      case DealerSocialNetwork.tiktok:
        return 'TikTok';
    }
  }

  static List<DealerSocialLink> fromDealerMap(Map<String, dynamic>? dealer) {
    final raw = _coerceMap(dealer?['dealership_socials']);
    final out = <DealerSocialLink>[];
    for (final network in networks) {
      var value = (raw[key(network)] ?? '').toString().trim();
      if (value.isEmpty) {
        value = (dealer?['dealership_${key(network)}'] ?? '').toString().trim();
      }
      if (value.isEmpty) continue;
      final url = normalize(network, value) ?? value;
      if (url.isEmpty) continue;
      out.add(
        DealerSocialLink(
          network: network,
          url: url,
          handle: displayHandle(network, url),
        ),
      );
    }
    return out;
  }

  static Map<String, String> payload({
    required String facebook,
    required String instagram,
    required String tiktok,
  }) {
    return {
      'facebook': facebook.trim(),
      'instagram': instagram.trim(),
      'tiktok': tiktok.trim(),
    };
  }

  static String? normalize(DealerSocialNetwork network, String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    if (text.length > _maxUrlLen) return null;
    final lower = text.toLowerCase();
    if (lower.startsWith('javascript:') ||
        lower.startsWith('data:') ||
        lower.startsWith('file:') ||
        lower.startsWith('vbscript:')) {
      return null;
    }
    if (_looksLikeUrl(network, text)) {
      return _normalizeUrl(network, text);
    }
    return _normalizeHandle(network, text);
  }

  static String displayHandle(DealerSocialNetwork network, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return label(network);
    final segments = uri.pathSegments
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (segments.isEmpty) return label(network);
    var handle = segments.first;
    if (handle == 'profile.php' && (uri.queryParameters['id'] ?? '').isNotEmpty) {
      return uri.queryParameters['id']!;
    }
    if (handle == 'pages' && segments.length >= 2) {
      handle = segments[1];
    }
    if (handle.startsWith('@')) handle = handle.substring(1);
    if (handle.isEmpty) return label(network);
    return network == DealerSocialNetwork.tiktok ? '@$handle' : handle;
  }

  /// Username shown in the edit form (no leading @).
  static String editHandle(DealerSocialNetwork network, String url) {
    var handle = displayHandle(network, url);
    if (handle == label(network)) return '';
    if (handle.startsWith('@')) handle = handle.substring(1);
    return handle;
  }

  static Map<String, String> _coerceMap(dynamic raw) {
    if (raw is Map) {
      return {
        for (final entry in raw.entries)
          entry.key.toString(): (entry.value ?? '').toString(),
      };
    }
    return const {};
  }

  static bool _looksLikeUrl(DealerSocialNetwork network, String text) {
    final lower = text.toLowerCase().trim();
    if (lower.contains('://') ||
        lower.startsWith('http:') ||
        lower.startsWith('https:')) {
      return true;
    }
    if (text.contains('/')) return true;
    var host = lower.split('/').first.split('?').first;
    if (host.startsWith('www.')) host = host.substring(4);
    return _hosts[network]!.contains(host);
  }

  static String? _normalizeHandle(DealerSocialNetwork network, String value) {
    var handle = value.trim();
    if (handle.startsWith('@')) handle = handle.substring(1);
    if (handle.toLowerCase().startsWith('www.')) return null;
    final ok = switch (network) {
      DealerSocialNetwork.facebook => RegExp(r'^[A-Za-z0-9.\-]{1,80}$'),
      DealerSocialNetwork.instagram => RegExp(r'^[A-Za-z0-9._]{1,30}$'),
      DealerSocialNetwork.tiktok => RegExp(r'^[A-Za-z0-9._]{2,24}$'),
    };
    if (!ok.hasMatch(handle)) return null;
    switch (network) {
      case DealerSocialNetwork.facebook:
        return 'https://www.facebook.com/$handle';
      case DealerSocialNetwork.instagram:
        return 'https://www.instagram.com/$handle';
      case DealerSocialNetwork.tiktok:
        return 'https://www.tiktok.com/@$handle';
    }
  }

  static String? _normalizeUrl(DealerSocialNetwork network, String value) {
    var text = value.trim();
    if (text.startsWith('//')) {
      text = 'https:$text';
    } else if (!text.contains('://')) {
      text = 'https://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.userInfo.isNotEmpty) return null;
    final host = (uri.host).toLowerCase();
    if (!_hosts[network]!.contains(host)) return null;
    if (uri.hasPort && uri.port != 80 && uri.port != 443) return null;
    final path = uri.path.isEmpty ? '/' : uri.path;
    if ((path == '/' || path.isEmpty) && !uri.hasQuery) return null;
    final rebuilt = Uri(
      scheme: 'https',
      host: host,
      path: path,
      query: uri.hasQuery ? uri.query : null,
    ).toString();
    if (rebuilt.length > _maxUrlLen) return null;
    return rebuilt;
  }
}
