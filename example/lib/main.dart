import 'package:flutter/material.dart';
import 'package:flutter_billing/flutter_billing.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  initState() {
    super.initState();
    _initBilling();
  }

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: new Text('Plugin example app'),
        ),
        body: new Center(
          child: new Text('Billing.'),
        ),
      ),
    );
  }

  void _initBilling() async {
    Billing billing = new Billing();

    billing.getProducts(<String>['coach_yourself_training'], 'subs').then((billingProducts) {
      print("initBilling(): got products: ${billingProducts}");
    }, onError: (dynamic error) {
      print("initBilling(): got an error: $error");
    });

    billing.getPurchases().then((Set<String> purchases) {
      print("initBilling(): purchases: $purchases");
    }, onError: (dynamic error) {
      print("initBilling(): getPurchases(): got an error: $error");
    });

    final bool isPurchased = await billing.isPurchased('coach_yourself_training');
    print('coach_yourself_training isPurchased: $isPurchased');

    if (!isPurchased)
      billing.purchase('coach_yourself_training').then((bool purchased) {
        print('coach_yourself_training purchased: $purchased');
      });
  }
}
