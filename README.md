# MediaUtilities

This package allows you to:
- Import Images and Videos
- Edit Images and Videos

# Installation
Swift Package Manager

# Usage
You can use the individial files depending on your needs.
For a holistic unified approach use:
```
/// For Images 
.imagePicker($isShowingImagePicker, aspectRatio: 16 / 9, isGuarded: false) { result in

}

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

# Code Contributions
Feel free to contribute via fork/pull request to master branch. If you want to request a feature or report a bug please start a new issue.

# License
Run Wild
