import AVFoundation
import CoreImage
import ImageIO
import UIKit

protocol DocumentCameraViewControllerDelegate: AnyObject {
    func documentCameraViewController(_ controller: DocumentCameraViewController, didFinishWith pages: [UIImage])
    func documentCameraViewControllerDidCancel(_ controller: DocumentCameraViewController)
    func documentCameraViewController(_ controller: DocumentCameraViewController, didFailWith error: Error)
}

enum DocumentCameraError: LocalizedError {
    case cameraUnavailable
    case cameraPermissionDenied
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: "A camera is not available on this device."
        case .cameraPermissionDenied: "Camera access is required to scan documents."
        case .captureFailed: "The page could not be captured. Please try again."
        }
    }
}

final class DocumentCameraViewController: UIViewController {
    static var isSupported: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    weak var delegate: DocumentCameraViewControllerDelegate?

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.longnt27.KhanhScanner.capture-session")
    private let analysisQueue = DispatchQueue(label: "com.longnt27.KhanhScanner.document-analysis")
    private let imageContext = CIContext(options: [.cacheIntermediates: false])

    private lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()
    private let documentLayer = CAShapeLayer()
    private let warningLabel = UILabel()
    private let pageCountLabel = UILabel()
    private let shutterButton = UIButton(type: .custom)
    private let doneButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    private var pages: [UIImage] = []
    private var currentQuadrilateral: DocumentQuadrilateral?
    private var currentQuality: DocumentQuality = .flattenCorners
    private var lastAnalysisDate = Date.distantPast
    private var isCapturing = false
    private var isFinishing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureInterface()
        requestCameraAccessAndConfigure()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        documentLayer.frame = previewLayer.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning { captureSession.stopRunning() }
        }
    }

    private func configureInterface() {
        view.layer.addSublayer(previewLayer)

        documentLayer.fillColor = UIColor.clear.cgColor
        documentLayer.lineWidth = 3
        documentLayer.lineJoin = .round
        previewLayer.addSublayer(documentLayer)

        [warningLabel, pageCountLabel, shutterButton, doneButton, cancelButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        warningLabel.text = "Flatten all four corners before scanning."
        warningLabel.textAlignment = .center
        warningLabel.textColor = .white
        warningLabel.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.92)
        warningLabel.font = .preferredFont(forTextStyle: .headline)
        warningLabel.numberOfLines = 0
        warningLabel.layer.cornerRadius = 12
        warningLabel.clipsToBounds = true

        pageCountLabel.textColor = .white
        pageCountLabel.font = .preferredFont(forTextStyle: .headline)
        pageCountLabel.textAlignment = .center

        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 36
        shutterButton.layer.borderColor = UIColor.white.withAlphaComponent(0.65).cgColor
        shutterButton.layer.borderWidth = 5
        shutterButton.addTarget(self, action: #selector(capturePage), for: .touchUpInside)

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.tintColor = .white
        doneButton.addTarget(self, action: #selector(finishScanning), for: .touchUpInside)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancelScanning), for: .touchUpInside)

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

            warningLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            warningLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            warningLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            warningLabel.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -22),
            warningLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            warningLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])

        updatePageCount()
        updateQualityInterface()
    }

    private func requestCameraAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                granted ? self.configureCaptureSession() : self.fail(with: DocumentCameraError.cameraPermissionDenied)
            }
        default:
            fail(with: DocumentCameraError.cameraPermissionDenied)
        }
    }

    private func configureCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                guard let camera = AVCaptureDevice.default(
                    .builtInWideAngleCamera,
                    for: .video,
                    position: .back
                ) else {
                    throw DocumentCameraError.cameraUnavailable
                }

                let input = try AVCaptureDeviceInput(device: camera)
                guard self.captureSession.canAddInput(input),
                      self.captureSession.canAddOutput(self.photoOutput),
                      self.captureSession.canAddOutput(self.videoOutput) else {
                    throw DocumentCameraError.cameraUnavailable
                }

                self.captureSession.beginConfiguration()
                self.captureSession.sessionPreset = .photo
                self.captureSession.addInput(input)
                self.captureSession.addOutput(self.photoOutput)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
                self.captureSession.addOutput(self.videoOutput)

                self.setPortraitOrientation(on: self.videoOutput.connection(with: .video))
                self.setPortraitOrientation(on: self.photoOutput.connection(with: .video))
                self.captureSession.commitConfiguration()
                self.captureSession.startRunning()
            } catch {
                self.fail(with: error)
            }
        }
    }

    private func setPortraitOrientation(on connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoRotationAngleSupported(90) else { return }
        connection.videoRotationAngle = 90
    }

    @objc private func capturePage() {
        guard currentQuality == .ready, currentQuadrilateral != nil, !isCapturing else {
            currentQuality = .flattenCorners
            updateQualityInterface()
            return
        }

        isCapturing = true
        updateQualityInterface()
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func finishScanning() {
        guard !pages.isEmpty, !isFinishing else { return }
        isFinishing = true
        let capturedPages = pages
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning { captureSession.stopRunning() }
        }
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.documentCameraViewController(self, didFinishWith: capturedPages)
        }
    }

    @objc private func cancelScanning() {
        guard !isFinishing else { return }
        isFinishing = true
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning { captureSession.stopRunning() }
        }
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.documentCameraViewControllerDidCancel(self)
        }
    }

    private func processCapturedPhoto(_ image: UIImage) {
        analysisQueue.async { [weak self] in
            guard let self, let image = image.normalizedForDocumentCapture(), let cgImage = image.cgImage else {
                self?.finishCapture(with: .failure(DocumentCameraError.captureFailed))
                return
            }

            do {
                guard let observation = try DocumentRectangleProcessor.observation(in: cgImage) else {
                    self.finishCapture(with: .rejected)
                    return
                }
                let quadrilateral = DocumentRectangleProcessor.quadrilateral(from: observation)
                let edgeSupport = DocumentEdgeAnalyzer.measure(in: cgImage, quadrilateral: quadrilateral)
                guard DocumentQualityEvaluator.evaluate(
                    quadrilateral,
                    confidence: observation.confidence,
                    edgeSupport: edgeSupport
                ) == .ready,
                let corrected = DocumentRectangleProcessor.correctedImage(
                    from: cgImage,
                    quadrilateral: quadrilateral
                ) else {
                    self.finishCapture(with: .rejected)
                    return
                }
                self.finishCapture(with: .accepted(corrected))
            } catch {
                self.finishCapture(with: .failure(error))
            }
        }
    }

    private enum CaptureResult {
        case accepted(UIImage)
        case rejected
        case failure(Error)
    }

    private func finishCapture(with result: CaptureResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isCapturing = false
            switch result {
            case let .accepted(image):
                self.pages.append(image)
                self.updatePageCount()
            case .rejected:
                self.currentQuality = .flattenCorners
                self.updateQualityInterface()
            case let .failure(error):
                self.fail(with: error)
            }
        }
    }

    private func updateDetection(quadrilateral: DocumentQuadrilateral?, quality: DocumentQuality) {
        currentQuadrilateral = quadrilateral
        currentQuality = quality

        guard let quadrilateral else {
            documentLayer.path = nil
            updateQualityInterface()
            return
        }

        let points = quadrilateral.points.map { point in
            previewLayer.layerPointConverted(
                fromCaptureDevicePoint: CGPoint(x: point.x, y: 1 - point.y)
            )
        }
        let path = UIBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.close()
        documentLayer.path = path.cgPath
        updateQualityInterface()
    }

    private func updateQualityInterface() {
        let ready = currentQuality == .ready && currentQuadrilateral != nil && !isCapturing
        shutterButton.isEnabled = ready
        shutterButton.alpha = ready ? 1 : 0.38
        warningLabel.isHidden = currentQuality == .ready
        documentLayer.strokeColor = (currentQuality == .ready ? UIColor.systemGreen : UIColor.systemOrange).cgColor
    }

    private func updatePageCount() {
        pageCountLabel.text = pages.isEmpty ? "" : "\(pages.count) page\(pages.count == 1 ? "" : "s")"
        doneButton.isEnabled = !pages.isEmpty
        doneButton.alpha = pages.isEmpty ? 0.45 : 1
    }

    private func fail(with error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isFinishing else { return }
            self.isFinishing = true
            self.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.delegate?.documentCameraViewController(self, didFailWith: error)
            }
        }
    }
}

