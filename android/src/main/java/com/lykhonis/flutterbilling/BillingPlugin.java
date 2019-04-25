package com.lykhonis.flutterbilling;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;
import android.util.Log;

import com.android.billingclient.api.BillingClient;
import com.android.billingclient.api.BillingClient.BillingResponse;
import com.android.billingclient.api.BillingClient.SkuType;
import com.android.billingclient.api.BillingClientStateListener;
import com.android.billingclient.api.BillingFlowParams;
import com.android.billingclient.api.Purchase;
import com.android.billingclient.api.PurchasesUpdatedListener;
import com.android.billingclient.api.SkuDetails;
import com.android.billingclient.api.SkuDetailsParams;
import com.android.billingclient.api.SkuDetailsResponseListener;
import com.android.billingclient.api.ConsumeResponseListener;


import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;

public final class BillingPlugin implements MethodCallHandler {
    private final String TAG = BillingPlugin.class.getSimpleName();

    private final Activity activity;
    private final BillingClient billingClient;
    private final Map<String, Result> pendingPurchaseRequests;
    private final Map<String, Boolean> requestsToConsume;

    private boolean billingServiceConnected;

    public static void registerWith(Registrar registrar) {
        final MethodChannel channel = new MethodChannel(registrar.messenger(), "flutter_billing");
        channel.setMethodCallHandler(new BillingPlugin(registrar.activity()));
    }

    private BillingPlugin(Activity activity) {
        this.activity = activity;

        pendingPurchaseRequests = new HashMap<>();
        requestsToConsume = new HashMap<>();

        billingClient = BillingClient.newBuilder(activity)
                                     .setListener(new BillingListener())
                                     .build();

        final Application application = activity.getApplication();

        application.registerActivityLifecycleCallbacks(new LifecycleCallback() {
            @Override
            public void onActivityDestroyed(Activity activity) {
                if (activity == BillingPlugin.this.activity) {
                    application.unregisterActivityLifecycleCallbacks(this);

                    stopServiceConnection();
                }
            }
        });

        startServiceConnection(new Request() {
            @Override
            public void execute() {
                Log.d(TAG, "Billing service is ready.");
            }

            @Override
            public void failed() {
                Log.d(TAG, "Failed to setup billing service!");
            }
        });
    }

    @Override
    public void onMethodCall(MethodCall methodCall, Result result) {
        if ("fetchProducts".equals(methodCall.method)) {
            fetchProducts(
                methodCall.<List<String>>argument("identifiers"),
                methodCall.<String>argument("type"),
                result);
        } else if ("fetchPurchases".equals(methodCall.method)) {
            fetchPurchases(result);
        } else if ("purchase".equals(methodCall.method)) {
            purchase(
                methodCall.<String>argument("identifier"),
                methodCall.<Boolean>argument("consume"),
                result);
        }  else if ("fetchSubscriptions".equals(methodCall.method)) {
            fetchSubscriptions(result);
        } else if ("subscribe".equals(methodCall.method)) {
            subscribe(methodCall.<String>argument("identifier"), result);
        } else if ("appSharedSecret".equals(methodCall.method)) {
            result.success(null);
        } else {
            result.notImplemented();
        }
    }

    private void fetchProducts(final List<String> identifiers, final String type, final Result result) {

        executeServiceRequest(new Request() {

            @Override
            public void execute() {
                billingClient.querySkuDetailsAsync(
                    SkuDetailsParams.newBuilder()
                                    .setSkusList(identifiers)
                                    .setType(type)
                                    .build(),
                    new SkuDetailsResponseListener() {

                        @Override
                        public void onSkuDetailsResponse(int responseCode, List<SkuDetails> skuDetailsList) {
                            if (responseCode == BillingResponse.OK) {
                                final List<Map<String, Object>> products = convertSkuDetailsToListOfMaps(skuDetailsList);
                                result.success(products);
                            } else {
                                result.error("ERROR", "fetchProducts(): Failed to fetch products!", null);
                            }
                        }
                    });
            }

            @Override
            public void failed() {
                result.error("UNAVAILABLE", "Billing service is unavailable!", null);
            }
        });
    }

