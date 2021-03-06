#import "BillingPlugin.h"
#import "Purchase.h"

@interface BillingPlugin ()

@property(atomic, retain) NSMutableArray<FlutterResult> *fetchPurchases;
@property(atomic, retain) NSMutableDictionary<NSValue *, FlutterResult> *fetchProducts;
@property(atomic, retain) NSMutableDictionary<SKPayment *, FlutterResult> *requestedPayments;
@property(atomic, retain) NSArray<SKProduct *> *products;
@property(atomic, retain) NSMutableSet<Purchase *> *purchases;
@property(nonatomic, retain) FlutterMethodChannel *channel;
@property(nonatomic, retain) NSString *appSharedSecret;

@end

typedef void (^VerifyReceiptsCompletionBlock)(BOOL success, NSError *error, BOOL useSandbox);

@implementation BillingPlugin

@synthesize fetchPurchases;
@synthesize fetchProducts;
@synthesize requestedPayments;
@synthesize products;
@synthesize purchases;
@synthesize channel;
@synthesize appSharedSecret;

+ (void)registerWithRegistrar:(NSObject <FlutterPluginRegistrar> *)registrar
{
    BillingPlugin *instance = [[BillingPlugin alloc] init];
    instance.channel = [FlutterMethodChannel methodChannelWithName:@"flutter_billing" binaryMessenger:[registrar messenger]];
    [[SKPaymentQueue defaultQueue] addTransactionObserver:instance];
    [registrar addMethodCallDelegate:instance channel:instance.channel];
}

- (instancetype)init
{
    self = [super init];

    self.fetchPurchases = [[NSMutableArray alloc] init];
    self.fetchProducts = [[NSMutableDictionary alloc] init];
    self.requestedPayments = [[NSMutableDictionary alloc] init];
    self.products = [[NSArray alloc] init];
    self.purchases = [[NSMutableSet alloc] init];

    return self;
}

- (void)dealloc
{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
    [self.channel setMethodCallHandler:nil];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result
{
    if ([@"fetchProducts" isEqualToString:call.method])
    {
        NSArray<NSString *> *identifiers = (NSArray<NSString *> *) call.arguments[@"identifiers"];
        if (identifiers == nil || [identifiers count] == 0)
        {
            result([FlutterError errorWithCode:@"ERROR" message:@"Invalid or missing argument 'identifiers'" details:nil]);
            return;
        }

        [self fetchProducts:identifiers result:result];
    }
    else if ([@"fetchPurchases" isEqualToString:call.method])
    {
        [self fetchPurchases:result];
    }
    else if ([@"purchase" isEqualToString:call.method])
    {
        NSString *identifier = (NSString *) call.arguments[@"identifier"];
        if (identifier == nil)
        {
            result([FlutterError errorWithCode:@"ERROR" message:@"Invalid or missing argument 'identifier'" details:nil]);
            return;
        }
        [self purchase:identifier result:result];
    }
    else if ([@"appSharedSecret" isEqualToString:call.method])
    {
        NSString *appSharedSecret = (NSString *) call.arguments[@"app_shared_secret"];
        if (appSharedSecret == nil)
        {
            result([FlutterError errorWithCode:@"ERROR" message:@"Invalid or missing argument 'app_shared_secret'" details:nil]);
            return;
        }
        [self setAppSharedSecret:appSharedSecret];
    }
    else
    {
        result(FlutterMethodNotImplemented);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions
{
    [self purchased:[transactions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SKPaymentTransaction *transaction, NSDictionary *bindings) {
        return [transaction transactionState] == SKPaymentTransactionStatePurchased;
    }]]];
    [self restored:[transactions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SKPaymentTransaction *transaction, NSDictionary *bindings) {
        return [transaction transactionState] == SKPaymentTransactionStateRestored;
    }]]];
    [self failed:[transactions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SKPaymentTransaction *transaction, NSDictionary *bindings) {
        return [transaction transactionState] == SKPaymentTransactionStateFailed;
    }]]];
}

