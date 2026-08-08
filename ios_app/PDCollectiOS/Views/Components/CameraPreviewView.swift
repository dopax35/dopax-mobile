import SwiftUI
import AVFoundation

/// Renders a live AVCaptureSession camera preview stream inside a SwiftUI view.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = videoGravity
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.videoPreviewLayer.videoGravity = videoGravity
    }
}
