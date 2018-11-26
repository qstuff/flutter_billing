import 'package:flutter/material.dart';
import 'package:flutter_billing/flutter_billing.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final Billing billing = new Billing();

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: new Text('Plugin example app'),
        ),
        body: new Column(
          children: <Widget>[
            FlatButton(
              onPressed: _fetchProducts,
              child: const Text('fetchProducts'),
              padding: const EdgeInsets.all(20.0),
            ),
            FlatButton(
              onPressed: _purchase,
              child: const Text('buy something'),
              padding: const EdgeInsets.all(20.0),
            ),
            FlatButton(
              onPressed: _fetchPurchases,
              child: const Text('fetchPurchases'),
              padding: const EdgeInsets.all(20.0),
            ),
          ],
        ),
      ),
    );
  }

  void _fetchProducts() {
    billing.getProducts(
      <String>[
        'Test_Abo_01',
        'Test_Abo_02',
        'Test_Abo_03',
      ],
      'subs',
    ).then((List<BillingProduct> billingProducts) {
      billingProducts.forEach((BillingProduct product) {
        print("_fetchProducts: got products: $product");
      });
    }, onError: (dynamic error) {
      print("_fetchProducts): got an error: $error");
    });
  }

  void _purchase() {
    billing.purchase('Test_Abo_01', 'secret').then((bool success) {
      print("_purchase: success: $success");
    }, onError: (dynamic error) {
      print("_purchase: purchase(): got an error: $error");
    });
  }

  void _fetchPurchases() {
    billing.getPurchases().then((purchases) {
      print("_fetchPurchases: purchases: $purchases");
    }, onError: (dynamic error) {
      print("_fetchPurchases: getPurchases(): got an error: $error");
    });
  }
}