extension DocumentCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisDate) >= 0.25,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysisDate = now

        do {
            guard let observation = try DocumentRectangleProcessor.observation(
                in: pixelBuffer,
                orientation: .right
            ) else {
                DispatchQueue.main.async { [weak self] in
                    self?.updateDetection(quadrilateral: nil, quality: .flattenCorners)
                }
                return
            }

            let quadrilateral = DocumentRectangleProcessor.quadrilateral(from: observation)
            let orientedImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
            let edgeSupport = imageContext.createCGImage(orientedImage, from: orientedImage.extent).map {
                DocumentEdgeAnalyzer.measure(in: $0, quadrilateral: quadrilateral)
            }
            let quality = DocumentQualityEvaluator.evaluate(
                quadrilateral,
                confidence: observation.confidence,
                edgeSupport: edgeSupport
            )
            DispatchQueue.main.async { [weak self] in
                self?.updateDetection(quadrilateral: quadrilateral, quality: quality)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.updateDetection(quadrilateral: nil, quality: .flattenCorners)
            }
        }
    }
}

extension DocumentCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            finishCapture(with: .failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            finishCapture(with: .failure(DocumentCameraError.captureFailed))
            return
        }
        processCapturedPhoto(image)
    }
}

private extension UIImage {
    func normalizedForDocumentCapture() -> UIImage? {
        if imageOrientation == .up, cgImage != nil { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