- (void)productsRequest:(nonnull SKProductsRequest *)request didReceiveResponse:(nonnull SKProductsResponse *)response
{
    NSValue *key = [NSValue valueWithNonretainedObject:request];
    FlutterResult result = fetchProducts[key];
    if (result == nil)
    {return;}
    [fetchProducts removeObjectForKey:key];

    NSNumberFormatter *currencyFormatter = [[NSNumberFormatter alloc] init];
    [currencyFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];

    products = [response products];

    NSMutableArray<NSDictionary *> *allValues = [[NSMutableArray alloc] init];
    [[response products] enumerateObjectsUsingBlock:^(SKProduct *product, NSUInteger idx, BOOL *stop)
    {
        [currencyFormatter setLocale:product.priceLocale];

        if (product.productIdentifier == nil ||
            product.localizedTitle == nil ||
            product.localizedDescription == nil ||
            product.priceLocale == nil ||
            product.price == nil)
        {
            return;
        }

        NSMutableDictionary<NSString *, id> *values = [[NSMutableDictionary alloc] init];
        values[@"identifier"] = product.productIdentifier;
        values[@"price"] = [currencyFormatter stringFromNumber:product.price];
        if (@available(iOS 11_2, *))
        {
            if (product.introductoryPrice != nil && product.introductoryPrice.price != nil)
            {
                values[@"introductoryPrice"] = [currencyFormatter stringFromNumber:product.introductoryPrice.price];
            }
        }
        values[@"title"] = product.localizedTitle;
        values[@"description"] = product.localizedDescription;
        if (@available(iOS 10, *))
        {
            if (product.priceLocale.currencyCode != nil)
            {
                values[@"currency"] = product.priceLocale.currencyCode;
            }
        }
        values[@"amount"] = @((int) ceil(product.price.doubleValue * 100));

        [allValues addObject:values];
    }];

    result(allValues);
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error
{
    NSValue *key = [NSValue valueWithNonretainedObject:request];
    FlutterResult result = fetchProducts[key];
    if (result != nil)
    {
        [fetchProducts removeObjectForKey:key];
        result([FlutterError errorWithCode:@"ERROR" message:@"Failed to make IAP request!" details:nil]);
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    [self verifyReceiptsProduction:^(BOOL success, NSError *error, BOOL useSandbox)
    {
        if (useSandbox)
        {
            [self verifyReceiptsSandbox:^(BOOL success, NSError *error, BOOL useSandbox)
            {
                [self handleValidationResult:success error:error];
            }];
        }
        else
        {
            [self handleValidationResult:success error:error];
        }
    }];
}

- (void)handleValidationResult:(BOOL)success error:(NSError *)error
{
    NSArray<FlutterResult> *results = [NSArray arrayWithArray:self.fetchPurchases];
    [self.fetchPurchases removeAllObjects];

    if (!success)
    {
        [results enumerateObjectsUsingBlock:^(FlutterResult result, NSUInteger idx, BOOL *stop)
        {
            result([FlutterError errorWithCode:@"ERROR" message:@"Failed to verify receipts!" details:error == nil ? nil : error.localizedDescription]);
        }];
        return;
    }

    NSMutableArray *list = [[NSMutableArray alloc] init];
    for (Purchase *purchase in self.purchases)
    {
        if (purchase.productId == nil)
        {
            continue;
        }

        NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
        result[@"identifier"] = purchase.productId;
        result[@"purchaseTime"] = @(purchase.purchaseDate);
        result[@"expiresTime"] = @(purchase.expiresDate);
        [list addObject:result];
    }

    [results enumerateObjectsUsingBlock:^(FlutterResult result, NSUInteger idx, BOOL *stop)
    {
        result(list);
    }];
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    FlutterError *resultError = [FlutterError errorWithCode:@"ERROR" message:@"Failed to restore purchases!" details:nil];
    NSArray<FlutterResult> *results = [NSArray arrayWithArray:fetchPurchases];
    [fetchPurchases removeAllObjects];

    [results enumerateObjectsUsingBlock:^(FlutterResult result, NSUInteger idx, BOOL *stop)
    {
        result(resultError);
    }];
}

- (void)fetchProducts:(NSArray<NSString *> *)identifiers result:(FlutterResult)result
{
    SKProductsRequest *request = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:identifiers]];
    [request setDelegate:self];
    [fetchProducts setObject:result forKey:[NSValue valueWithNonretainedObject:request]];
    [request start];
}

