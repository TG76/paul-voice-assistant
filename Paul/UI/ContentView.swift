import SwiftUI
import WebKit

struct ContentDisplayView: View {
    let imageURL: URL?
    let webURL: URL?

    var body: some View {
        Group {
            if let imageURL = imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(12)
                            .shadow(radius: 10)
                    case .failure:
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: 500, maxHeight: 400)
                .transition(.scale.combined(with: .opacity))

            } else if let webURL = webURL {
                WebViewWrapper(url: webURL)
                    .frame(maxWidth: 600, maxHeight: 500)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

struct WebViewWrapper: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.load(URLRequest(url: url))
    }
}