    private void fetchPurchases(final Result result) {
        executeServiceRequest(new Request() {

            @Override
            public void execute() {
                final Purchase.PurchasesResult purchasesResult = billingClient.queryPurchases(SkuType.INAPP);
                final int responseCode = purchasesResult.getResponseCode();

                if (responseCode == BillingResponse.OK) {
                    result.success(convertPurchasesToListOfMaps(purchasesResult.getPurchasesList()));
                } else {
                    result.error("ERROR", "Failed to query purchases with error " + responseCode, null);
                }
            }

            @Override
            public void failed() {
                result.error("UNAVAILABLE", "Billing service is unavailable!", null);
            }
        });
    }

    private void purchase(final String identifier, final Boolean consume, final Result result) {

        requestsToConsume.put(identifier, consume);

        executeServiceRequest(new Request() {
            @Override
            public void execute() {
                final int responseCode = billingClient.launchBillingFlow(
                        activity,
                        BillingFlowParams.newBuilder()
                                         .setSku(identifier)
                                         .setType(SkuType.INAPP)
                                         .build());

                if (responseCode == BillingResponse.OK) {
                    Log.d(TAG, "purchase(): result: " + result.toString());
                    pendingPurchaseRequests.put(identifier, result);
                } else {
                    result.error("ERROR", "Failed to launch billing flow to purchase an item with error " + responseCode, null);
                }
            }

            @Override
            public void failed() {
                result.error("UNAVAILABLE", "Billing service is unavailable!", null);
            }
        });
    }

    /**
     * We need to pass back a list of purchases, since we need to check the purchaseTime against the
     * subscription period in case the subscription was revoked by the user.
     * If the subscription is revoked by the user it still appears in the purchases list, but with autorenewal set to false.
     * In that case the subscription is still valid until the end of the current subscrition period.
     * This verification is done on the dart side in flutter_billing.isSubscribed()
     *
     * @param result
     */
    private void fetchSubscriptions(final Result result) {
        executeServiceRequest(new Request() {
            @Override
            public void execute() {
                final Purchase.PurchasesResult purchasesResult = billingClient.queryPurchases(SkuType.SUBS);
                final int responseCode = purchasesResult.getResponseCode();

                if (responseCode == BillingResponse.OK) {
                    final List<Map<String, Object>> purchases =
                        convertPurchasesToListOfMaps(purchasesResult.getPurchasesList());
                    result.success(purchases);
                } else {
                    result.error("ERROR", "Failed to query purchases with error " + responseCode, null);
                }
            }

            @Override
            public void failed() {
                result.error("UNAVAILABLE", "Billing service is unavailable!", null);
            }
        });
    }

    private void subscribe(final String identifier, final Result result) {
        executeServiceRequest(new Request() {
            @Override
            public void execute() {
                final int responseCode = billingClient.launchBillingFlow(
                        activity,
                        BillingFlowParams.newBuilder()
                                .setSku(identifier)
                                .setType(SkuType.SUBS)
                                .build());

                if (responseCode == BillingResponse.OK) {
                    pendingPurchaseRequests.put(identifier, result);
                } else {
                    result.error("ERROR", "Failed to launch billing flow to subscribe an item with error " + responseCode, null);
                }
            }

            @Override
            public void failed() {
                result.error("UNAVAILABLE", "Billing service is unavailable!", null);
            }
        });
    }

    List<Map<String, Object>> convertSkuDetailsToListOfMaps(List<SkuDetails> details) {
        if (details == null) {
            return Collections.emptyList();
        }

        final List<Map<String, Object>> list = new ArrayList<>(details.size());
        for (SkuDetails detail : details) {
            list.add(convertSkuDetailToMap(detail));
        }
        return list;
    }

    static Map<String, Object> convertSkuDetailToMap(SkuDetails detail) {
        final Map<String, Object> product = new HashMap<>();
        product.put("identifier", detail.getSku());
        product.put("price", detail.getPrice());
        product.put("introductoryPrice", detail.getIntroductoryPrice());
        product.put("title", detail.getTitle());
        product.put("description", detail.getDescription());
        product.put("currency", detail.getPriceCurrencyCode());
        product.put("amount", detail.getPriceAmountMicros() / 10_000L);
        return product;
    }

