part of 'edit_dealer_page.dart';

mixin _EditDealerPageBuild on _EditDealerPageBuildBody {
  void _openPublicDealerPreview() {
    final user = context.read<AuthService>().currentUser;
    final dealerPublicId =
        (user?['public_id'] ?? user?['id'] ?? user?['user_id'] ?? '')
            .toString()
            .trim();
    if (dealerPublicId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Unable to open your public page',
              ar: 'تعذر فتح صفحتك العامة',
              ku: 'نەتوانرا پەڕەی گشتییەکەت بکرێتەوە',
            ),
          ),
        ),
      );
      return;
    }

    Navigator.pushNamed(
      context,
      '/dealer/profile',
      arguments: {'dealerPublicId': dealerPublicId, 'previewAsVisitor': true},
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isLightShell = brightness == Brightness.light;
    final barSurface = Color.alphaBlend(
      Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
      isLightShell ? Colors.white : AppThemes.darkHomeShellBackground,
    );

    if (_hydratingProfile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _tr('Edit dealer', ar: 'تعديل الوكيل', ku: 'دەستکاری وەکیل'),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr('Edit dealer', ar: 'تعديل الوكيل', ku: 'دەستکاری وەکیل'),
        ),
        backgroundColor: _editDealerAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _openPublicDealerPreview,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.visibility_outlined),
            label: Text(_tr('Preview', ar: 'معاينة', ku: 'پێشبینین')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      backgroundColor: isLightShell ? AppThemes.lightAppBackground : null,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Material(
                color: barSurface,
                elevation: 14,
                shadowColor: Colors.black.withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withValues(
                      alpha: isLightShell ? 0.12 : 0.18,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _editDealerAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _saving
                          ? (_loc?.savingLabel ?? 'Saving...')
                          : (_loc?.saveChangesButton ?? 'Save changes'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: _buildEditDealerBody(context),
    );
  }
}
