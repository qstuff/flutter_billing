import 'dart:async';

import 'package:flutter/services.dart';
import 'package:synchronized/synchronized.dart';

/// A single product that can be purchased by a user in app.
class BillingProduct {
  BillingProduct({
    this.identifier,
    this.price,
    this.introductoryPrice,
    this.title,
    this.description,
    this.currency,
    this.amount,
  })  : assert(identifier != null),
        assert(price != null),
        assert(title != null),
        assert(description != null),
        assert(currency != null),
        assert(amount != null);

  /// Unique product identifier.
  final String identifier;

  /// Localized formatted product price including currency sign. e.g. $2.49.
  final String price;

  /// Localized formatted introductory product price including currency sign. e.g. $2.49.
  final String introductoryPrice;

  /// Localized product title.
  final String title;

  /// Localized product description.
  final String description;

  /// ISO 4217 currency code for price.
  final String currency;

  /// Price in 100s. e.g. $2.49 equals 249.
  final int amount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BillingProduct &&
          runtimeType == other.runtimeType &&
          identifier == other.identifier &&
          price == other.price &&
          introductoryPrice == other.introductoryPrice &&
          title == other.title &&
          description == other.description &&
          currency == other.currency &&
          amount == other.amount;

  @override
  int get hashCode =>
      identifier.hashCode ^
      price.hashCode ^
      introductoryPrice.hashCode ^
      title.hashCode ^
      description.hashCode ^
      currency.hashCode ^
      amount.hashCode;

  @override
  String toString() {
    return 'BillingProduct{sku: $identifier, price: $price, introductoryPrice: $introductoryPrice, title: $title, '
        'description: $description, currency: $currency, amount: $amount}';
  }
}

/// our flutter equivalent of a purchase
/// (https://developer.android.com/reference/com/android/billingclient/api/Purchase.html)
class Purchase {
  Purchase({
    this.orderId,
    this.packageName,
    this.identifier,
    this.purchaseToken,
    this.purchaseTime,
    this.expiresTime,
    this.autorenewal,
  }) : assert(identifier != null);

  final String orderId;
  final String packageName;
  final String identifier;
  final String purchaseToken;
  final int purchaseTime;
  final int expiresTime;
  final String autorenewal;

  @override
  String toString() {
    return 'Purchase{order: $orderId, package: $packageName, sku: $identifier,  '
        'token: $purchaseToken, purchaseTime: $purchaseTime, expiresTime: $expiresTime, autorenewal: $autorenewal';
  }
}

/// A billing error callback to be called when any of billing operations fail.
typedef void BillingErrorCallback(Exception e);

/// Billing plugin to enable communication with billing API in iOS and Android.
class Billing {
  static const MethodChannel _channel = const MethodChannel('flutter_billing');

  Billing({BillingErrorCallback onError}) : _onError = onError;

  final BillingErrorCallback _onError;
  final Map<String, BillingProduct> _cachedProducts = new Map();
  final Set<Purchase> _purchasedProducts = new Set();
  bool _purchasesFetched = false;
  final Set<Purchase> _subscribedProducts = new Set();
  bool _subscriptionsFetched = false;

  /// Products details of supplied product identifiers.
  ///
  /// Returns a list of products available to the app for a purchase.
  ///
  /// Note the behavior may differ from iOS and Android. Android most likely to throw in a case
  /// of error, while iOS would return a list of only products that are available. In a case of
  /// error, it would return simply empty list.

  Future<List<BillingProduct>> getProducts(List<String> identifiers, String type) {
    assert(identifiers != null);

    if (_cachedProducts.keys.toSet().containsAll(identifiers)) {
      return new Future.value(identifiers.map((identifier) => _cachedProducts[identifier]).toList());
    }

    return synchronized(this, () async {
      final Map<String, BillingProduct> products = new Map.fromIterable(
        await _channel.invokeMethod('fetchProducts', {'identifiers': identifiers, 'type': type}),
        key: (product) => product['identifier'],
        value: (product) => _convertToBillingProduct(product),
      );
      _cachedProducts.addAll(products);
      return products.values.toList();
    });
  }

  /// Product details of supplied product identifier.
  ///
  /// Returns a product details or null if one is not available or error occurred.
  Future<BillingProduct> getProduct(String identifier, String type) async {
    final List<BillingProduct> products = await getProducts(<String>[identifier], type);
    return products.firstWhere((product) => product.identifier == identifier, orElse: () => null);
  }

  /// Purchased products identifiers.
  ///
  /// Returns products identifiers that are already purchased.
  Future<Set<Purchase>> getPurchases() {
    if (_purchasesFetched) {
      return new Future.value(new Set.from(_purchasedProducts));
    }
    return synchronized(this, () async {
      final Map<String, Purchase> purchases = new Map.fromIterable(
        await _channel.invokeMethod('fetchPurchases'),
        key: (purchase) => purchase['orderId'],
        value: (purchase) => _convertToPurchase(purchase),
      );
      _purchasedProducts.addAll(purchases.values);
      _purchasesFetched = true;
      return _purchasedProducts;
    });
  }

