part of 'edit_dealer_page.dart';

mixin _EditDealerPageBuild on _EditDealerPageBuildBody {
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
          title: Text(_tr('Edit dealer', ar: 'تعديل الوكيل', ku: 'دەستکاری وەکیل')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Edit dealer', ar: 'تعديل الوكيل', ku: 'دەستکاری وەکیل')),
        backgroundColor: _editDealerAccent,
        foregroundColor: Colors.white,
        elevation: 0,
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
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: isLightShell ? 0.12 : 0.18),
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
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? (_loc?.savingLabel ?? 'Saving...') : (_loc?.saveChangesButton ?? 'Save changes')),
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
