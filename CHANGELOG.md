# Changelog

## Unreleased

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