- (void)fetchPurchases:(FlutterResult)result
{
    [fetchPurchases addObject:result];
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (void)purchase:(NSString *)identifier result:(FlutterResult)result
{
    SKProduct *product;
    for (SKProduct *p in products)
    {
        if ([p.productIdentifier isEqualToString:identifier])
        {
            product = p;
            break;
        }
    }

    if (product != nil)
    {
        SKPayment *payment = [SKPayment paymentWithProduct:product];
        [requestedPayments setObject:result forKey:payment];
        [[SKPaymentQueue defaultQueue] addPayment:payment];
    }
    else
    {
        result([FlutterError errorWithCode:@"ERROR" message:@"Failed to make a payment!" details:nil]);
    }
}

- (void)purchased:(NSArray<SKPaymentTransaction *> *)transactions
{
    NSMutableArray<FlutterResult> *results = [[NSMutableArray alloc] init];

    [transactions enumerateObjectsUsingBlock:^(SKPaymentTransaction *transaction, NSUInteger idx, BOOL *stop)
    {
        Purchase *purchase = [Purchase purchaseWithProductId:transaction.payment.productIdentifier
                                                purchaseDate:0
                                                 expiresDate:0];
        [self.purchases addObject:purchase];
        FlutterResult result = self.requestedPayments[transaction.payment];
        if (result != nil)
        {
            [self.requestedPayments removeObjectForKey:transaction.payment];
            [results addObject:result];
        }
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    }];

    NSMutableArray *list = [[NSMutableArray alloc] init];
    for (Purchase *purchase in purchases)
    {
        if (purchase.productId == nil)
        {
            continue;
        }

        NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
        result[@"identifier"] = purchase.productId;
        result[@"purchaseTime"] = @(purchase.purchaseDate);
        result[@"expiresTime"] = @(purchase.expiresDate);
        [list addObject:result];
    }

    [results enumerateObjectsUsingBlock:^(FlutterResult result, NSUInteger idx, BOOL *stop)
    {
        result(list);
    }];
}

- (void)restored:(NSArray<SKPaymentTransaction *> *)transactions
{
    [transactions enumerateObjectsUsingBlock:^(SKPaymentTransaction *transaction, NSUInteger idx, BOOL *stop)
    {
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    }];
}

- (void)failed:(NSArray<SKPaymentTransaction *> *)transactions
{
    [transactions enumerateObjectsUsingBlock:^(SKPaymentTransaction *transaction, NSUInteger idx, BOOL *stop)
    {
        FlutterResult result = self.requestedPayments[transaction.payment];
        if (result != nil)
        {
            [self.requestedPayments removeObjectForKey:transaction.payment];
            result([FlutterError errorWithCode:@"ERROR" message:@"Failed to make a payment!" details:nil]);
        }
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    }];
}

- (void)verifyReceiptsProduction:(VerifyReceiptsCompletionBlock)completionBlock
{
    [self verifyReceipts:@"https://buy.itunes.apple.com/verifyReceipt" completio:completionBlock];
}

- (void)verifyReceiptsSandbox:(VerifyReceiptsCompletionBlock)completionBlock
{
    [self verifyReceipts:@"https://sandbox.itunes.apple.com/verifyReceipt" completio:completionBlock];
}

- (void)verifyReceipts:(NSString *)urlString completio:(VerifyReceiptsCompletionBlock)completionBlock
{
    NSData *receipts = [self loadReceipts];
    if (receipts == nil)
    {
        completionBlock(YES, nil, NO);
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    request.HTTPMethod = @"POST";

    NSString *base64EncodedString = [receipts base64EncodedStringWithOptions:0];
    NSDictionary *dictionary = @{@"receipt-data"            : base64EncodedString,
                                 @"password"                : self.appSharedSecret,
                                 @"exclude-old-transactions": @YES};
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:kNilOptions error:&error];

    if (error)
    {
        completionBlock(NO, error, NO);
        return;
    }

    NSURLSessionUploadTask *uploadTask = [session uploadTaskWithRequest:request
                                                               fromData:data
                                                      completionHandler:^(NSData *data,
                                                                          NSURLResponse *response,
                                                                          NSError *error)
                                                      {
                                                          NSError *jsonError;
                                                          NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                                                               options:NSJSONReadingMutableContainers
                                                                                                                 error:&jsonError];

                                                          if (error)
                                                          {
                                                              completionBlock(NO, error, NO);
                                                              return;
                                                          }

                                                          int statusCode = [json[@"status"] intValue];
                                                          if (statusCode == 21007)
                                                          {
                                                              // This receipt is from the test environment, but it was sent to the production environment for verification.
                                                              // Send it to the test environment instead.
                                                              completionBlock(NO, error, YES);
                                                              return;
                                                          }

                                                          NSArray *latestReceiptInfo = json[@"latest_receipt_info"];
                                                          for (NSDictionary *info in latestReceiptInfo)
                                                          {
                                                              double now = [[NSDate date] timeIntervalSince1970];
                                                              double expiresDateMs = [info[@"expires_date_ms"] doubleValue] / 1000.0;
                                                              if (expiresDateMs > now)
                                                              {
                                                                  Purchase *purchase = [Purchase purchaseWithProductId:info[@"product_id"]
                                                                                                          purchaseDate:[info[@"purchase_date_ms"] doubleValue]
                                                                                                           expiresDate:[info[@"expires_date_ms"] doubleValue]];
                                                                  [self.purchases addObject:purchase];
                                                              }
                                                          }
                                                          completionBlock(YES, nil, NO);
                                                          return;
                                                      }];
    [uploadTask resume];
}

- (NSData *)loadReceipts
{
    NSData *data = nil;
    @try
    {
        NSURL *url = [[NSBundle mainBundle] appStoreReceiptURL];
        data = [NSData dataWithContentsOfURL:url];
    } @catch (NSException *e)
    {
        NSLog(@"Error loading receipt data: %@", e);
    }
    return data;
}

@end
