//
//  File.swift
//  
//
//  Created by Ian on 29/06/2022.
//

#if os(iOS)
import SwiftUI
import PhotosUI

@available(iOS 14.0, macOS 11, *)
public extension View {
    func mediaPicker(
        isPresented: Binding<Bool>,
        allowedMediaTypes: MediaTypeOptions,
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            MediaPickerWrapper(
                isPresented: isPresented,
                allowedMediaTypes: allowedMediaTypes,
                allowsMultipleSelection: allowsMultipleSelection,
                onCompletion: onCompletion
            )
        }
    }
}

@available(iOS 14.0, macOS 11, *)
fileprivate struct MediaPickerWrapper: View {
    @ObservedObject var viewModel: MediaPickerViewModel
    @Binding var isPresented: Bool
    
    init(
        isPresented: Binding<Bool>,
        allowedMediaTypes: MediaTypeOptions,
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) {
        let viewModel = MediaPickerViewModel(onCompletion: onCompletion)
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = allowsMultipleSelection ? 0 : 1
        configuration.filter = PHPickerFilter.from(allowedMediaTypes)
        configuration.preferredAssetRepresentationMode = .current
        viewModel.configuration = configuration
        viewModel.allowedContentTypes = allowedMediaTypes.typeIdentifiers
        
        self.viewModel = viewModel
        self._isPresented = isPresented
    }
    
    var body: some View {
        MediaPickerRepresentable(viewModel: viewModel, isPresented: $isPresented)
            .overlay(viewModel.isLoading ? loadingView : nil)
    }
    
    var loadingView: some View {
        NavigationView {
            ProgressView(viewModel.progress)
                .progressViewStyle(.linear)
                .padding()
                .navigationTitle("Importing Media...")
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onChange(of: viewModel.progress.isFinished) { _ in
            viewModel.finaliseResults()
            isPresented = false
        }
    }
}

@available(iOS 14.0, macOS 11, *)
fileprivate struct MediaPickerRepresentable: UIViewControllerRepresentable {
    @ObservedObject var viewModel: MediaPickerViewModel
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        let controller = PHPickerViewController(configuration: viewModel.configuration)
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // do nothing
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
    
    class Coordinator: PHPickerViewControllerDelegate {
        let parent: MediaPickerRepresentable
        
        init(_ picker: MediaPickerRepresentable) {
            self.parent = picker
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                parent.isPresented = false
                return
            }
            parent.viewModel.handleResults(for: results)
        }
    }
}

@available(iOS 14.0, macOS 11, *)
fileprivate extension PHPickerFilter {
    static func from(_ mediaOptions: MediaTypeOptions) -> Self {
        var filters: [PHPickerFilter] = []
        if mediaOptions.contains(.images) {
            filters.append(.images)
        } else if mediaOptions.contains(.livePhotos) {
            filters.append(.livePhotos)
        }
        if mediaOptions.contains(.videos) {
            filters.append(.videos)
        }
        return PHPickerFilter.any(of: filters)
    }
}
#endif

