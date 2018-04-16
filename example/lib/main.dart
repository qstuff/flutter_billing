import 'dart:async';
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

  void _initBilling() {
    print("initBilling()");

    Billing billing = new Billing();

    billing.getProducts(<String>['my.product.id', 'my.other.product.id',],
        'subs').then((billingProducts) {
      print("initBilling(): got products: ${billingProducts.length}");

    }, onError: (Object o) {
      print("initBilling(): got an error");
    });

    print("_initBilling(): getSubscriptions():");

    billing.getSubscriptions().then((subscriptions) {
      print("initBilling(): subscriptions: ${subscriptions.length}");
    }, onError: (Object o) {
      print("initBilling(): getSubscriptions(): got an error");
    });
  }


}
