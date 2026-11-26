import AVFoundation
import UIKit

final class PairingQrScanner: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  private let session = AVCaptureSession()
  private let captureQueue = DispatchQueue(label: "dev.leeef.pairing-camera")
  private var completion: ((String?, String?) -> Void)?
  private var preview: AVCaptureVideoPreviewLayer?

  init(completion: @escaping (String?, String?) -> Void) {
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    let cancel = UIButton(type: .system)
    cancel.setTitle("取消", for: .normal)
    cancel.tintColor = .white
    cancel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
    cancel.layer.cornerRadius = 8
    cancel.addTarget(self, action: #selector(cancelScan), for: .touchUpInside)
    cancel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(cancel)

    let label = UILabel()
    label.text = "扫描另一台设备显示的 Leeef 配对二维码"
    label.textColor = .white
    label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
    label.textAlignment = .center
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)
    NSLayoutConstraint.activate([
      cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      cancel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
      cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
      label.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard preview == nil, completion != nil else { return }
    guard let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
    else { return finish(error: "无法打开相机。") }
    session.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else { return finish(error: "此设备无法扫描二维码。") }
    session.addOutput(output)
    guard output.availableMetadataObjectTypes.contains(.qr) else {
      return finish(error: "此设备无法扫描二维码。")
    }
    output.setMetadataObjectsDelegate(self, queue: .main)
    output.metadataObjectTypes = [.qr]

    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.videoGravity = .resizeAspectFill
    preview.frame = view.bounds
    view.layer.insertSublayer(preview, at: 0)
    self.preview = preview
    captureQueue.async { [session] in session.startRunning() }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    preview?.frame = view.bounds
  }

  func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
    if let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue {
      finish(text: code)
    }
  }

  @objc private func cancelScan() { finish() }

  private func finish(text: String? = nil, error: String? = nil) {
    guard let completion else { return }
    self.completion = nil
    captureQueue.async { [session] in session.stopRunning() }
    dismiss(animated: true) { completion(text, error) }
  }
}
