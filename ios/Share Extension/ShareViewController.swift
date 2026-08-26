import receive_sharing_intent

final class ShareViewController: RSIShareViewController {
    override func shouldAutoRedirect() -> Bool { true }
    override var sendButtonTitle: String { "导入 Leeef Reader" }
}
