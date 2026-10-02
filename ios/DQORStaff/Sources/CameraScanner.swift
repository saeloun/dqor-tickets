import SwiftUI
import AVFoundation
import UIKit

struct CameraScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController { ScannerController(onCode: onCode) }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: ScannerController, coordinator: ()) { controller.stop() }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "org.dqor.staff.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private let onCode: (String) -> Void
    private let status = UILabel()
    private var visible = false
    private var configured = false
    init(onCode: @escaping (String) -> Void) { self.onCode = onCode; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is unsupported") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        status.textColor = .white; status.numberOfLines = 0; status.textAlignment = .center
        status.font = .preferredFont(forTextStyle: .body); status.adjustsFontForContentSizeCategory = true
        status.text = "Camera permission is required to scan tickets. You can also use attendee search."
        status.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(status)
        NSLayoutConstraint.activate([status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), status.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); visible = true; requestCamera() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); visible = false; stop() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    @objc private func background() { stop() }
    @objc private func foreground() { if visible { requestCamera() } }
    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async { guard let self, self.visible else { return }; allowed ? self.start() : self.denied() }
            }
        default: denied()
        }
    }
    private func denied() { status.text = "Camera access is unavailable. Use attendee search, or enable camera access in Settings." }
    private func start() {
        guard visible else { return }
        if !configured {
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                status.text = "No camera is available. Use attendee search. Simulator check-in supports synthetic attendees."; return
            }
            session.beginConfiguration(); session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { session.commitConfiguration(); status.text = "Scanning is unavailable. Use attendee search."; return }
            session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main)
            guard output.availableMetadataObjectTypes.contains(.qr) else { session.commitConfiguration(); status.text = "QR scanning is unavailable. Use attendee search."; return }
            output.metadataObjectTypes = [.qr]; session.commitConfiguration()
            let layer = AVCaptureVideoPreviewLayer(session: session); layer.videoGravity = .resizeAspectFill
            view.layer.insertSublayer(layer, at: 0); preview = layer; layer.frame = view.bounds
            configured = true; status.text = nil
        }
        let session = session
        queue.async { if !session.isRunning { session.startRunning() } }
    }
    func stop() { let session = session; queue.async { if session.isRunning { session.stopRunning() } } }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard visible, UIApplication.shared.applicationState == .active else { return }
        for object in objects {
            if let code = object as? AVMetadataMachineReadableCodeObject, code.type == .qr, let value = code.stringValue { onCode(value) }
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}
