# Changelog

## Unreleased

- **feat: `redeemCode` — result-based offer code redemption on iOS 27+.** Uses
  `AppStore.presentOfferCodeRedeemSheet(from:options:)` (works on macCatalyst too,
  unlike the old `(in:)` path). The redeemed transaction is ingested exactly like
  a purchase (`processedTransactionIds` + `emitTransactionUpdate`, delivered to JS
  through the usual `approved` path); the callback resolves on success and rejects
  with a `[errorCode, message]` array on failure or user cancellation, reusing the
  existing CdvPurchase error codes (userCancelled → 6777006 PAYMENT_CANCELLED,
  networkError → 6777014 COMMUNICATION, notEntitled / notAvailableInStorefront /
  unsupported → 6777008 PAYMENT_NOT_ALLOWED, the rest → 6777010 UNKNOWN). Below
  iOS 27 the sheet opens fire-and-forget on the deprecated `(in:)` API and the
  callback resolves with no result — no cancel or error reporting (decided,
  FOV-511b). The iOS 27 branch is gated on `#if compiler(>=6.4)` (Xcode 27 SDK);
  apps built with older Xcode versions always take the fire-and-forget path.
  `RedeemOption` exists as of iOS 27 but the SDK defines no values yet — the
  options array is accepted for forward compatibility and ignored.

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
