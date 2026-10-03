import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/data/app_store_billing.dart';
import 'package:waybi_mobile/data/plus_billing.dart';

const userId = '729db2f1-5891-4b09-9b2c-72ba7a8f271b';
const productId = 'me.samyao.waybi.plus.annual';

class BillingAccount extends AccountRepository {
  BillingAccount() {
    setPlan('free');
  }
  final verification = Completer<Map<String, dynamic>>();
  Future<Map<String, dynamic>>? configuration;
  String? transaction;
  bool verified = false;
  void setPlan(String plan) {
    profile = AccountProfile(
      id: userId,
      email: 'driver@example.test',
      displayName: '',
      providers: [],
      routes: [],
      places: [],
      reviews: [],
      recentDestinations: [],
      plan: plan,
      subscriptionSource: plan == 'plus' ? 'apple' : null,
    );
    notifyListeners();
  }

  @override
  bool get signedIn => true;
  @override
  Future<Map<String, dynamic>> appleBillingConfig() async =>
      await configuration ??
      {
        'ready': true,
        'monthly': 'me.samyao.waybi.plus.monthly',
        'annual': productId,
      };
  @override
  Future<Map<String, dynamic>> verifyApplePurchase(String transactionId) async {
    transaction = transactionId;
    final response = await verification.future;
    verified = response['verified'] == true && response['active'] == true;
    return response;
  }

  @override
  Future<void> refresh() async {
    if (verified) setPlan('plus');
  }
}

class TestStore extends AppStoreClient {
  final stream = StreamController<List<PurchaseDetails>>.broadcast(sync: true);
  PurchaseParam? param;
  int completed = 0;
  bool storeAvailable = true;
  String? restoredUser;
  @override
  Stream<List<PurchaseDetails>> get updates => stream.stream;
  @override
  Future<bool> available() async => storeAvailable;
  @override
  Future<ProductDetailsResponse> products(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: [
          ProductDetails(
            id: productId,
            title: 'Plus Yearly',
            description: 'Plus',
            price: r'NZ$39.99',
            rawPrice: 39.99,
            currencyCode: 'NZD',
          ),
        ],
        notFoundIDs: ids.where((id) => id != productId).toList(),
      );
  @override
  Future<bool> buy(PurchaseParam param) async {
    this.param = param;
    return true;
  }

  @override
  Future<void> restore(String userId) async {
    restoredUser = userId;
    stream.add([purchase(PurchaseStatus.restored)]);
  }

  @override
  Future<void> complete(PurchaseDetails purchase) async {
    completed++;
  }
}

PurchaseDetails purchase(PurchaseStatus status, {String id = productId}) =>
    PurchaseDetails(
      purchaseID: '100000000000001',
      productID: id,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'app_store',
      ),
      transactionDate: '1000',
      status: status,
    )..pendingCompletePurchase = true;

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BillingAccount account;
  late TestStore store;
  late AppStoreBillingGateway gateway;
  setUp(() {
    account = BillingAccount();
    store = TestStore();
    gateway = AppStoreBillingGateway(
      account,
      store: store,
      supportsStore: true,
    );
  });
  tearDown(() async {
    gateway.dispose();
    await store.stream.close();
    account.dispose();
  });

  test('purchase binds the Waybi account and finishes only after server verification', () async {
    final offering = await gateway.load();
    final buying = gateway.subscribe(offering.plans.single);
    await tick();
    expect(store.param?.applicationUserName, userId);
    store.stream.add([purchase(PurchaseStatus.purchased)]);
    await tick();
    expect(account.transaction, '100000000000001');
    expect(store.completed, 0);
    expect(account.profile?.isPlus, false);
    account.verification.complete({'verified': true, 'active': true});
    await buying;
    expect(store.completed, 1);
    expect(account.profile?.isPlus, true);
  });

  test(
    'rejected verification leaves the transaction unfinished and access free',
    () async {
      final offering = await gateway.load();
      final buying = gateway.subscribe(offering.plans.single);
      final rejection = expectLater(buying, throwsStateError);
      store.stream.add([purchase(PurchaseStatus.purchased)]);
      await tick();
      account.verification.complete({'verified': false});
      await rejection;
      expect(store.completed, 0);
      expect(account.profile?.isPlus, false);
    },
  );

  test('restore waits for asynchronous validation and accepts verified expired history', () async {
    await gateway.load();
    var finished = false;
    final restoring = gateway.restore().then((_) => finished = true);
    await tick();
    expect(store.restoredUser, userId);
    expect(finished, false);
    expect(store.completed, 0);
    account.verification.complete({'verified': true, 'active': false});
    await restoring;
    expect(finished, true);
    expect(store.completed, 1);
    expect(account.profile?.isPlus, false);
  });

  test('cancelled purchase reports cancellation without unlocking or completing it', () async {
    final offering = await gateway.load();
    final buying = gateway.subscribe(offering.plans.single);
    final cancelled = expectLater(
      buying,
      throwsA(isA<PlusPurchaseCancelled>()),
    );
    store.stream.add([purchase(PurchaseStatus.canceled)]);
    await cancelled;
    expect(account.transaction, isNull);
    expect(store.completed, 0);
    expect(account.profile?.isPlus, false);
  });

  test('an unavailable App Store never launches a purchase', () async {
    store.storeAvailable = false;
    final offering = await gateway.load();
    expect(offering.available, false);
    await expectLater(
      gateway.subscribe(offering.plans.first),
      throwsStateError,
    );
    expect(store.param, isNull);
  });
  test(
    'startup transactions wait for configured product IDs without opening Plus',
    () async {
      final config = Completer<Map<String, dynamic>>();
      account.configuration = config.future;
      gateway.initialize();
      store.stream.add([
        purchase(PurchaseStatus.purchased, id: 'custom.plus.annual'),
      ]);
      await tick();
      expect(account.transaction, isNull);
      config.complete({
        'ready': true,
        'monthly': 'custom.plus.monthly',
        'annual': 'custom.plus.annual',
      });
      await tick();
      expect(account.transaction, '100000000000001');
      account.verification.complete({'verified': true, 'active': true});
      await tick();
      expect(account.profile?.isPlus, true);
      expect(store.completed, 1);
    },
  );
}
