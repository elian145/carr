part of 'chat_pages.dart';

mixin _ChatConversationPageBuild on _ChatConversationPageBuildBody {
  @override
  Widget build(BuildContext context) {
    final mergedMeta = _mergedListingMeta();
    final localizedFromMeta = localizedListingTitle(context, mergedMeta).trim();
    final conversationTitle = localizedFromMeta.isNotEmpty
        ? localizedFromMeta
        : ((_carDisplayTitle ?? '').trim().isNotEmpty
            ? _carDisplayTitle!.trim()
            : AppLocalizations.of(context)!.listingTitle);
    return Scaffold(
            appBar: AppBar(
              centerTitle: false,
              toolbarHeight: 64,
              leading: BackButton(
                color: Theme.of(context).appBarTheme.foregroundColor,
                onPressed: () => Navigator.maybePop(context),
              ),
              title: InkWell(
                onTap: () {
                  final listingId = listingPrimaryId(_mergedListingMeta());
                  final carId = listingId.isNotEmpty
                      ? listingId
                      : widget.carId.trim();
                  if (carId.isEmpty) return;
                  Navigator.pushNamed(
                    context,
                    '/car_detail',
                    arguments: {'carId': carId},
                  );
                },
                child: Row(
                  children: [
                    buildChatListingAvatar(
                      context,
                      imageUrl: _carImageUrl,
                      radius: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AutoSizeText(
                        conversationTitle,
                        maxLines: 3,
                        minFontSize: 10,
                        stepGranularity: 0.5,
                        softWrap: true,
                        overflow: TextOverflow.clip,
                        style: Theme.of(context).appBarTheme.titleTextStyle
                                ?.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ) ??
                            const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              color: Colors.white,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (widget.receiverId != null && widget.receiverId!.isNotEmpty)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'block') _showBlockDialog();
                      if (value == 'report') _showReportDialog();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'block',
                        child: Text(
                          _chatText(
                            context,
                            'Block User',
                            ar: 'حظر المستخدم',
                            ku: 'بلۆککردنی بەکارهێنەر',
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'report',
                        child: Text(
                          _chatText(
                            context,
                            'Report User',
                            ar: 'الإبلاغ عن المستخدم',
                            ku: 'ڕاپۆرتکردنی بەکارهێنەر',
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            body: _buildChatConversationBody(context),
    );
  }
}
