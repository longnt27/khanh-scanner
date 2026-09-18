import ARKit
import AVFoundation
import ImageIO
import SceneKit
import UIKit
import Vision

protocol ScannerV2ViewControllerDelegate: AnyObject {
    func scannerV2ViewController(_ controller: ScannerV2ViewController, didFinishWith pages: [UIImage])
    func scannerV2ViewControllerDidCancel(_ controller: ScannerV2ViewController)
    func scannerV2ViewController(_ controller: ScannerV2ViewController, didFailWith error: Error)
}

enum ScannerV2Error: LocalizedError {
    case unsupported
    case highResolutionCaptureFailed
    case documentDetectionFailed
    case perspectiveCorrectionFailed

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "Scanner V2 requires AR world tracking."
        case .highResolutionCaptureFailed:
            "The camera could not capture a high-resolution page."
        case .documentDetectionFailed:
            "The document could not be detected clearly. Try again."
        case .perspectiveCorrectionFailed:
            "The captured page could not be corrected. Try again."
        }
    }
}

final class ScannerV2ViewController: UIViewController {
    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    weak var delegate: ScannerV2ViewControllerDelegate?

    private let sceneView = ARSCNView(frame: .zero)
    private let documentLayer = CAShapeLayer()
    private let statusLabel = UILabel()
    private let pageCountLabel = UILabel()
    private let lastPageView = UIImageView()
    private let shutterButton = UIButton(type: .custom)
    private let doneButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    private let analysisQueue = DispatchQueue(label: "com.longnt27.KhanhScanner.scanner-v2-analysis")
    private var configuration: ARWorldTrackingConfiguration?
    private var pages: [UIImage] = []
    private var latestQuadrilateral: ScannerV2Quadrilateral?
    private var latestReadiness: ScannerV2CaptureReadiness = .noDocument
    private var stabilityTracker = ScannerV2StabilityTracker()
    private var cameraMotionTracker = ScannerV2CameraMotionTracker()
    private var pageChangeDetector = ScannerV2PageChangeDetector()
    private var lastAnalysisTimestamp: TimeInterval = 0
    private var lastCaptureTimestamp: TimeInterval = 0
    private var missingDocumentFrames = 0
    private var isAnalyzing = false
    private var isCapturing = false
    private var isFinishing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureInterface()
        startSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sceneView.frame = view.bounds
        documentLayer.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    private func configureInterface() {
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.automaticallyUpdatesLighting = false
        view.addSubview(sceneView)
        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        documentLayer.fillColor = UIColor.systemGreen.withAlphaComponent(0.08).cgColor
        documentLayer.strokeColor = UIColor.systemYellow.cgColor
        documentLayer.lineWidth = 3
        documentLayer.lineJoin = .round
        view.layer.addSublayer(documentLayer)

        statusLabel.textAlignment = .center
        statusLabel.textColor = .white
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.layer.cornerRadius = 12
        statusLabel.clipsToBounds = true
        statusLabel.numberOfLines = 2

        pageCountLabel.textColor = .white
        pageCountLabel.font = .preferredFont(forTextStyle: .headline)
        pageCountLabel.textAlignment = .center

        lastPageView.contentMode = .scaleAspectFill
        lastPageView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        lastPageView.layer.cornerRadius = 8
        lastPageView.layer.borderWidth = 1
        lastPageView.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
        lastPageView.clipsToBounds = true

        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 36
        shutterButton.layer.borderWidth = 5
        shutterButton.layer.borderColor = UIColor.white.withAlphaComponent(0.65).cgColor
        shutterButton.addTarget(self, action: #selector(captureManually), for: .touchUpInside)

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.tintColor = .white
        doneButton.addTarget(self, action: #selector(finishScanning), for: .touchUpInside)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancelScanning), for: .touchUpInside)

        [statusLabel, pageCountLabel, lastPageView, shutterButton, doneButton, cancelButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),

            doneButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            doneButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),

            pageCountLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageCountLabel.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),

            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalTo: shutterButton.widthAnchor),

            lastPageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            lastPageView.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            lastPageView.widthAnchor.constraint(equalToConstant: 54),
            lastPageView.heightAnchor.constraint(equalToConstant: 72),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -22),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        updatePageUI()
        updateStatus(.noDocument)
    }

    private func startSession() {
        guard Self.isSupported else {
            fail(with: ScannerV2Error.unsupported)
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        if let format = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
            configuration.videoFormat = format
        }
        self.configuration = configuration

        sceneView.session.delegate = self
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    @objc private func captureManually() {
        guard let quadrilateral = latestQuadrilateral, !isCapturing else {
            updateStatus(.noDocument)
            return
        }
        capturePage(using: quadrilateral)
    }

    @objc private func finishScanning() {
        guard !pages.isEmpty, !isFinishing else { return }
        isFinishing = true
        sceneView.session.pause()
        delegate?.scannerV2ViewController(self, didFinishWith: pages)
    }

    @objc private func cancelScanning() {
        guard !isFinishing else { return }
        isFinishing = true
        sceneView.session.pause()
        delegate?.scannerV2ViewControllerDidCancel(self)
    }

    private func analyze(frame: ARFrame, cameraStable: Bool) {
        guard !isAnalyzing else { return }
        isAnalyzing = true

        let pixelBuffer = frame.capturedImage
        analysisQueue.async { [weak self] in
            guard let self else { return }
            defer {
                DispatchQueue.main.async { [weak self] in
                    self?.isAnalyzing = false
                }
            }

            do {
                let request = VNDetectDocumentSegmentationRequest()
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
                try handler.perform([request])

                guard let observation = request.results?.first else {
                    DispatchQueue.main.async { [weak self] in
                        self?.handleMissingDocument()
                    }
                    return
                }

                let quadrilateral = ScannerV2Quadrilateral(
                    topLeft: observation.topLeft,
                    topRight: observation.topRight,
                    bottomRight: observation.bottomRight,
                    bottomLeft: observation.bottomLeft
                )

                let sharpness = ScannerV2ImageProcessor.cgImage(
                    from: pixelBuffer,
                    orientation: .right
                ).map(ScannerV2ImageProcessor.sharpnessScore(of:)) ?? 0

                DispatchQueue.main.async { [weak self] in
                    self?.handle(
                        quadrilateral: quadrilateral,
                        sharpness: sharpness,
                        frame: frame,
                        cameraStable: cameraStable
                    )
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.handleMissingDocument()
                }
            }
        }
    }

    private func handle(
        quadrilateral: ScannerV2Quadrilateral,
        sharpness: Float,
        frame: ARFrame,
        cameraStable: Bool
    ) {
        missingDocumentFrames = 0
        latestQuadrilateral = quadrilateral

        let documentStable = stabilityTracker.append(quadrilateral)
        let planeValidation = planeValidation(for: quadrilateral, frame: frame)
        let captureDevice = ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera

        let readiness = ScannerV2CaptureGate.evaluate(
            hasDocument: true,
            documentStable: documentStable,
            cameraStable: cameraStable,
            planeScore: planeValidation.score,
            planeAvailable: planeValidation.available,
            focusAdjusting: captureDevice?.isAdjustingFocus ?? false,
            exposureAdjusting: captureDevice?.isAdjustingExposure ?? false,
            sharpnessScore: sharpness
        )
        latestReadiness = readiness
        draw(quadrilateral, frame: frame, readiness: readiness)
        updateStatus(readiness)

        let now = CACurrentMediaTime()
        if readiness == .ready,
           !isCapturing,
           now - lastCaptureTimestamp > 1.0,
           pageChangeDetector.canCapture(quadrilateral) {
            capturePage(using: quadrilateral)
        }
    }

    private func handleMissingDocument() {
        latestQuadrilateral = nil
        latestReadiness = .noDocument
        stabilityTracker.reset()
        missingDocumentFrames += 1
        if missingDocumentFrames >= 3 {
            pageChangeDetector.reset()
        }
        documentLayer.path = nil
        updateStatus(.noDocument)
    }

    private func capturePage(using liveQuadrilateral: ScannerV2Quadrilateral) {
        guard !isCapturing else { return }
        isCapturing = true
        shutterButton.isEnabled = false
        statusLabel.text = "Capturing…"

        sceneView.session.captureHighResolutionFrame { [weak self] frame, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.completeCaptureFailure(error)
                }
                return
            }

            guard let frame else {
                DispatchQueue.main.async {
                    self.completeCaptureFailure(ScannerV2Error.highResolutionCaptureFailed)
                }
                return
            }

            self.analysisQueue.async {
                do {
                    let request = VNDetectDocumentSegmentationRequest()
                    let handler = VNImageRequestHandler(
                        cvPixelBuffer: frame.capturedImage,
                        orientation: .right
                    )
                    try handler.perform([request])

                    guard let observation = request.results?.first else {
                        DispatchQueue.main.async {
                            self.completeCaptureFailure(ScannerV2Error.documentDetectionFailed)
                        }
                        return
                    }

                    let quadrilateral = ScannerV2Quadrilateral(
                        topLeft: observation.topLeft,
                        topRight: observation.topRight,
                        bottomRight: observation.bottomRight,
                        bottomLeft: observation.bottomLeft
                    )

                    if let cgImage = ScannerV2ImageProcessor.cgImage(
                        from: frame.capturedImage,
                        orientation: .right
                    ), ScannerV2ImageProcessor.sharpnessScore(of: cgImage) < 0.18 {
                        DispatchQueue.main.async {
                            self.completeCaptureFailure(ScannerV2Error.highResolutionCaptureFailed)
                        }
                        return
                    }

                    guard let corrected = ScannerV2ImageProcessor.correctedImage(
                        from: frame.capturedImage,
                        quadrilateral: quadrilateral,
                        orientation: .right
                    ) else {
                        DispatchQueue.main.async {
                            self.completeCaptureFailure(ScannerV2Error.perspectiveCorrectionFailed)
                        }
                        return
                    }

                    DispatchQueue.main.async {
                        self.pages.append(corrected)
                        self.pageChangeDetector.markCaptured(liveQuadrilateral)
                        self.lastCaptureTimestamp = CACurrentMediaTime()
                        self.isCapturing = false
                        self.stabilityTracker.reset()
                        self.updatePageUI()
                        self.updateStatus(.holdSteady)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.completeCaptureFailure(error)
                    }
                }
            }
        }
    }

    private func completeCaptureFailure(_ error: Error) {
        isCapturing = false
        shutterButton.isEnabled = true
        let alert = UIAlertController(
            title: "Try that page again",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func planeValidation(
        for quadrilateral: ScannerV2Quadrilateral,
        frame: ARFrame
    ) -> (available: Bool, score: Float) {
        let points = quadrilateral.points.map { viewPoint(for: $0, frame: frame) }
        let results: [ARRaycastResult] = points.compactMap { point in
            guard let query = sceneView.raycastQuery(
                from: point,
                allowing: .existingPlaneInfinite,
                alignment: .any
            ) else {
                return nil
            }
            return sceneView.session.raycast(query).first
        }

        guard results.count == 4 else { return (false, 0) }

        let planeAnchors = results.compactMap { $0.anchor as? ARPlaneAnchor }
        guard planeAnchors.count == 4,
              let firstID = planeAnchors.first?.identifier,
              planeAnchors.allSatisfy({ $0.identifier == firstID }) else {
            return (false, 0)
        }

        let worldPoints = results.map { result -> SIMD3<Float> in
            let column = result.worldTransform.columns.3
            return SIMD3<Float>(column.x, column.y, column.z)
        }
        return (true, ScannerV2PlaneGeometry.rectangleScore3D(worldPoints))
    }

    private func draw(
        _ quadrilateral: ScannerV2Quadrilateral,
        frame: ARFrame,
        readiness: ScannerV2CaptureReadiness
    ) {
        let points = quadrilateral.points.map { viewPoint(for: $0, frame: frame) }
        guard let first = points.first else {
            documentLayer.path = nil
            return
        }

        let path = UIBezierPath()
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.close()

        documentLayer.path = path.cgPath
        let ready = readiness == .ready
        documentLayer.strokeColor = (ready ? UIColor.systemGreen : UIColor.systemYellow).cgColor
        documentLayer.fillColor = (ready ? UIColor.systemGreen : UIColor.systemYellow)
            .withAlphaComponent(0.08).cgColor
    }

    private func viewPoint(for visionPoint: CGPoint, frame: ARFrame) -> CGPoint {
        let imageNormalized = CGPoint(x: visionPoint.x, y: 1 - visionPoint.y)
        let transform = frame.displayTransform(for: .portrait, viewportSize: sceneView.bounds.size)
        let viewNormalized = imageNormalized.applying(transform)
        return CGPoint(
            x: viewNormalized.x * sceneView.bounds.width,
            y: viewNormalized.y * sceneView.bounds.height
        )
    }

    private func updateStatus(_ readiness: ScannerV2CaptureReadiness) {
        latestReadiness = readiness
        statusLabel.text = readiness.statusText
        shutterButton.alpha = latestQuadrilateral == nil || isCapturing ? 0.45 : 1
        shutterButton.isEnabled = latestQuadrilateral != nil && !isCapturing
    }

    private func updatePageUI() {
        pageCountLabel.text = pages.isEmpty ? "" : "\(pages.count) page\(pages.count == 1 ? "" : "s")"
        lastPageView.image = pages.last
        lastPageView.isHidden = pages.isEmpty
        doneButton.isEnabled = !pages.isEmpty
        doneButton.alpha = pages.isEmpty ? 0.45 : 1
    }

    private func fail(with error: Error) {
        guard !isFinishing else { return }
        isFinishing = true
        sceneView.session.pause()
        delegate?.scannerV2ViewController(self, didFailWith: error)
    }
}

extension ScannerV2ViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !isFinishing else { return }

        let cameraStable = cameraMotionTracker.append(frame.camera.transform)
        guard frame.timestamp - lastAnalysisTimestamp >= 0.12 else { return }
        lastAnalysisTimestamp = frame.timestamp
        analyze(frame: frame, cameraStable: cameraStable)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.fail(with: error)
        }
    }
}

private extension ScannerV2CaptureReadiness {
    var statusText: String {
        switch self {
        case .noDocument:
            "Find a document"
        case .holdSteady:
            "Hold steady"
        case .alignDocument:
            "Align the page"
        case .waitForCamera:
            "Focusing…"
        case .tooSoft:
            "Hold steady for a sharper scan"
        case .ready:
            "Ready"
        }
    }
}
