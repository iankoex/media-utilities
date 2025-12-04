# MediaUtilities

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fiankoex%2Fmedia-utilities%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/iankoex/media-utilities)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fiankoex%2Fmedia-utilities%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/iankoex/media-utilities)

This package allows you to:

- Import Images and Videos
- Edit Images and Videos
- Capture Photos and Videos with Camera

# Installation

Swift Package Manager

# Usage

You can use the individial files depending on your needs.
For a holistic unified approach use:

### Images

Allows for cropping, rotating images and more features coming. It also allows for dragging and dropping any image from Photos, Finder, Safari, anywhere you can drag an image from.

Feel free to add your implementations and submit a pr.


<p align="center">
  <img width="200" src="https://github.com/user-attachments/assets/be836617-e045-4155-a841-156a4425309e" >
  <img width="200" src="https://github.com/user-attachments/assets/1814a1bf-f32b-4462-b824-77561b1712ea" >
  <img width="200" src="https://github.com/user-attachments/assets/bd545e46-47cb-4a79-957e-b02fea6e20f4" >
</p>


```swift

/// a holistic image picker that allows for picking or dropping image to the attached view and editing the image before retuning the final image.
/// the image editor uses gestures, keep this in mind when attaching this modifier to a sheet, a scrollview or any view with gestures enabled
/// - Parameters:
///   - isPresented: a bool that directly controls the media picker
///   - aspectRatio: desired aspect ratio, when the mash shape is curcular this value is ignored in favour of 1
///   - maskShape: desired mask shape, when you choose circular the aspect ratio is automatically 1
///   - isGuarded: a bool that indicates whether the attached view can accept dropping of images
///   - onCompletion: call back with a result of type `Result<UnifiedImage, Error>`
///
@inlinable public func imagePicker(
    _ isPresented: Binding<Bool>,
    aspectRatio: CGFloat,
    maskShape: MaskShape = .rectangular,
    isGuarded: Binding<Bool>,
    onCompletion: @escaping (Result<UnifiedImage, Error>) -> Void
) -> some View

```


### Videos

```swift


/// a holistic video picker that allows for picking or dropping of videos or url with videos to the attached view
/// and editing of the video before retuning the url in the local file sytem.
/// internet urls will be downloaded before editing the video.
/// - Parameters:
///   - isPresented: a bool that directly controls the media picker
///   - isGuarded: a bool that indicates whether the attached view can accept dropping of url or video
///   - onCompletion: call back with a result of type `Result<URL, Error>`, the url is a local file url
@inlinable public func videoPicker(
    _ isPresented: Binding<Bool>,
    isGuarded: Binding<Bool>,
    onCompletion: @escaping (Result<URL, Error>) -> Void
) -> some View

```

### Camera

Provides comprehensive camera functionality for capturing photos and videos with advanced controls.

#### Camera Capture View

A complete SwiftUI camera interface with live preview, capture controls, and mode switching.

```swift
import SwiftUI
import MediaUtilities

struct CameraView: View {
    @State private var showCamera = false

    var body: some View {
        VStack {
            Button("Open Camera") {
                showCamera = true
            }
        }
        .cameraCapture(isPresented: $showCamera) { result in
            switch result {
            case .success(let url):
                print("Media captured: \(url)")
            case .failure(let error):
                print("Camera error: \(error)")
            }
        }
    }
}
```

#### Camera Service

For advanced camera control and custom implementations.

```swift
import MediaUtilities

class CameraManager {
    private let cameraService = CameraService()

    func setupCamera() async {
        // Initialize camera
        let result = await cameraService.initializeCamera()
        switch result {
        case .success:
            print("Camera ready")
        case .failure(let error):
            print("Camera setup failed: \(error)")
        }
    }

    func capturePhoto() async {
        let result = await cameraService.capturePhotoWithCompletion()
        switch result {
        case .success(let url):
            print("Photo saved to: \(url)")
        case .failure(let error):
            print("Photo capture failed: \(error)")
        }
    }

    func toggleFlash() {
        let success = cameraService.toggleFlashMode()
        if success {
            print("Flash mode: \(cameraService.flashMode)")
        }
    }
}
```

#### Camera Features

- **Live Preview**: Real-time camera preview with pause/resume controls
- **Photo/Video Capture**: Switch between photo and video recording modes
- **Flash Control**: Automatic flash mode cycling (off/auto/on)
- **Camera Switching**: Toggle between front and back cameras
- **Permission Handling**: Automatic camera access request and status checking
- **Error Handling**: Comprehensive error reporting with localized messages
- **Cross-Platform**: Works on both iOS and macOS with platform-specific optimizations

What this allows you to do is enable drag and drop to the view,edit the asset then retun the edited asset.
The `isPresented` directly controls the PhotosPicker in iOS and finder window in macOS.

## To Do

- [ ] Adding Stickers on Image/Video
- [ ] Custom Audio to Video
- [ ] Drawing on Image/Video
- [x] Drag and Drop Delegates
- [x] Camera Capture (Photo/Video)

# SDKs

Some features may require higher versions. But generally it supports the following:

- iOS 13+
- macOS 10.15+

Although the package is written mainly for SwiftUI, image and video manipulations can be used in UIKit and AppKit.

# Code Contributions

Feel free to contribute via fork/pull request to main branch. If you want to request a feature or report a bug please start a new issue.

# License

MIT
