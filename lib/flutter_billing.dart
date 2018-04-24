import 'dart:async';

import 'package:flutter/services.dart';
import 'package:synchronized/synchronized.dart';

/// A single product that can be purchased by a user in app.
class BillingProduct {
  BillingProduct({
    this.identifier,
    this.price,
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
          title == other.title &&
          description == other.description &&
          currency == other.currency &&
          amount == other.amount;

  @override
  int get hashCode =>
      identifier.hashCode ^
      price.hashCode ^
      title.hashCode ^
      description.hashCode ^
      currency.hashCode ^
      amount.hashCode;

  @override
  String toString() {
    return 'BillingProduct{sku: $identifier, price: $price, title: $title, '
        'description: $description, currency: $currency, amount: $amount}';
  }
}

/// our flutter equivalent of a purchase
/// (https://developer.android.com/reference/com/android/billingclient/api/Purchase.html)
class Purchase {

  Purchase({
    this.orderId,
    this.packageName,
    this.productId,
    this.purchaseToken,
    this.purchaseTime,
    this.autorenewal,
    }) : assert (orderId != null),
        assert (packageName != null),
        assert (productId != null),
        assert (purchaseToken != null);


  final String orderId;
  final String packageName;
  final String productId;
  final String purchaseToken;
  int          purchaseTime;
  final String autorenewal;

  @override
  String toString() {
    return 'Purchase{order: $orderId, package: $packageName, sku: $productId,  '
        'token: $purchaseToken, time: $purchaseTime, autorenewal: $autorenewal}';
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

  final Set<String> _purchasedProducts = new Set();
  bool _purchasesFetched = false;

  final Map<String, Purchase> _fetchedSubscriptions = new Map();
  final Set<String> _subscribedProducts = new Set();


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
      return new Future.value(
          identifiers.map((identifier) => _cachedProducts[identifier]).toList());
    }

    return synchronized(this, () async {
      try {
        final Map<String, BillingProduct> products = new Map.fromIterable(
          await _channel.invokeMethod('fetchProducts', {'identifiers': identifiers, 'type': type} ),
          key: (product) => product['identifier'],
          value: (product) => new BillingProduct(
                identifier: product['identifier'],
                price: product['price'],
                title: product['title'],
                description: product['description'],
                currency: product['currency'],
                amount: product['amount'],
              ),
        );

        _cachedProducts.addAll(products);
        return products.values.toList();
      } catch (e) {
        if (_onError != null) _onError(e);
        return <BillingProduct>[];
      }
    });
  }

  /// Product details of supplied product identifier.
  ///
  /// Returns a product details or null if one is not available or error occurred.
  Future<BillingProduct> getProduct(String identifier, String type) async {
    final List<BillingProduct> products = await getProducts(<String>[identifier], type);
    return products.firstWhere((product) => product.identifier == identifier, orElse: () => null);
  }


  /// Subscribed products identifiers.
  ///
  /// Returns products identifiers that are already subscribed.
  Future<List<Purchase>> getSubscriptions() {

    return synchronized(this, () async {
      try {
        final Map<String, Purchase> purchases = new Map.fromIterable(
          await _channel.invokeMethod('fetchSubscriptions'),
          key: (purchase) => purchase ['orderId'],
          value: (purchase) => new Purchase(
            orderId: purchase['orderId'],
            packageName: purchase['packageName'],
            productId: purchase['productId'],
            purchaseToken: purchase['purchaseToken'],
            purchaseTime: purchase['purchaseTime'],
            autorenewal: purchase['autorenewal'],
          ),
      );

        _fetchedSubscriptions.addAll(purchases);
        return purchases.values.toList();
      } catch (e) {
        if (_onError != null) _onError(e);
        return <Purchase>[];
      }
    });
  }

  /// Validate if a product is purchased.
  ///
  /// Returns true if a product is purchased, otherwise false.
  Future<bool> isSubscribed(String identifier, int subscriptionPeriodMillis) async {

    final List<Purchase> purchases = await getSubscriptions();
    bool isSubscribed = false;

    purchases.forEach((purchase) {

      // is product id in subscription list?
      if (purchase.productId == identifier) {

        // is subscription active?
        if (purchase.autorenewal == "false") {

          DateTime now = new DateTime.now();
          DateTime expirationDate = new DateTime.fromMillisecondsSinceEpoch(purchase.purchaseTime + subscriptionPeriodMillis);

          // is expired
          if (expirationDate.isAfter(now)) {
            isSubscribed = true;
          }
        } else {
          isSubscribed =  true;
        }
      }
    });
    return isSubscribed;
  }

  /// Subscribe a product.
  ///
  /// This would trigger platform UI to walk a user through steps of purchasing the product.
  /// Returns updated list of product identifiers that have been purchased.
  Future<bool> subscribe(String identifier) {
    assert(identifier != null);
    if (_subscribedProducts.contains(identifier)) {
      return new Future.value(true);
    }
    return synchronized(this, () async {
      try {
        final List subscriptions = await _channel.invokeMethod('subscribe', {'identifier': identifier});
        _subscribedProducts.addAll(subscriptions.cast());
        return subscriptions.contains(identifier);
      } catch (e) {
        if (_onError != null) _onError(e);
        return false;
      }
    });
  }


  /// Purchased products identifiers.
  ///
  /// Returns products identifiers that are already purchased.
  Future<Set<String>> getPurchases() {
    if (_purchasesFetched) {
      return new Future.value(new Set.from(_purchasedProducts));
    }
    return synchronized(this, () async {
      try {
        final List purchases = await _channel.invokeMethod('fetchPurchases');
        _purchasedProducts.addAll(purchases.cast());
        _purchasesFetched = true;
        return _purchasedProducts;
      } catch (e) {
        if (_onError != null) _onError(e);
        return new Set.identity();
      }
    });
  }

  /// Validate if a product is purchased.
  ///
  /// Returns true if a product is purchased, otherwise false.
  Future<bool> isPurchased(String identifier) async {
    assert(identifier != null);
    final Set<String> purchases = await getPurchases();
    return purchases.contains(identifier);
  }

  /// Purchase a product.
  ///
  /// This would trigger platform UI to walk a user through steps of purchasing the product.
  /// Returns updated list of product identifiers that have been purchased.
  Future<bool> purchase(String identifier) {
    assert(identifier != null);
    if (_purchasedProducts.contains(identifier)) {
      return new Future.value(true);
    }
    return synchronized(this, () async {
      try {
        final List purchases = await _channel.invokeMethod('purchase', {'identifier': identifier});
        _purchasedProducts.addAll(purchases.cast());
        return purchases.contains(identifier);
      } catch (e) {
        if (_onError != null) _onError(e);
        return false;
      }
    });
  }
}
