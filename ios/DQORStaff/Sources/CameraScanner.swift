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
    private let captureState = CameraCaptureState()
    private var preview: AVCaptureVideoPreviewLayer?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private let onCode: (String) -> Void
    private let status = UILabel()
    private let actions = UIStackView()
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
        status.accessibilityIdentifier = "cameraStatus"
        actions.axis = .vertical; actions.spacing = 12
        actions.addArrangedSubview(status)
        actions.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(actions)
        NSLayoutConstraint.activate([actions.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), actions.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), actions.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); visible = true; requestCamera() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); visible = false; stop() }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); preview?.frame = view.bounds
        if let connection = preview?.connection, let angle = rotation?.videoRotationAngleForHorizonLevelPreview,
           connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
    }
    @objc private func background() { stop() }
    @objc private func foreground() { if visible { requestCamera() } }
    private func resetActions() {
        for action in actions.arrangedSubviews where action !== status { actions.removeArrangedSubview(action); action.removeFromSuperview() }
    }
    private func button(_ title: String, action: Selector) {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal); button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        actions.addArrangedSubview(button)
    }
    private func requestCamera() {
        resetActions()
        #if targetEnvironment(simulator)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--scanner-camera-denied") { denied(); return }
        if ProcessInfo.processInfo.arguments.contains("--demo"), ProcessInfo.processInfo.arguments.contains("--scanner-rehearsal") {
            status.text = "Scanner rehearsal · synthetic codes only. Camera capture is unavailable in Simulator."
            button("Scan sample Alex", action: #selector(sampleAlex))
            button("Scan sample Taylor", action: #selector(sampleTaylor))
            button("Scan invalid sample", action: #selector(sampleInvalid))
            return
        }
        #endif
        status.text = "Camera capture is unavailable in Simulator. Use attendee search to try the demo."
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async { guard let self, self.visible else { return }; allowed ? self.start() : self.denied() }
            }
        default: denied()
        }
        #endif
    }
    #if DEBUG
    @objc private func sampleAlex() { receive("dqor-demo:demo-001") }
    @objc private func sampleTaylor() { receive("dqor-demo:demo-003") }
    @objc private func sampleInvalid() { receive("invalid-synthetic-code") }
    #endif
    private func denied() {
        stop()
        status.text = "Camera access is unavailable. Use attendee search, or enable camera access in Settings."
        button("Open camera settings", action: #selector(openSettings))
        button("Retry camera", action: #selector(retry))
    }
    @objc private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    @objc private func retry() { if visible { requestCamera() } }
    private func start() {
        guard visible, UIApplication.shared.applicationState == .active else { return }
        if !configured {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                status.text = "No rear camera is available. Use attendee search."; return
            }
            session.beginConfiguration(); session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.removeInput(input); session.commitConfiguration()
                status.text = "Scanning is unavailable. Use attendee search."; return
            }
            session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main)
            guard output.availableMetadataObjectTypes.contains(.qr) else {
                session.removeOutput(output); session.removeInput(input); session.commitConfiguration()
                status.text = "QR scanning is unavailable. Use attendee search."; return
            }
            output.metadataObjectTypes = [.qr]; session.commitConfiguration()
            let layer = AVCaptureVideoPreviewLayer(session: session); layer.videoGravity = .resizeAspectFill
            view.layer.insertSublayer(layer, at: 0); preview = layer; layer.frame = view.bounds
            rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
            configured = true; status.text = nil
        }
        let request = captureState.activate()
        let session = session, state = captureState
        queue.async { if state.current(request), !session.isRunning { session.startRunning() } }
    }
    func stop() {
        captureState.stop()
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }
    private func receive(_ value: String) {
        guard visible, UIApplication.shared.applicationState == .active else { return }
        onCode(value)
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        for object in objects {
            if let code = object as? AVMetadataMachineReadableCodeObject, code.type == .qr, let value = code.stringValue { receive(value) }
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

final class CameraCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var active = false
    func activate() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1; active = true
        return generation
    }
    func stop() {
        lock.lock(); defer { lock.unlock() }
        generation += 1; active = false
    }
    func current(_ request: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active && generation == request
    }
}
