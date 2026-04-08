import StoreKit

@available(iOS 15.0, *)
@objc(StoreKit2Plugin) class StoreKit2Plugin: CDVPlugin {

    // MARK: - State

    private var products: [String: Product] = [:]
    private var unfinishedTransactions: [String: Transaction] = [:]
    private var transactionObserverTask: Task<Void, Never>?
    private var isInitialized = false
    private var debugEnabled = false

    /// Transaction IDs already emitted to JS. Prevents duplicate delivery when
    /// both purchase() and Transaction.updates deliver the same transaction.
    private var processedTransactionIds: Set<UInt64> = []

    // Pending transaction updates received before JS is ready
    private var pendingTransactionUpdates: [(state: String, errorCode: Int, errorText: String,
        transactionId: String, productId: String, transactionReceipt: String,
        originalTransactionId: String, transactionDate: String, discountId: String,
        expirationDate: String, jwsRepresentation: String)] = []

    // MARK: - Lifecycle

    override func pluginInitialize() {
        super.pluginInitialize()
        startTransactionObserver()
    }

    override func dispose() {
        transactionObserverTask?.cancel()
        processedTransactionIds.removeAll()
        super.dispose()
    }

    // MARK: - Transaction Observer

    private func startTransactionObserver() {
        transactionObserverTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                await self.handleTransactionUpdate(result)
            }
        }
    }

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            guard !processedTransactionIds.contains(transaction.id) else {
                log("Transaction.updates: skipping duplicate id=\(transaction.id)")
                return
            }
            processedTransactionIds.insert(transaction.id)
            log("Transaction.updates: verified id=\(transaction.id) product=\(transaction.productID) expires=\(String(describing: transaction.expirationDate))")
            await emitTransactionUpdate(transaction, state: "PaymentTransactionStatePurchased", jwsRepresentation: result.jwsRepresentation)
        case .unverified(let transaction, let error):
            log("Transaction.updates: REJECTED unverified id=\(transaction.id) product=\(transaction.productID) error=\(error)")
        }
    }

    // MARK: - JS Bridge Methods

    @objc func setup(_ command: CDVInvokedUrlCommand) {
        isInitialized = true
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc func debug(_ command: CDVInvokedUrlCommand) {
        debugEnabled = true
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc func autoFinish(_ command: CDVInvokedUrlCommand) {
        // No-op for now — SK2 transaction finishing is handled explicitly by the JS bridge.
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc func canMakePayments(_ command: CDVInvokedUrlCommand) {
        // AppStore.canMakePayments is synchronous in StoreKit 2
        if AppStore.canMakePayments {
            let result = CDVPluginResult(status: CDVCommandStatus_OK)
            commandDelegate.send(result, callbackId: command.callbackId)
        } else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR,
                messageAs: "Device is not allowed to make payments")
            commandDelegate.send(result, callbackId: command.callbackId)
        }
    }

    // MARK: - Product Loading

    @objc func load(_ command: CDVInvokedUrlCommand) {
        guard let productIds = command.arguments[0] as? [String] else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR,
                messageAs: "Invalid product IDs")
            commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        Task {
            do {
                let storeProducts = try await Product.products(for: Set(productIds))
                var validProducts: [[String: Any]] = []
                var invalidIds: [String] = []

                let loadedIds = Set(storeProducts.map { $0.id })
                for id in productIds {
                    if !loadedIds.contains(id) {
                        invalidIds.append(id)
                    }
                }

                for product in storeProducts {
                    self.products[product.id] = product
                    validProducts.append(self.productToDictionary(product))
                }

                let response: [Any] = [validProducts, invalidIds]
                let result = CDVPluginResult(status: CDVCommandStatus_OK,
                    messageAs: response)
                self.commandDelegate.send(result, callbackId: command.callbackId)
            } catch {
                let result = CDVPluginResult(status: CDVCommandStatus_ERROR,
                    messageAs: error.localizedDescription)
                self.commandDelegate.send(result, callbackId: command.callbackId)
            }
        }
    }

    // MARK: - Transaction Helpers

    /// Finish any unfinished transactions whose subscription has already expired.
    /// Stale unfinished transactions can block product.purchase() from initiating
    /// a new purchase flow (confirmed on Apple Developer Forums).
    private func clearExpiredUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            if let expirationDate = transaction.expirationDate, expirationDate < Date() {
                log("clearExpired: finishing expired transaction id=\(transaction.id) product=\(transaction.productID) expired=\(expirationDate)")
                await transaction.finish()
                unfinishedTransactions.removeValue(forKey: String(transaction.id))
            }
        }
    }

    // MARK: - Purchase

    @objc func purchase(_ command: CDVInvokedUrlCommand) {
        guard let productId = command.arguments[0] as? String else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR,
                messageAs: "Missing product ID")
            commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        let applicationUsername = command.arguments[2] as? String
        let discountData = command.arguments[3] as? [String: Any]

        guard let product = products[productId] else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR,
                messageAs: "Product not loaded: \(productId)")
            commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        log("purchase: productId=\(productId) username=\(applicationUsername ?? "nil") hasDiscount=\(discountData != nil)")

        Task {
            do {
                var options: Set<Product.PurchaseOption> = []

                // Application account token (maps to applicationUsername)
                if let username = applicationUsername, !username.isEmpty {
                    if let uuid = UUID(uuidString: username) {
                        options.insert(.appAccountToken(uuid))
                    }
                }

                // Promotional offer discount
                if let discount = discountData,
                   let offerId = discount["id"] as? String,
                   let keyId = discount["key"] as? String,
                   let nonceString = discount["nonce"] as? String,
                   let nonce = UUID(uuidString: nonceString),
                   let signatureString = discount["signature"] as? String,
                   let timestampString = discount["timestamp"] as? String,
                   let timestamp = Int(timestampString) {
                    let signatureData = Data(base64Encoded: signatureString) ?? Data()
                    options.insert(.promotionalOffer(
                        offerID: offerId,
                        keyID: keyId,
                        nonce: nonce,
                        signature: signatureData,
                        timestamp: timestamp
                    ))
                }

                // Clear expired unfinished transactions that could block the purchase
                await self.clearExpiredUnfinishedTransactions()

                log("purchase: calling product.purchase() for \(productId)")
                let purchaseResult = try await product.purchase(options: options)

                switch purchaseResult {
                case .success(let verification):
                    switch verification {
                    case .verified(let transaction):
                        log("purchase: success verified id=\(transaction.id) product=\(transaction.productID) expires=\(String(describing: transaction.expirationDate))")
                        if transaction.productID != productId {
                            log("purchase: returned product \(transaction.productID) differs from requested \(productId) — likely a subscription downgrade")
                        }
                        // Mark as processed to prevent duplicate delivery via Transaction.updates
                        self.processedTransactionIds.insert(transaction.id)
                        self.unfinishedTransactions[String(transaction.id)] = transaction
                        await self.emitTransactionUpdate(transaction, state: "PaymentTransactionStatePurchased", jwsRepresentation: verification.jwsRepresentation)
                    case .unverified(let transaction, let error):
                        log("purchase: REJECTED unverified id=\(transaction.id) product=\(transaction.productID) error=\(error)")
                        self.emitPurchaseFailed(productId: productId,
                            errorCode: 6777010, message: "Transaction verification failed")
                    }
                    let result = CDVPluginResult(status: CDVCommandStatus_OK)
                    self.commandDelegate.send(result, callbackId: command.callbackId)

                case .pending:
                    log("purchase: pending for \(productId)")
                    self.emitSimpleUpdate(productId: productId, state: "PaymentTransactionStateDeferred")
                    let result = CDVPluginResult(status: CDVCommandStatus_OK)
                    self.commandDelegate.send(result, callbackId: command.callbackId)

                case .userCancelled:
                    log("purchase: userCancelled for \(productId)")
                    self.emitPurchaseFailed(productId: productId,
                        errorCode: 6777006, message: "Payment cancelled")
                    let result = CDVPluginResult(status: CDVCommandStatus_OK)
                    self.commandDelegate.send(result, callbackId: command.callbackId)

                @unknown default:
                    log("purchase: unknown result for \(productId)")
                    let result = CDVPluginResult(status: CDVCommandStatus_ERROR,
                        messageAs: "Unknown purchase result")
                    self.commandDelegate.send(result, callbackId: command.callbackId)
                }
            } catch {
                log("purchase: error for \(productId): \(error.localizedDescription)")
                self.emitPurchaseFailed(productId: productId,
                    errorCode: 6777010, message: error.localizedDescription)
                let result = CDVPluginResult(status: CDVCommandStatus_ERROR,
                    messageAs: error.localizedDescription)
                self.commandDelegate.send(result, callbackId: command.callbackId)
            }
        }
    }

    // MARK: - Finish Transaction

    @objc func finishTransaction(_ command: CDVInvokedUrlCommand) {
        guard let transactionId = command.arguments[0] as? String else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR,
                messageAs: "Missing transaction ID")
            commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        log("finishTransaction: id=\(transactionId) found=\(unfinishedTransactions[transactionId] != nil)")
        if let transaction = unfinishedTransactions[transactionId] {
            Task {
                await transaction.finish()
                log("finishTransaction: finished id=\(transactionId)")
                self.unfinishedTransactions.removeValue(forKey: transactionId)
                let result = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate.send(result, callbackId: command.callbackId)
            }
        } else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR,
                messageAs: "Cannot finish transaction [#CdvPurchase:100]")
            commandDelegate.send(result, callbackId: command.callbackId)
        }
    }

    // MARK: - Restore Purchases

    @objc func restoreCompletedTransactions(_ command: CDVInvokedUrlCommand) {
        Task {
            do {
                for await result in Transaction.currentEntitlements {
                    switch result {
                    case .verified(let transaction):
                        if transaction.isUpgraded {
                            self.log("restore: skipping upgraded transaction id=\(transaction.id) product=\(transaction.productID)")
                            continue
                        }
                        self.unfinishedTransactions[String(transaction.id)] = transaction
                        await self.emitTransactionUpdate(transaction, state: "PaymentTransactionStateRestored", jwsRepresentation: result.jwsRepresentation)
                    case .unverified(let transaction, let error):
                        self.log("restore: REJECTED unverified id=\(transaction.id) product=\(transaction.productID) error=\(error)")
                    }
                }
                // Signal restore completed
                self.evalJs("window.storekit2.restoreCompletedTransactionsFinished()")
            } catch {
                self.log("Restore failed: \(error.localizedDescription)")
                self.evalJs("window.storekit2.restoreCompletedTransactionsFailed(6777010)")
            }
        }
    }

    // MARK: - App Store Receipt (SK2 provides empty receipt, JWS is the replacement)

    @objc func appStoreReceipt(_ command: CDVInvokedUrlCommand) {
        // SK2 doesn't use monolithic receipts. Return empty receipt with bundle info.
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let numericVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let response: [Any] = ["", bundleId, version, Int(numericVersion) ?? 0, ""]
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc func appStoreRefreshReceipt(_ command: CDVInvokedUrlCommand) {
        // Same as above for SK2 — no monolithic receipt to refresh
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let numericVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let response: [Any] = ["", bundleId, version, Int(numericVersion) ?? 0, ""]
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Process Pending Transactions

    @objc func processPendingTransactions(_ command: CDVInvokedUrlCommand) {
        log("processPendingTransactions: \(pendingTransactionUpdates.count) pending")
        for update in pendingTransactionUpdates {
            log("  pending: id=\(update.transactionId) product=\(update.productId) state=\(update.state) expires=\(update.expirationDate)")
        }
        // Emit any pending transaction updates that arrived before JS was ready
        for update in pendingTransactionUpdates {
            evalTransactionUpdated(
                state: update.state, errorCode: update.errorCode, errorText: update.errorText,
                transactionId: update.transactionId, productId: update.productId,
                transactionReceipt: update.transactionReceipt,
                originalTransactionId: update.originalTransactionId,
                transactionDate: update.transactionDate, discountId: update.discountId,
                expirationDate: update.expirationDate, jwsRepresentation: update.jwsRepresentation)
        }
        pendingTransactionUpdates.removeAll()
        evalJs("window.storekit2.lastTransactionUpdated()")
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Manage Subscriptions / Billing

    @objc func manageSubscriptions(_ command: CDVInvokedUrlCommand) {
        Task { @MainActor in
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                try? await AppStore.showManageSubscriptions(in: scene)
            }
            let result = CDVPluginResult(status: CDVCommandStatus_OK)
            self.commandDelegate.send(result, callbackId: command.callbackId)
        }
    }

    @objc func manageBilling(_ command: CDVInvokedUrlCommand) {
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc func presentCodeRedemptionSheet(_ command: CDVInvokedUrlCommand) {
        #if !targetEnvironment(macCatalyst)
        Task { @MainActor in
            if #available(iOS 16.0, *) {
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    try? await AppStore.presentOfferCodeRedeemSheet(in: scene)
                }
            }
            let result = CDVPluginResult(status: CDVCommandStatus_OK)
            self.commandDelegate.send(result, callbackId: command.callbackId)
        }
        #else
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
        #endif
    }

    // MARK: - Helpers

    private func log(_ message: String) {
        if debugEnabled {
            NSLog("[StoreKit2Plugin] %@", message)
        }
    }

    private func productToDictionary(_ product: Product) -> [String: Any] {
        var dict: [String: Any] = [
            "id": product.id,
            "title": product.displayName,
            "description": product.description,
            "price": product.displayPrice,
            "priceMicros": NSDecimalNumber(decimal: product.price)
                .multiplying(by: 1000000).int64Value,
            "currency": product.priceFormatStyle.currencyCode,
            "countryCode": {
                if #available(iOS 16.0, *) {
                    return product.priceFormatStyle.locale.region?.identifier ?? ""
                } else {
                    return Locale.current.regionCode ?? ""
                }
            }(),
        ]

        if let subscription = product.subscription {
            let unit = subscription.subscriptionPeriod.unit
            let value = subscription.subscriptionPeriod.value
            dict["billingPeriod"] = value
            dict["billingPeriodUnit"] = periodUnitToString(unit)
            dict["group"] = product.subscription?.subscriptionGroupID

            // Introductory offer
            if let intro = subscription.introductoryOffer {
                dict["introPrice"] = intro.displayPrice
                dict["introPriceMicros"] = NSDecimalNumber(decimal: intro.price)
                    .multiplying(by: 1000000).int64Value
                dict["introPricePeriod"] = intro.period.value
                dict["introPricePeriodUnit"] = periodUnitToString(intro.period.unit)
                dict["introPricePaymentMode"] = paymentModeToString(intro.paymentMode)
            }

            // Promotional offers (discounts)
            var discounts: [[String: Any]] = []
            for offer in subscription.promotionalOffers {
                discounts.append([
                    "id": offer.id ?? "",
                    "type": "Subscription",
                    "price": offer.displayPrice,
                    "priceMicros": NSDecimalNumber(decimal: offer.price)
                        .multiplying(by: 1000000).int64Value,
                    "period": offer.period.value,
                    "periodUnit": periodUnitToString(offer.period.unit),
                    "paymentMode": paymentModeToString(offer.paymentMode),
                ])
            }
            if !discounts.isEmpty {
                dict["discounts"] = discounts
            }
        }

        return dict
    }

    private func periodUnitToString(_ unit: Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        @unknown default: return "Day"
        }
    }

    private func paymentModeToString(_ mode: Product.SubscriptionOffer.PaymentMode) -> String {
        switch mode {
        case .payAsYouGo: return "PayAsYouGo"
        case .payUpFront: return "PayUpFront"
        case .freeTrial: return "FreeTrial"
        default: return "PayAsYouGo"
        }
    }

    // MARK: - JS Communication

    /// Emit a transaction update to the JS bridge via evalJs.
    /// The signature matches the SK1 bridge's transactionUpdated() with additional SK2 fields.
    /// The JWS representation must be passed explicitly — it comes from VerificationResult, not Transaction.
    private func emitTransactionUpdate(_ transaction: Transaction, state: String, jwsRepresentation: String = "") async {
        let transactionId = String(transaction.id)
        let productId = transaction.productID
        let originalTransactionId = transaction.originalID != transaction.id
            ? String(transaction.originalID) : ""
        let transactionDate = transaction.purchaseDate.timeIntervalSince1970 * 1000
        let discountId = transaction.offerID ?? ""
        let expirationDate = transaction.expirationDate.map {
            String(Int($0.timeIntervalSince1970 * 1000))
        } ?? ""

        self.unfinishedTransactions[transactionId] = transaction

        if isInitialized {
            evalTransactionUpdated(
                state: state, errorCode: 0, errorText: "",
                transactionId: transactionId, productId: productId,
                transactionReceipt: "",
                originalTransactionId: originalTransactionId,
                transactionDate: String(Int(transactionDate)),
                discountId: discountId,
                expirationDate: expirationDate,
                jwsRepresentation: jwsRepresentation)
        } else {
            pendingTransactionUpdates.append((
                state: state, errorCode: 0, errorText: "",
                transactionId: transactionId, productId: productId,
                transactionReceipt: "",
                originalTransactionId: originalTransactionId,
                transactionDate: String(Int(transactionDate)),
                discountId: discountId,
                expirationDate: expirationDate,
                jwsRepresentation: jwsRepresentation))
        }
    }

    private func emitSimpleUpdate(productId: String, state: String) {
        evalTransactionUpdated(
            state: state, errorCode: 0, errorText: "",
            transactionId: "", productId: productId,
            transactionReceipt: "", originalTransactionId: "",
            transactionDate: "", discountId: "",
            expirationDate: "", jwsRepresentation: "")
    }

    private func emitPurchaseFailed(productId: String, errorCode: Int, message: String) {
        evalTransactionUpdated(
            state: "PaymentTransactionStateFailed",
            errorCode: errorCode, errorText: message,
            transactionId: "", productId: productId,
            transactionReceipt: "", originalTransactionId: "",
            transactionDate: "", discountId: "",
            expirationDate: "", jwsRepresentation: "")
    }

    private func evalTransactionUpdated(
        state: String, errorCode: Int, errorText: String,
        transactionId: String, productId: String, transactionReceipt: String,
        originalTransactionId: String, transactionDate: String, discountId: String,
        expirationDate: String, jwsRepresentation: String
    ) {
        let args = [
            jsonEscape(state),
            "\(errorCode)",
            jsonEscape(errorText),
            jsonEscape(transactionId),
            jsonEscape(productId),
            jsonEscape(transactionReceipt),
            jsonEscape(originalTransactionId),
            jsonEscape(transactionDate),
            jsonEscape(discountId),
            jsonEscape(expirationDate),
            jsonEscape(jwsRepresentation),
        ].joined(separator: ",")
        evalJs("window.storekit2.transactionUpdated(\(args))")
    }

    private func jsonEscape(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private func evalJs(_ js: String) {
        DispatchQueue.main.async {
            self.commandDelegate.evalJs(js)
        }
    }
}
