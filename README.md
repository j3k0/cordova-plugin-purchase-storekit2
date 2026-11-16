# cordova-plugin-purchase-storekit2

StoreKit 2 adapter for [cordova-plugin-purchase](https://github.com/j3k0/cordova-plugin-purchase). Uses Apple's modern StoreKit 2 API — see [Apple's documentation](https://developer.apple.com/storekit/) for details.

> **Capacitor users:** You don't need this plugin. Use [capacitor-plugin-cdv-purchase](https://github.com/j3k0/cordova-plugin-purchase/tree/master/capacitor) instead — StoreKit 2 support is built-in.

## Installation

Install alongside the main plugin:

```sh
cordova plugin add cordova-plugin-purchase-storekit2
```

That's it — the Apple AppStore adapter in cordova-plugin-purchase will automatically use StoreKit 2 when this plugin is present.

## Requirements

- **cordova-plugin-purchase** — must be installed alongside this plugin
- **cordova-ios 7+** — required for Swift 5.5 support
- **iOS 15+** — StoreKit 2 is only available on iOS 15 and later. On older devices, the main plugin falls back to StoreKit 1 automatically.

## Notes for contributors

The native `purchase` bridge expects `applicationUsername` (argument index `2`) to be a string parseable by `UUID(uuidString:)`. Apple's `Product.PurchaseOption.appAccountToken` requires a UUID; any other value is silently ignored and the purchase proceeds without an `appAccountToken`. The TypeScript layer in `cordova-plugin-purchase` (≥ 13.16) takes care of this by routing the value through `store.obfuscator` (defaults to a UUIDv3 derived from the raw username) before invoking the bridge — so app developers only configure `store.obfuscator` and don't need to format the value themselves.

## Offer code redemption

`store.redeemCode()` (cordova-plugin-purchase ≥ 13.21) presents Apple's offer code
redemption sheet through this extension. On iOS 27+ it uses the result-based
`AppStore.presentOfferCodeRedeemSheet(from:options:)` — the redeemed transaction
arrives through the usual `approved` event (ingested like a purchase), and the
returned promise reports user cancellation and errors with the existing
`CdvPurchase.ErrorCode` values. Below iOS 27 the sheet opens fire-and-forget on the
deprecated `(in:)` API — no cancel or error reporting. Apps must be built with the
iOS 27 SDK (Xcode 27) for the result-based path; older Xcode versions always take
the fire-and-forget path.

## License

MIT
