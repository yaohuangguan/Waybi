import 'package:flutter/material.dart';

import '../data/account_repository.dart';
import 'account_sign_in.dart';

class ProfileSheet extends StatefulWidget {
  const ProfileSheet({super.key, required this.account});
  final AccountRepository account;

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.account,
      builder: (context, _) {
        final profile = widget.account.profile;
        return Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .82,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  MediaQuery.viewInsetsOf(context).bottom + 24,
                ),
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'My Waybi',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  if (profile == null) ...[
                    const SizedBox(height: 12),
                    AccountSignIn(account: widget.account),
                  ] else ...[
                    Text(
                      profile.email,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _Stat('${profile.routes.length}', 'Routes'),
                        _Stat(
                          '${profile.places.where((place) => place['isFavorite'] == true).length}',
                          'Favorites',
                        ),
                        _Stat('${profile.reviews.length}', 'Reviews'),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _Section(
                      title: 'Recent navigation and saved routes',
                      empty: 'No routes yet.',
                      items: profile.routes.map((route) {
                        final name =
                            route['destinationName'] as String? ??
                            'Destination';
                        final mode = route['mode'] as String? ?? 'drive';
                        final metres = (route['distanceMeters'] as num?)
                            ?.round();
                        return _ProfileRow(
                          icon: Icons.route_rounded,
                          title: name,
                          detail:
                              '$mode${metres == null ? '' : ' · ${(metres / 1000).toStringAsFixed(1)} km'}',
                        );
                      }).toList(),
                    ),
                    _Section(
                      title: 'Saved places',
                      empty: 'No favorites or notes yet.',
                      items: profile.places
                          .map(
                            (place) => _ProfileRow(
                              icon: place['isFavorite'] == true
                                  ? Icons.favorite_rounded
                                  : Icons.place_outlined,
                              title: place['name'] as String? ?? 'Place',
                              detail:
                                  (place['note'] as String?)?.isNotEmpty == true
                                  ? place['note'] as String
                                  : (place['address'] as String? ?? ''),
                            ),
                          )
                          .toList(),
                    ),
                    _Section(
                      title: 'My private reviews',
                      empty: 'No reviews yet.',
                      items: profile.reviews
                          .map(
                            (review) => _ProfileRow(
                              icon: Icons.star_rounded,
                              title:
                                  '${review['placeName'] ?? 'Place'} · ${'★' * ((review['rating'] as num?)?.round() ?? 0)}',
                              detail: review['comment'] as String? ?? '',
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await widget.account.signOut();
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sign out'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.empty,
    required this.items,
  });
  final String title;
  final String empty;
  final List<Widget> items;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            empty,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        )
      else
        ...items,
    ],
  );
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: detail.isEmpty
        ? null
        : Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis),
  );
}
