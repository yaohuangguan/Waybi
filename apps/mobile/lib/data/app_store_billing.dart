import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'account_repository.dart';
import 'plus_billing.dart';

abstract class AppStoreClient {
  Stream<List<PurchaseDetails>> get updates;
  Future<bool> available();
  Future<ProductDetailsResponse> products(Set<String> ids);
  Future<bool> buy(PurchaseParam param);
  Future<void> restore(String userId);
  Future<void> complete(PurchaseDetails purchase);
}

class NativeAppStoreClient implements AppStoreClient {
  InAppPurchase get _store => InAppPurchase.instance;
  @override
  Stream<List<PurchaseDetails>> get updates => _store.purchaseStream;
  @override
  Future<bool> available() => _store.isAvailable();
  @override
  Future<ProductDetailsResponse> products(Set<String> ids) =>
      _store.queryProductDetails(ids);
  @override
  Future<bool> buy(PurchaseParam param) =>
      _store.buyNonConsumable(purchaseParam: param);
  @override
  Future<void> restore(String userId) =>
      _store.restorePurchases(applicationUserName: userId);
  @override
  Future<void> complete(PurchaseDetails purchase) =>
      _store.completePurchase(purchase);
}

class AppStoreBillingGateway extends PlusBillingGateway {
  AppStoreBillingGateway(
    this.account, {
    AppStoreClient? store,
    bool? supportsStore,
  }) : _store = store ?? NativeAppStoreClient(),
       _supported =
           supportsStore ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
  final AccountRepository account;
  final AppStoreClient _store;
  final bool _supported;
  StreamSubscription<List<PurchaseDetails>>? _listener;
  final _products = <String, ProductDetails>{};
  final _pending = <String, PurchaseDetails>{};
  final _processing = <String>{};
  final _ids = <String>{
    'me.samyao.kiwilens.plus.monthly',
    'me.samyao.kiwilens.plus.annual',
  };
  Future<void> _updates = Future.value();
  Completer<void>? _purchase;
  Completer<void>? _restore;
  String? _requestedProduct;
  bool _ready = false;
  bool _disposed = false;

  // Owned by the app root so pending transactions also survive leaving the Plus page.
  void initialize() {
    if (!_supported || _listener != null || _disposed) return;
    account.addListener(_accountChanged);
    _listener = _store.updates.listen(
      _queue,
      onError: (Object error) => _fail(error),
    );
  }

  void _accountChanged() {
    if (!account.signedIn ||
        account.profile?.id.isEmpty != false ||
        _pending.isEmpty) {
      return;
    }
    final pending = _pending.values.toList();
    _pending.clear();
    _queue(pending);
  }

  void _queue(List<PurchaseDetails> updates) {
    _updates = _updates
        .then((_) => _handle(updates))
        .catchError((Object error) => _fail(error));
  }

  void _fail(Object error) {
    if (_purchase?.isCompleted == false) _purchase!.completeError(error);
    if (_restore?.isCompleted == false) _restore!.completeError(error);
  }

  Future<void> _handle(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (!_ids.contains(purchase.productID)) continue;
      if (purchase.status == PurchaseStatus.pending) continue;
      if (purchase.status == PurchaseStatus.canceled) {
        _fail(const PlusPurchaseCancelled());
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        _fail(StateError('App Store purchase failed'));
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      final id = purchase.purchaseID;
      if (id == null) {
        _fail(StateError('Missing App Store transaction'));
        continue;
      }
      if (!account.signedIn || account.profile?.id.isEmpty != false) {
        _pending[id] = purchase;
        continue;
      }
      if (!_processing.add(id)) continue;
      _pending.remove(id);
      try {
        final proof = await account.verifyApplePurchase(id);
        if (proof['verified'] != true) {
          throw StateError('App Store purchase was not verified');
        }
        await account.refresh();
        // Finish only after the server has validated ownership and stored the entitlement.
        if (purchase.pendingCompletePurchase) await _store.complete(purchase);
        _pending.remove(id);
        if (purchase.productID == _requestedProduct &&
            _purchase?.isCompleted == false) {
          _purchase!.complete();
        }
      } catch (error) {
        _pending[id] = purchase;
        _fail(error);
      } finally {
        _processing.remove(id);
      }
    }
    if (_restore?.isCompleted == false &&
        purchases.every((p) => p.status == PurchaseStatus.restored)) {
      _restore!.complete();
    }
  }

