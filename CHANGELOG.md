# Changelog

## 1.1.0

- **fix: remove 27 deprecation warnings with cordova-ios 8.** Replaced the legacy
  `CDVCommandStatus_OK` / `CDVCommandStatus_ERROR` constants with the Swift enum
  cases `CDVCommandStatus.ok` / `CDVCommandStatus.error`, which cordova-ios 8
  deprecation notes explicitly recommend. Both cases exist since cordova-ios 7.0.0,
  the plugin's declared minimum, so no version guard is needed
  ([PR #5](https://github.com/j3k0/cordova-plugin-purchase-storekit2/pull/5)).
- **minor version bump** as a precaution: while the change is verified against the
  cordova-ios 7.0.0 and 8.0.0 headers, building against unofficial/patched older
  Cordova versions could behave differently.

## 1.0.6

- **fix: send `"UpFront"` for pay-up-front offers.** `paymentModeToString` returned
  `"PayUpFront"`, a value the iaptic server doesn't recognize. It affected both
  `introPricePaymentMode` and `discounts[].paymentMode` (introductory and promotional
  offers). Same fix as [cordova-plugin-purchase #1740](https://github.com/j3k0/cordova-plugin-purchase/pull/1740).

## 1.0.5

- **Surface `isEligibleForIntroOffer` on loaded products.** `load()` now populates
  `introPriceEligible` on each product dictionary with StoreKit 2's authoritative
  eligibility answer (`Product.SubscriptionInfo.isEligibleForIntroOffer`). The
  `cordova-plugin-purchase` adapter consumes this to short-circuit the receipt-based
  determiner under SK2, fixing the "always eligible for the free trial" bug reported
  in [cordova-plugin-purchase #1694](https://github.com/j3k0/cordova-plugin-purchase/issues/1694).
  `productToDictionary` is now `async` (already called from a `Task` block).

## 1.0.4

- chore: bump version to 1.0.4

## 1.0.3

- fix: add `getStorefront` using `Storefront.current`

## 1.0.2

- Earlier versions — see git history.
