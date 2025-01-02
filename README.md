# MediaUtilities

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fiankoex%2Fmedia-utilities%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/iankoex/media-utilities)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fiankoex%2Fmedia-utilities%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/iankoex/media-utilities)

This package allows you to:

- Import Images and Videos
- Edit Images and Videos

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
/// an holictic image picker that allows for picking or dropping image to the attached view and editing the image before retuning the final image.
/// the image editor uses gestures, keep this in mind when attaching this modifier to a sheet, a scrollview or any view with gestures enabled
/// - Parameters:
///   - isPresented: a bool that directly controls the media picker
///   - aspectRatio: desired aspect ratio, when the mash shape is curcular this value is ignored in favour of 1
///   - maskShape: desired mask shape, when you choose circular the aspect ratio is automatically 1
///   - isGuarded: a bool that indicates whether the attched view can accept dropping of images
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
// For Videos
.videoPicker($isShowingVideoPicker) { result in

}
```

What this allows you to do is enable drag and drop to the view,edit the asset then retun the edited asset.
The `isPresented` directly controls the PhotosPicker in iOS and finder window in macOS.

## To Do

- [ ] Adding Stickers on Image/Video
- [ ] Custom Audio to Video
- [ ] Drawing on Image/Video
- [x] Drag and Drop Delegates

# SDKs

Some features may require higher versions. But generally it supports the following:

- iOS 13+
- macOS 10.15+

Although the package is written mainly for SwiftUI, image and video manipulations can be used in UIKit and AppKit.

# Code Contributions

Feel free to contribute via fork/pull request to main branch. If you want to request a feature or report a bug please start a new issue.

# License

MIT
