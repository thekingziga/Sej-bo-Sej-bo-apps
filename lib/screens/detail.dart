import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class PostDetailScreen extends StatelessWidget {
  const PostDetailScreen({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brutal.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 16, 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Brutal.paper,
                        border: Brutal.outline,
                        boxShadow: Brutal.shadow(dx: 3, dy: 3),
                      ),
                      child: const Icon(Icons.arrow_back, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'SEJBOSEJBO #${post.id}',
                      style: Brutal.label.copyWith(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  Text(post.title, style: Brutal.display.copyWith(fontSize: 36)),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Brutal.ink, width: 4),
                      boxShadow: Brutal.shadow(dx: 7, dy: 7),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 200, maxHeight: 460),
                      child: ClipRect(
                        child: PostMedia(post: post, accent: Brutal.orange, compact: false),
                      ),
                    ),
                  ),
                  if (post.description.isNotEmpty && !post.isStory) ...[
                    const SizedBox(height: 18),
                    Text(post.description, style: Brutal.body.copyWith(fontSize: 17)),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (post.featured) ...[
                        const BrutalTag('featured'),
                        const SizedBox(width: 8),
                      ],
                      if (post.pinned) ...[
                        const BrutalTag('pinned', color: Brutal.cyan),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        relativeDate(post.createdAt),
                        style: Brutal.body.copyWith(
                          fontSize: 13,
                          color: Brutal.ink.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Transform.rotate(
                    angle: -0.03,
                    child: BrutalBox(
                      color: Brutal.lime,
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
                      child: Center(
                        child: Text(
                          'THIS IS OFFICIALLY\nSEJBOSEJBO.',
                          textAlign: TextAlign.center,
                          style: Brutal.display.copyWith(fontSize: 26),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
