import 'package:flutter/material.dart';

import 'shimmer.dart';

/// Skeleton placeholders matching listing cards / chat rows.
class ListingFeedSkeleton extends StatelessWidget {
  const ListingFeedSkeleton({
    super.key,
    this.columns = 2,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(12),
  });

  final int columns;
  final int itemCount;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cols = columns.clamp(1, 2);
    return Shimmer(
      child: GridView.builder(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: itemCount,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: cols == 1 ? 1.35 : 0.72,
        ),
        itemBuilder: (context, _) => const _ListingCardSkeleton(),
      ),
    );
  }
}

class ListingFeedSkeletonSliver extends StatelessWidget {
  const ListingFeedSkeletonSliver({
    super.key,
    this.columns = 2,
    this.itemCount = 6,
  });

  final int columns;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final cols = columns.clamp(1, 2);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      sliver: SliverToBoxAdapter(
        child: Shimmer(
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itemCount,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: cols == 1 ? 1.35 : 0.72,
            ),
            itemBuilder: (context, _) => const _ListingCardSkeleton(),
          ),
        ),
      ),
    );
  }
}

class ChatListSkeleton extends StatelessWidget {
  const ChatListSkeleton({super.key, this.itemCount = 8});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, _) => const _ChatRowSkeleton(),
      ),
    );
  }
}

class _ListingCardSkeleton extends StatelessWidget {
  const _ListingCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Expanded(child: ShimmerBox(borderRadius: 12)),
        const SizedBox(height: 8),
        const ShimmerBox(height: 14, borderRadius: 6),
        const SizedBox(height: 6),
        ShimmerBox(
          width: MediaQuery.sizeOf(context).width * 0.25,
          height: 12,
          borderRadius: 6,
        ),
        const SizedBox(height: 6),
        const ShimmerBox(height: 14, borderRadius: 6, width: 72),
      ],
    );
  }
}

class _ChatRowSkeleton extends StatelessWidget {
  const _ChatRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const ShimmerBox(width: 52, height: 52, borderRadius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ShimmerBox(height: 14, borderRadius: 6),
                  SizedBox(height: 8),
                  ShimmerBox(height: 12, width: 160, borderRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const ShimmerBox(width: 36, height: 12, borderRadius: 6),
          ],
        ),
      ),
    );
  }
}