  @override
  Future<PlusOffering> load() async {
    initialize();
    _ready = false;
    _products.clear();
    final config = await account.appleBillingConfig();
    _ready = config['ready'] == true;
    final monthly =
        config['monthly'] as String? ?? 'me.samyao.kiwilens.plus.monthly';
    final annual =
        config['annual'] as String? ?? 'me.samyao.kiwilens.plus.annual';
    _ids
      ..clear()
      ..addAll([monthly, annual]);
    if (!_supported || !_ready || !await _store.available()) {
      return PlusOffering(
        available: false,
        provider: PlusBillingProvider.apple,
        canManage: account.profile?.subscriptionSource == 'apple',
        plans: const [
          PlusPlan(
            id: 'monthly',
            price: r'NZ$4.99',
            amount: 4.99,
            currency: 'NZD',
            annual: false,
          ),
          PlusPlan(
            id: 'annual',
            price: r'NZ$39.99',
            amount: 39.99,
            currency: 'NZD',
            annual: true,
          ),
        ],
      );
    }
    final response = await _store.products(_ids);
    if (response.error != null) {
      throw StateError('App Store could not load plans');
    }
    _products
      ..clear()
      ..addEntries(response.productDetails.map((p) => MapEntry(p.id, p)));
    _accountChanged();
    return PlusOffering(
      available: _products.isNotEmpty,
      provider: PlusBillingProvider.apple,
      canRestore: true,
      canManage: account.profile?.subscriptionSource == 'apple',
      plans:
          response.productDetails
              .map(
                (p) => PlusPlan(
                  id: p.id,
                  price: p.price,
                  amount: p.rawPrice,
                  currency: p.currencyCode,
                  annual: p.id == annual,
                ),
              )
              .toList()
            ..sort((a, b) => (a.annual ? 1 : 0).compareTo(b.annual ? 1 : 0)),
    );
  }

  @override
  Future<void> subscribe(PlusPlan plan) async {
    if (!_supported ||
        !_ready ||
        !account.signedIn ||
        account.profile?.id.isEmpty != false ||
        account.profile?.isPlus == true ||
        !_products.containsKey(plan.id) ||
        _purchase != null ||
        _restore != null) {
      throw StateError('Purchase unavailable');
    }
    final completion = Completer<void>();
    _purchase = completion;
    _requestedProduct = plan.id;
    try {
      await Future.wait<void>([
        completion.future.timeout(const Duration(minutes: 5)),
        () async {
          if (!await _store.buy(
            PurchaseParam(
              productDetails: _products[plan.id]!,
              applicationUserName: account.profile!.id,
            ),
          )) {
            throw StateError('Could not start App Store payment');
          }
        }(),
      ], eagerError: true);
    } finally {
      _purchase = null;
      _requestedProduct = null;
    }
  }

  @override
  Future<void> restore() async {
    if (!_supported ||
        !_ready ||
        !account.signedIn ||
        account.profile?.id.isEmpty != false ||
        _restore != null ||
        _purchase != null) {
      throw StateError('Restore unavailable');
    }
    final completion = Completer<void>();
    _restore = completion;
    try {
      await Future.wait<void>([
        completion.future.timeout(const Duration(minutes: 2)),
        _store.restore(account.profile!.id),
      ], eagerError: true);
    } finally {
      _restore = null;
    }
  }

  @override
  Future<void> manage() async {
    if (!await launchUrl(
      Uri.parse('https://apps.apple.com/account/subscriptions'),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('Could not open App Store subscriptions');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _listener?.cancel();
    account.removeListener(_accountChanged);
  }
}
