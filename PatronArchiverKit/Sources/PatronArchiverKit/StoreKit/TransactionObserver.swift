#if canImport(StoreKit)
import OSLog
import StoreKit

public final actor TransactionObserver {
    private static let logger = Logger(
        subsystem: Logger.moduleSubsystem,
        category: "TransactionObserver"
    )

    private let updatesTask: Task<Void, Never>

    public init() {
        updatesTask = Task.detached(priority: .background) {
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    Self.logger.info(
                        "Finished pending transaction: \(transaction.productID)"
                    )
                case .unverified(_, let error):
                    Self.logger.warning(
                        "Unverified transaction: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    deinit {
        updatesTask.cancel()
    }
}
#endif
