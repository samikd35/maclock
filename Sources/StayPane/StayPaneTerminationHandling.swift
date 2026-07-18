import Foundation

@MainActor
protocol StayPaneTerminationHandling: AnyObject {
    func handleQuitRequest() -> Bool
    func prepareForSystemTermination()
}
