import SwiftUI
import WebKit

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image("Logo").resizable().renderingMode(.template).scaledToFit().frame(height: 28)
            Text("A suli, átláthatóan.")
                .font(.system(size: 40, weight: .bold, design: model.prefs.titleFont.design))
            Text("Jegyek, órarend, üzenetek — a KRÉTA adataid egy nyugodtabb, natív Mac alkalmazásban.")
                .font(.title3).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("· adatok titkosítva, csak ezen a Macen")
                Text("· háttérfrissítés és értesítések a menüsorból")
                Text("· a jelszavad a hivatalos KRÉTA oldalon marad")
            }
            .font(.mono(12)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Bejelentkezés a KRÉTA-val") { model.beginLogin() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                Button("Bemutató") { model.startDemo() }
                    .buttonStyle(.glassy)
                    .controlSize(.large)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Official KRÉTA IdP in an isolated, non-persistent web view.
struct LoginSheet: View {
    var session: LoginSession
    @Environment(AppModel.self) private var model
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill").foregroundStyle(.green)
                Text("idp.e-kreta.hu").font(.callout.monospaced()).foregroundStyle(.secondary)
                if loading { ProgressView().controlSize(.small) }
                Spacer()
                Button("Mégse") { model.cancelLogin() }
                    .buttonStyle(.glassy)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            OAuthWebView(url: session.url, loading: $loading) { model.completeLogin($0) }
        }
        .frame(minWidth: 460, idealWidth: 540, minHeight: 520, idealHeight: 720)
    }
}

struct OAuthWebView: NSViewRepresentable {
    var url: URL
    @Binding var loading: Bool
    var onRedirect: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: OAuthWebView
        private var completed = false
        init(_ parent: OAuthWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            if PendingLogin.isRedirect(url) {
                if !completed {
                    completed = true
                    parent.onRedirect(url)
                }
                return .cancel
            }
            // Only TLS navigation inside KRÉTA's hosted authentication.
            guard url.scheme == "https", let host = url.host, host == "e-kreta.hu" || host.hasSuffix(".e-kreta.hu") else {
                return url.scheme == "about" ? .allow : .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { parent.loading = true }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.loading = false }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.loading = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.loading = false }
    }
}
