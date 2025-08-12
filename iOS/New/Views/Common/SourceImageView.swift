//
//  SourceImageView.swift
//  Aidoku
//
//  Created by Skitty on 4/26/25.
//

import AidokuRunner
import NukeUI
import SwiftUI

struct SourceImageView: View {
    var source: AidokuRunner.Source?

    let imageUrl: String
    var width: CGFloat?
    var height: CGFloat?
    var downsampleWidth: CGFloat?
    var contentMode: ContentMode = .fill
    var placeholder = "MangaPlaceholder"

    @State private var imageRequest: ImageRequest?
    @State private var isLoaded: Bool = false

    var body: some View {
        LazyImage(
            request: imageRequest,
            transaction: .init(animation: .default)
        ) { state in
            if state.imageContainer?.type == .gif, let data = state.imageContainer?.data {
                GIFImage(
                    data: data,
                    contentMode: contentMode
                )
                    .frame(width: width, height: height)
                    .id(state.image != nil ? imageUrl : "placeholder") // ensures only opacity is animated
                    .opacity(isLoaded ? 1 : 0)
                    .scaleEffect(isLoaded ? 1 : 0.98)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isLoaded)
                    .onChange(of: state.image != nil) { loaded in
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            isLoaded = loaded
                        }
                    }
            } else {
                let result = if let image = state.image {
                    image
                } else {
                    Image(placeholder)
                }
                result
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: width, height: height)
                    .id(state.image != nil ? imageUrl : "placeholder") // ensures only opacity is animated
                    .opacity(isLoaded ? 1 : 0)
                    .scaleEffect(isLoaded ? 1 : 0.98)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isLoaded)
                    .onChange(of: state.image != nil) { loaded in
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            isLoaded = loaded
                        }
                    }
                    .overlay(
                        Group {
                            if state.image == nil {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.08))
                                    .shimmering()
                            }
                        }
                    )
            }
        }
        .processors({
            if let downsampleWidth {
                [DownsampleProcessor(width: downsampleWidth)]
            } else {
                []
            }
        }())
        .onAppear {
            guard imageRequest == nil else { return }
            Task {
                await loadImageRequest(url: imageUrl)
            }
        }
        .onChange(of: imageUrl) { newValue in
            imageRequest = nil
            isLoaded = false
            Task {
                await loadImageRequest(url: newValue)
            }
        }
        .onAppear { isLoaded = false }
    }

    func loadImageRequest(url: String) async {
        let url = URL(string: url)
        if let fileUrl = url?.toAidokuFileUrl() {
            imageRequest = ImageRequest(url: fileUrl)
            return
        }
        guard let source, let url, !url.isFileURL else {
            imageRequest = ImageRequest(url: url)
            return
        }
        imageRequest = ImageRequest(urlRequest: await source.getModifiedImageRequest(url: url, context: nil))
    }
}
