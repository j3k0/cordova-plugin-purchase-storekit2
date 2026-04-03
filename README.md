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

## License

MIT