  /// Validate if a product is purchased.
  ///
  /// Returns true if a product is purchased, otherwise false.
  Future<bool> isPurchased(String identifier) async {
    assert(identifier != null);
    final Set<Purchase> purchases = await getPurchases();
    return purchases.where((Purchase purchase) => purchase.identifier == identifier).isNotEmpty;
  }

  /// Purchase a product.
  /// [identifier] id of the product to purchase.
  /// [appSharedSecret] Apples app shared secret. Only for Apple, ignored for Android.
  ///
  /// This would trigger platform UI to walk a user through steps of purchasing the product.
  /// Returns updated list of product identifiers that have been purchased.
  Future<bool> purchase(String identifier, String appSharedSecret) async {
    assert(identifier != null);
    assert(appSharedSecret != null);

    final bool purchased = await isPurchased(identifier);
    if (purchased) {
      return new Future.value(true);
    }

    return synchronized(this, () async {
      final Map<String, Purchase> purchases = new Map.fromIterable(
        await _channel.invokeMethod('purchase', {'identifier': identifier, 'app_shared_secret': appSharedSecret}),
        key: (purchase) => purchase['orderId'],
        value: (purchase) => _convertToPurchase(purchase),
      );
      _purchasedProducts.addAll(purchases.values);
      _purchasesFetched = true;
      final bool purchased = await isPurchased(identifier);
      return purchased;
    });
  }

  /// Subscribed products identifiers.
  ///
  /// Returns products identifiers that are already subscribed.
  Future<Set<Purchase>> getSubscriptions() {
    if (_subscriptionsFetched) {
      return new Future.value(new Set.from(_subscribedProducts));
    }

    return synchronized(this, () async {
      final Map<String, Purchase> purchases = new Map.fromIterable(
        await _channel.invokeMethod('fetchSubscriptions'),
        key: (purchase) => purchase['orderId'],
        value: (purchase) {
          return _convertToPurchase(purchase);
        },
      );
      _subscribedProducts.addAll(purchases.values);
      _subscriptionsFetched = true;
      return _subscribedProducts;
    });
  }

  /// Validate if a product is purchased.
  ///
  /// Returns true if a product is purchased, otherwise false.
  Future<bool> isSubscribed(String identifier, int subscriptionPeriodMillis) async {
    assert(identifier != null);
    assert(subscriptionPeriodMillis != null);

    final DateTime now = new DateTime.now();
    final Set<Purchase> purchases = await getSubscriptions();

    return purchases.where((Purchase purchase) {
      final DateTime expirationDate =
          new DateTime.fromMillisecondsSinceEpoch((purchase.purchaseTime + subscriptionPeriodMillis).toInt());

      return purchase.identifier == identifier && purchase.autorenewal == "true" ||
          (purchase.autorenewal == "false" && expirationDate.isAfter(now));
    }).isNotEmpty;
  }

  /// Subscribe a product.
  ///
  /// This would trigger platform UI to walk a user through steps of purchasing the product.
  /// Returns updated list of product identifiers that have been purchased.
  Future<bool> subscribe(String identifier, int subscriptionPeriodMillis) async {
    assert(identifier != null);
    assert(subscriptionPeriodMillis != null);

    final bool purchased = await isSubscribed(identifier, subscriptionPeriodMillis);
    if (purchased) {
      return new Future.value(true);
    }

    return synchronized(this, () async {
      final Map<String, Purchase> purchases = new Map.fromIterable(
        await _channel.invokeMethod('subscribe', {'identifier': identifier}),
        key: (purchase) => purchase['orderId'],
        value: (purchase) => _convertToPurchase(purchase),
      );
      _subscribedProducts.addAll(purchases.values);
      _subscriptionsFetched = true;
      final bool purchased = await isSubscribed(identifier, subscriptionPeriodMillis);
      return purchased;
    });
  }
}

BillingProduct _convertToBillingProduct(Map<dynamic, dynamic> product) {
  assert(product != null);
  return new BillingProduct(
    identifier: product['identifier'],
    price: product['price'],
    introductoryPrice: product['introductoryPrice'],
    title: product['title'],
    description: product['description'],
    currency: product['currency'],
    amount: product['amount'],
  );
}

Purchase _convertToPurchase(Map<dynamic, dynamic> purchase) {
  assert(purchase != null);
  final num purchaseTime = purchase['purchaseTime'];
  final num expiresTime = purchase['expiresTime'];
  return new Purchase(
    orderId: purchase['orderId'],
    packageName: purchase['packageName'],
    identifier: purchase['identifier'],
    purchaseToken: purchase['purchaseToken'],
    purchaseTime: purchaseTime?.toInt() ?? 0,
    expiresTime: expiresTime?.toInt() ?? 0,
    autorenewal: purchase['autorenewal'],
  );
}