    private List<Map<String, Object>> convertPurchasesToListOfMaps(List<Purchase> purchases) {
        if (purchases == null) {
            return Collections.emptyList();
        }

        final List<Map<String, Object>> list = new ArrayList<>(purchases.size());
        for (Purchase purchase : purchases) {
            list.add(convertPurchaseToMap(purchase));
        }
        return list;
    }

    private static Map<String, Object> convertPurchaseToMap(Purchase purchase) {
        final Map<String, Object> product = new HashMap<>();
        product.put("orderId", purchase.getOrderId());
        product.put("packageName", purchase.getPackageName());
        product.put("identifier", purchase.getSku());
        product.put("purchaseToken", purchase.getPurchaseToken());
        product.put("purchaseTime", purchase.getPurchaseTime());
        product.put("autorenewal", purchase.isAutoRenewing() ? "true" : "false");
        return product;
    }

    private void stopServiceConnection() {
        if (billingClient.isReady()) {
            Log.d(TAG, "Stopping billing service.");

            billingClient.endConnection();

            billingServiceConnected = false;
        }
    }

    private void startServiceConnection(final Request request) {
        billingClient.startConnection(new BillingClientStateListener() {
            @Override
            public void onBillingSetupFinished(@BillingResponse int billingResponseCode) {
                Log.d(TAG, "Billing service was setup with code " + billingResponseCode);

                if (billingResponseCode == BillingResponse.OK) {
                    billingServiceConnected = true;

                    request.execute();
                } else {
                    request.failed();
                }
            }

            @Override
            public void onBillingServiceDisconnected() {
                Log.d(TAG, "Billing service was disconnected!");

                billingServiceConnected = false;
            }
        });
    }

    private void executeServiceRequest(Request request) {
        if (billingServiceConnected) {
            request.execute();
        } else {
            startServiceConnection(request);
        }
    }

    final class BillingListener implements PurchasesUpdatedListener {

        @Override
        public void onPurchasesUpdated(int resultCode, List<Purchase> purchases) {

            if (purchases != null) {
                Log.d(TAG, "onPurchasesUpdated(): num: " + purchases.size());

                for (Purchase p : purchases) {
                    Boolean consume = requestsToConsume.remove(p.getSku());
                    if (consume != null && consume == true) {
                        Log.d("BillingPlugin", "onPurchasesUpdated(): consuming. token " + p.getPurchaseToken());

                        billingClient.consumeAsync(p.getPurchaseToken(), new ConsumeResponseListener() {
                            @Override
                            public void onConsumeResponse(int responseCode, String purchaseToken) {
                                Log.d("BillingPlugin", "onConsumeResponse(): consumed: " + purchaseToken);
                            }
                        });
                    }
                }
            }

            if (resultCode == BillingResponse.OK && purchases != null) {

                final List<Map<String, Object>> identifiers = convertPurchasesToListOfMaps(purchases);
                for (final Map<String, Object> next : identifiers) {
                    Log.d("BillingPlugin", "onPurchasesUpdated(): id: " + next);

                    final Result result = pendingPurchaseRequests.remove(next.get("identifier"));
                    if (result != null) {
                        result.success(identifiers);
                    }
                }
            } else {
                for (Result result : pendingPurchaseRequests.values()) {
                    result.error("ERROR", "Failed to purchase an item with error " + resultCode, null);
                }

                pendingPurchaseRequests.clear();
            }
        }
    }

    interface Request {
        void execute();
        void failed();
    }

    static class LifecycleCallback implements Application.ActivityLifecycleCallbacks {
        @Override
        public void onActivityCreated(Activity activity, Bundle savedInstanceState) { }

        @Override
        public void onActivityStarted(Activity activity) { }

        @Override
        public void onActivityResumed(Activity activity) { }

        @Override
        public void onActivityPaused(Activity activity) { }

        @Override
        public void onActivityStopped(Activity activity) { }

        @Override
        public void onActivitySaveInstanceState(Activity activity, Bundle outState) { }

        @Override
        public void onActivityDestroyed(Activity activity) { }
    }
}
