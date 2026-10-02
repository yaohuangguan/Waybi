enum PlusBillingProvider { apple, stripe }

class PlusPlan {
  const PlusPlan({
    required this.id,
    required this.price,
    required this.amount,
    required this.currency,
    required this.annual,
  });
  final String id;
  final String price;
  final double amount;
  final String currency;
  final bool annual;
}

class PlusOffering {
  const PlusOffering({
    required this.plans,
    required this.available,
    required this.provider,
    this.canRestore = false,
    this.canManage = false,
  });
  final List<PlusPlan> plans;
  final bool available;
  final PlusBillingProvider provider;
  final bool canRestore;
  final bool canManage;
}

abstract class PlusBillingGateway {
  Future<PlusOffering> load();
  Future<void> subscribe(PlusPlan plan);
  Future<void> restore();
  Future<void> manage();
  void dispose() {}
}

class PlusPurchaseCancelled implements Exception {
  const PlusPurchaseCancelled();
}
