import AppKit
import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let document: RenderedDocument
    let documentURL: URL
    let rootURL: URL
    let style: ResolvedReaderTheme
    let scrollRequest: ScrollRequest?
    let findRequest: DocumentSearchRequest?
    let sourceViewportUpdates: [SourceViewportUpdate]
    let onOpenDocument: (URL, String?) -> Void
    let onActiveHeading: (String?) -> Void
    let onFindResult: (UUID, Bool) -> Void
    let onSourceBoundary: (SourceViewportDirection, Int) -> Void
    let onSourceVisiblePage: (Int) -> Void
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            rootURL: rootURL,
            onOpenDocument: onOpenDocument,
            onActiveHeading: onActiveHeading,
            onFindResult: onFindResult,
            onSourceBoundary: onSourceBoundary,
            onSourceVisiblePage: onSourceVisiblePage
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(
            context.coordinator.resourceHandler,
            forURLScheme: LocalDocumentResourcePolicy.resourceScheme
        )
        configuration.setURLSchemeHandler(
            context.coordinator.bundledAssetHandler,
            forURLScheme: LocalDocumentResourcePolicy.bundledAssetScheme
        )
        configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: context.coordinator),
            name: Coordinator.outlineMessageName
        )
        configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: context.coordinator),
            name: Coordinator.sourceViewportMessageName
        )

        let webView = FocusReportingWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.onFocus = onFocus
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = document.renderingMode == .interactiveHTML
            ? .clear
            : style.canvasColor
        if #available(macOS 13.3, *) {
            webView.isInspectable = false
        }

        context.coordinator.lastDocumentID = document.id
        context.coordinator.lastDocumentURL = documentURL
        context.coordinator.lastRootURL = rootURL
        context.coordinator.lastDocumentHTML = document.html
        context.coordinator.lastInteractiveHTMLFallback = document.interactiveHTMLFallback
        context.coordinator.lastOutline = document.outline
        context.coordinator.renderingMode = document.renderingMode
        context.coordinator.sourceSelection = document.sourcePage?.selectedRange
        context.coordinator.sourceSelectionPageIndex = document.sourcePage?.page.index
        context.coordinator.lastStyle = style
        context.coordinator.webContentRecoveryCount = 0
        context.coordinator.resourceHandler.rootURL = rootURL
        context.coordinator.loadCurrentDocument(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenDocument = onOpenDocument
        context.coordinator.onActiveHeading = onActiveHeading
        context.coordinator.onFindResult = onFindResult
        context.coordinator.onSourceBoundary = onSourceBoundary
        context.coordinator.onSourceVisiblePage = onSourceVisiblePage
        (webView as? FocusReportingWebView)?.onFocus = onFocus
        context.coordinator.resourceHandler.rootURL = rootURL
        webView.underPageBackgroundColor = document.renderingMode == .interactiveHTML
            ? .clear
            : style.canvasColor

        if context.coordinator.lastDocumentID != document.id {
            context.coordinator.lastDocumentID = document.id
            context.coordinator.lastDocumentURL = documentURL
            context.coordinator.lastRootURL = rootURL
            context.coordinator.lastDocumentHTML = document.html
            context.coordinator.lastInteractiveHTMLFallback = document.interactiveHTMLFallback
            context.coordinator.lastOutline = document.outline
            context.coordinator.renderingMode = document.renderingMode
            context.coordinator.sourceSelection = document.sourcePage?.selectedRange
            context.coordinator.sourceSelectionPageIndex = document.sourcePage?.page.index
            context.coordinator.lastStyle = style
            context.coordinator.lastScrollID = nil
            context.coordinator.lastFindRequestID = nil
            context.coordinator.resetSourceViewportUpdates()
            context.coordinator.lastReportedAnchor = nil
            context.coordinator.webContentRecoveryCount = 0
            context.coordinator.pendingAnchor = scrollRequest?.anchor
            context.coordinator.pendingFindRequest = nil
            context.coordinator.loadCurrentDocument(in: webView)
        } else if context.coordinator.lastStyle != style {
            context.coordinator.lastStyle = style
            switch document.renderingMode {
            case .styledDocument, .sourceCode, .image:
                context.coordinator.apply(style: style, to: webView)
            case .interactiveHTML:
                break
            }
        }

        if let scrollRequest, context.coordinator.lastScrollID != scrollRequest.id {
            context.coordinator.lastScrollID = scrollRequest.id
            if webView.isLoading {
                context.coordinator.pendingAnchor = scrollRequest.anchor
            } else {
                context.coordinator.scroll(to: scrollRequest.anchor, in: webView)
            }
        }

        if let findRequest, context.coordinator.lastFindRequestID != findRequest.id {
            context.coordinator.lastFindRequestID = findRequest.id
            if Coordinator.shouldDeferFind(
                webViewIsLoading: webView.isLoading,
                isDocumentReady: context.coordinator.isDocumentReady
            ) {
                context.coordinator.pendingFindRequest = findRequest
            } else {
                context.coordinator.find(findRequest, in: webView)
            }
        }

        context.coordinator.apply(sourceViewportUpdates, to: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.outlineMessageName
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.sourceViewportMessageName
        )
        coordinator.onOpenDocument = nil
        coordinator.onActiveHeading = nil
        coordinator.onFindResult = nil
        coordinator.onSourceBoundary = nil
        coordinator.onSourceVisiblePage = nil
        coordinator.pendingAnchor = nil
        coordinator.pendingFindRequest = nil
        coordinator.pendingSourceViewportUpdates = []
        coordinator.lastDocumentHTML = nil
        coordinator.lastInteractiveHTMLFallback = nil
        coordinator.lastOutline = []
        (webView as? FocusReportingWebView)?.onFocus = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let outlineMessageName = "moduOutline"
        static let sourceViewportMessageName = "moduSourceViewport"

        let resourceHandler: LocalResourceSchemeHandler
        let bundledAssetHandler = BundledAssetSchemeHandler()
        var onOpenDocument: ((URL, String?) -> Void)?
        var onActiveHeading: ((String?) -> Void)?
        var onFindResult: ((UUID, Bool) -> Void)?
        var onSourceBoundary: ((SourceViewportDirection, Int) -> Void)?
        var onSourceVisiblePage: ((Int) -> Void)?
        var lastDocumentID: UUID?
        var lastDocumentURL: URL?
        var lastRootURL: URL?
        var lastDocumentHTML: String?
        var lastInteractiveHTMLFallback: String?
        var lastOutline: [OutlineItem] = []
        var renderingMode: ReaderDocumentRenderingMode = .styledDocument
        var sourceSelection: NSRange?
        var sourceSelectionPageIndex: Int?
        var lastStyle: ResolvedReaderTheme?
        var lastScrollID: UUID?
        var lastFindRequestID: UUID?
        var pendingAnchor: String?
        var pendingFindRequest: DocumentSearchRequest?
        var pendingSourceViewportUpdates: [SourceViewportUpdate] = []
        var completedSourceViewportUpdateIDs: Set<UUID> = []
        var completedSourceViewportUpdateOrder: [UUID] = []
        var isApplyingSourceViewportUpdate = false
        var lastReportedAnchor: String?
        var webContentRecoveryCount = 0
        var interactiveLoadFinished = false
        var isDisplayingHTMLFallback = false
        var isAwaitingInitialInteractiveNavigation = false
        var isDocumentReady = false
        private static let maximumWebContentRecoveries = 1

        static func shouldDeferFind(webViewIsLoading: Bool, isDocumentReady: Bool) -> Bool {
            webViewIsLoading || !isDocumentReady
        }

        nonisolated static func isAllowedInternalNavigation(
            url: URL,
            isMainFrame: Bool?
        ) -> Bool {
            let absoluteString = (url.absoluteString.removingPercentEncoding ?? url.absoluteString)
                .lowercased()
            if absoluteString == "about:blank" || absoluteString.hasPrefix("about:blank#") {
                return true
            }
            if
                isMainFrame == false,
                absoluteString == "about:srcdoc" || absoluteString.hasPrefix("about:srcdoc#")
            {
                return true
            }
            return url.scheme == nil && url.path.isEmpty && url.query == nil && url.fragment != nil
        }

        nonisolated static func isExpectedInitialInteractiveNavigation(
            isAwaitingInitialNavigation: Bool,
            isMainFrame: Bool?,
            isOtherNavigation: Bool,
            candidateURL: URL,
            currentDocumentURL: URL?
        ) -> Bool {
            guard
                isAwaitingInitialNavigation,
                isMainFrame != false,
                isOtherNavigation,
                let currentDocumentURL
            else { return false }

            return candidateURL.resolvingSymlinksInPath().standardizedFileURL
                == currentDocumentURL.resolvingSymlinksInPath().standardizedFileURL
        }

        init(
            rootURL: URL,
            onOpenDocument: @escaping (URL, String?) -> Void,
            onActiveHeading: @escaping (String?) -> Void,
            onFindResult: @escaping (UUID, Bool) -> Void,
            onSourceBoundary: @escaping (SourceViewportDirection, Int) -> Void,
            onSourceVisiblePage: @escaping (Int) -> Void
        ) {
            resourceHandler = LocalResourceSchemeHandler(rootURL: rootURL)
            self.onOpenDocument = onOpenDocument
            self.onActiveHeading = onActiveHeading
            self.onFindResult = onFindResult
            self.onSourceBoundary = onSourceBoundary
            self.onSourceVisiblePage = onSourceVisiblePage
        }

        func loadCurrentDocument(in webView: WKWebView) {
            webView.stopLoading()
            interactiveLoadFinished = false
            isDisplayingHTMLFallback = false
            isAwaitingInitialInteractiveNavigation = false
            isDocumentReady = false

            if renderingMode == .interactiveHTML, let lastDocumentHTML {
                guard let baseURL = interactiveDocumentURL else {
                    showInteractiveHTMLFallbackIfNeeded(in: webView)
                    return
                }
                isAwaitingInitialInteractiveNavigation = true
                webView.loadHTMLString(lastDocumentHTML, baseURL: baseURL)
            } else if let lastDocumentHTML {
                webView.loadHTMLString(lastDocumentHTML, baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if renderingMode == .interactiveHTML, !isDisplayingHTMLFallback {
                isAwaitingInitialInteractiveNavigation = false
                interactiveLoadFinished = true
                if let pendingAnchor {
                    self.pendingAnchor = nil
                    scroll(to: pendingAnchor, in: webView)
                }
                installInteractiveHTMLOutline(in: webView)
                isDocumentReady = true
                applyPendingFindRequest(to: webView)
                return
            }

            if renderingMode == .sourceCode {
                webView.evaluateJavaScript(Self.sourceHighlightingScript(
                    selection: sourceSelection,
                    pageIndex: sourceSelectionPageIndex
                )) { [weak self, weak webView] _, _ in
                    guard let self, let webView else { return }
                    self.installSourceViewportTracking(in: webView) { [weak self, weak webView] in
                        guard let self, let webView else { return }
                        self.applyPendingSourceViewportUpdate(to: webView)
                        self.isDocumentReady = true
                        self.applyPendingFindRequest(to: webView)
                    }
                }
                return
            }

            if let pendingAnchor {
                self.pendingAnchor = nil
                scroll(to: pendingAnchor, in: webView)
            } else {
                webView.evaluateJavaScript("window.scrollTo(0, 0)")
            }
            installStaticHTMLCompatibility(in: webView)
            installOutlineTracking(in: webView)
            if let lastStyle {
                apply(style: lastStyle, to: webView)
            }
            isDocumentReady = true
            applyPendingFindRequest(to: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard let lastDocumentHTML else { return }
            guard webContentRecoveryCount < Self.maximumWebContentRecoveries else {
                self.lastDocumentHTML = nil
                pendingAnchor = nil
                lastReportedAnchor = nil
                webView.loadHTMLString(Self.webContentRecoveryFailureHTML(style: lastStyle), baseURL: nil)
                return
            }
            webContentRecoveryCount += 1
            pendingAnchor = lastReportedAnchor
            if renderingMode == .interactiveHTML, let baseURL = interactiveDocumentURL {
                interactiveLoadFinished = false
                isDisplayingHTMLFallback = false
                isAwaitingInitialInteractiveNavigation = true
                isDocumentReady = false
                webView.loadHTMLString(lastDocumentHTML, baseURL: baseURL)
            } else {
                isDocumentReady = false
                webView.loadHTMLString(lastDocumentHTML, baseURL: nil)
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == Self.sourceViewportMessageName {
                guard
                    let payload = message.body as? [String: Any],
                    let type = payload["type"] as? String,
                    let pageIndex = payload["pageIndex"] as? Int
                else { return }
                if type == "visible" {
                    onSourceVisiblePage?(pageIndex)
                    return
                }
                guard
                    type == "boundary",
                    let rawDirection = payload["direction"] as? String,
                    let direction = SourceViewportDirection(rawValue: rawDirection)
                else { return }
                onSourceBoundary?(direction, pageIndex)
                return
            }

            guard message.name == Self.outlineMessageName, let rawAnchor = message.body as? String else {
                return
            }
            let anchor = rawAnchor.isEmpty ? nil : rawAnchor
            guard anchor != lastReportedAnchor else { return }
            lastReportedAnchor = anchor
            onActiveHeading?(anchor)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let scheme = url.scheme?.lowercased()
            if Self.isAllowedInternalNavigation(
                url: url,
                isMainFrame: navigationAction.targetFrame?.isMainFrame
            ) {
                decisionHandler(.allow)
                return
            }

            if renderingMode == .interactiveHTML, !isDisplayingHTMLFallback {
                if scheme == LocalDocumentResourcePolicy.resourceScheme {
                    guard
                        let rootURL = lastRootURL,
                        let candidate = LocalResourceSchemeHandler.fileURL(
                            for: url,
                            inside: rootURL
                        )
                    else {
                        decisionHandler(.cancel)
                        return
                    }
                    if Self.isExpectedInitialInteractiveNavigation(
                        isAwaitingInitialNavigation: isAwaitingInitialInteractiveNavigation,
                        isMainFrame: navigationAction.targetFrame?.isMainFrame,
                        isOtherNavigation: navigationAction.navigationType == .other,
                        candidateURL: candidate,
                        currentDocumentURL: lastDocumentURL
                    ) {
                        isAwaitingInitialInteractiveNavigation = false
                        decisionHandler(.allow)
                        return
                    }
                    guard navigationAction.targetFrame?.isMainFrame != false else {
                        decisionHandler(.allow)
                        return
                    }
                    if
                        candidate == lastDocumentURL?.resolvingSymlinksInPath().standardizedFileURL,
                        url.fragment != nil
                    {
                        decisionHandler(.allow)
                        return
                    }
                    decisionHandler(.cancel)
                    if FileSystemService.previewKind(at: candidate) != nil {
                        onOpenDocument?(candidate, url.fragment)
                    }
                    return
                }

                if scheme == "file" {
                    guard
                        let rootURL = lastRootURL,
                        (try? FileSystemService.validate(url, inside: rootURL)) != nil
                    else {
                        decisionHandler(.cancel)
                        return
                    }

                    decisionHandler(.cancel)
                    if
                        navigationAction.targetFrame?.isMainFrame != false,
                        FileSystemService.previewKind(at: url) != nil
                    {
                        onOpenDocument?(url, url.fragment)
                    }
                    return
                }

                if let scheme, ["http", "https"].contains(scheme) {
                    if navigationAction.targetFrame?.isMainFrame == false {
                        decisionHandler(.allow)
                    } else {
                        decisionHandler(.cancel)
                        if navigationAction.navigationType == .linkActivated {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    return
                }

                if scheme == "mailto" {
                    decisionHandler(.cancel)
                    if navigationAction.navigationType == .linkActivated {
                        NSWorkspace.shared.open(url)
                    }
                    return
                }

                if let scheme, ["blob", "data"].contains(scheme) {
                    decisionHandler(navigationAction.targetFrame?.isMainFrame == false ? .allow : .cancel)
                    return
                }
            }

            if scheme == LocalDocumentResourcePolicy.documentLinkScheme {
                decisionHandler(.cancel)
                guard
                    let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "path" })?.value,
                    let rootURL = resourceHandler.rootURL
                else { return }

                let candidate = rootURL.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
                guard
                    FileSystemService.previewKind(at: candidate) != nil,
                    (try? FileSystemService.validate(candidate, inside: rootURL)) != nil
                else { return }
                onOpenDocument?(candidate, url.fragment)
                return
            }

            if let scheme, ["http", "https", "mailto"].contains(scheme) {
                decisionHandler(.cancel)
                if navigationAction.navigationType == .linkActivated {
                    NSWorkspace.shared.open(url)
                }
                return
            }

            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            showInteractiveHTMLFallbackIfNeeded(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            showInteractiveHTMLFallbackIfNeeded(in: webView)
        }

        func apply(style: ResolvedReaderTheme, to webView: WKWebView) {
            let stylesheet: String
            switch renderingMode {
            case .sourceCode:
                stylesheet = style.stylesheet + "\n" + SourceDocumentRenderer.stylesheet
            case .image:
                stylesheet = style.stylesheet + "\n" + ImageDocumentRenderer.stylesheet
            case .styledDocument, .interactiveHTML:
                stylesheet = style.stylesheet
            }
            guard let literal = Self.javaScriptLiteral(stylesheet) else { return }
            let renderingScript = renderingMode == .sourceCode
                ? ""
                : Self.mermaidRenderingScript(isDark: style.isDark)
            let script = """
            document.getElementById('modu-theme').textContent = \(literal);
            \(renderingScript)
            """
            webView.evaluateJavaScript(script)
        }

        static func sourceHighlightingScript(selection: NSRange?, pageIndex: Int?) -> String {
            let selectionScript: String
            if let selection, let pageIndex {
                selectionScript = """
                const code = document.getElementById('source-code-\(pageIndex)');
                if (!code) return highlighted;
                const targetStart = \(selection.location);
                const targetEnd = \(selection.location + selection.length);
                const walker = document.createTreeWalker(code, NodeFilter.SHOW_TEXT);
                let cursor = 0;
                let startNode = null;
                let startOffset = 0;
                let endNode = null;
                let endOffset = 0;
                while (walker.nextNode()) {
                  const node = walker.currentNode;
                  const next = cursor + node.nodeValue.length;
                  if (!startNode && targetStart >= cursor && targetStart <= next) {
                    startNode = node;
                    startOffset = targetStart - cursor;
                  }
                  if (targetEnd >= cursor && targetEnd <= next) {
                    endNode = node;
                    endOffset = targetEnd - cursor;
                    break;
                  }
                  cursor = next;
                }
                if (startNode && endNode) {
                  const range = document.createRange();
                  range.setStart(startNode, startOffset);
                  range.setEnd(endNode, endOffset);
                  const selection = window.getSelection();
                  selection.removeAllRanges();
                  selection.addRange(range);
                  startNode.parentElement?.scrollIntoView({ block: 'center', inline: 'nearest' });
                }
                """
            } else {
                selectionScript = "window.getSelection()?.removeAllRanges();"
            }

            return """
            (() => {
              const codes = Array.from(document.querySelectorAll('.source-code code'));
              if (codes.length === 0) return false;
              let highlighted = true;
              for (const code of codes) {
                try {
                  const language = Array.from(code.classList)
                    .find(value => value.startsWith('language-'))
                    ?.slice('language-'.length);
                  if (globalThis.hljs && (!language || globalThis.hljs.getLanguage(language))) {
                    globalThis.hljs.highlightElement(code);
                  } else {
                    code.classList.add('hljs');
                  }
                } catch (_) {
                  code.classList.add('hljs');
                  highlighted = false;
                }
              }
              \(selectionScript)
              return highlighted && codes.every(code => code.classList.contains('hljs'));
            })();
            """
        }

        func apply(_ updates: [SourceViewportUpdate], to webView: WKWebView) {
            let pendingIDs = Set(pendingSourceViewportUpdates.map(\.id))
            pendingSourceViewportUpdates.append(contentsOf: updates.filter {
                !completedSourceViewportUpdateIDs.contains($0.id) && !pendingIDs.contains($0.id)
            })
            applyPendingSourceViewportUpdate(to: webView)
        }

        private func applyPendingSourceViewportUpdate(to webView: WKWebView) {
            guard
                !webView.isLoading,
                !isApplyingSourceViewportUpdate,
                let update = pendingSourceViewportUpdates.first,
                let script = Self.sourceViewportUpdateScript(update)
            else { return }
            isApplyingSourceViewportUpdate = true
            webView.evaluateJavaScript(script) { [weak self] value, _ in
                guard let self else { return }
                self.isApplyingSourceViewportUpdate = false
                guard value is Bool else { return }
                if self.pendingSourceViewportUpdates.first?.id == update.id {
                    self.pendingSourceViewportUpdates.removeFirst()
                } else {
                    self.pendingSourceViewportUpdates.removeAll { $0.id == update.id }
                }
                self.completedSourceViewportUpdateIDs.insert(update.id)
                self.completedSourceViewportUpdateOrder.append(update.id)
                while self.completedSourceViewportUpdateOrder.count > 16 {
                    let removedID = self.completedSourceViewportUpdateOrder.removeFirst()
                    self.completedSourceViewportUpdateIDs.remove(removedID)
                }
                self.applyPendingSourceViewportUpdate(to: webView)
            }
        }

        func resetSourceViewportUpdates() {
            pendingSourceViewportUpdates = []
            completedSourceViewportUpdateIDs = []
            completedSourceViewportUpdateOrder = []
            isApplyingSourceViewportUpdate = false
        }

        static func sourceViewportUpdateScript(_ update: SourceViewportUpdate) -> String? {
            var payload: [String: Any] = [
                "action": update.action.rawValue,
                "pageIndex": update.page.index,
                "text": update.page.text,
                "lineNumbers": SourceDocumentRenderer.lineNumbers(for: update.page),
                "startLine": update.page.startLine,
                "endLine": update.page.endLine,
                "hasPrevious": update.page.hasPrevious,
                "hasNext": update.page.hasNext,
                "language": update.language.highlightIdentifier
            ]
            if let selectedRange = update.selectedRange {
                payload["selectionStart"] = selectedRange.location
                payload["selectionLength"] = selectedRange.length
            }
            if let targetLine = update.targetLine {
                payload["targetLine"] = targetLine
            }
            guard
                let data = try? JSONSerialization.data(withJSONObject: payload),
                let encoded = String(data: data, encoding: .utf8)
            else { return nil }
            return "window.__moduSourceViewport?.apply(\(encoded));"
        }

        func find(_ request: DocumentSearchRequest, in webView: WKWebView) {
            guard !request.query.isEmpty else {
                webView.evaluateJavaScript("window.getSelection()?.removeAllRanges()") { [weak self] _, _ in
                    self?.onFindResult?(request.id, true)
                }
                return
            }
            let configuration = WKFindConfiguration()
            configuration.backwards = request.direction == .previous
            configuration.caseSensitive = request.isCaseSensitive
            configuration.wraps = true
            webView.find(request.query, configuration: configuration) { [weak self] result in
                self?.onFindResult?(request.id, result.matchFound)
            }
        }

        private func applyPendingFindRequest(to webView: WKWebView) {
            guard !webView.isLoading, let request = pendingFindRequest else { return }
            pendingFindRequest = nil
            find(request, in: webView)
        }

        func scroll(to anchor: String, in webView: WKWebView) {
            guard let literal = Self.javaScriptLiteral(anchor) else { return }
            let script = """
            (() => {
              const target = document.getElementById(\(literal));
              if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
            })();
            """
            webView.evaluateJavaScript(script)
        }

        private func installStaticHTMLCompatibility(in webView: WKWebView) {
            webView.evaluateJavaScript(Self.staticHTMLCompatibilityScript)
        }

        private func installSourceViewportTracking(in webView: WKWebView, completion: (() -> Void)? = nil) {
            webView.evaluateJavaScript(Self.sourceViewportTrackingScript) { _, _ in
                completion?()
            }
        }

        static let sourceViewportTrackingScript = """
        (() => {
          if (window.__moduSourceViewport) {
            window.__moduSourceViewport.schedule();
            return true;
          }

          const container = document.getElementById('source-segments');
          if (!container) return false;
          const maximumSegments = 3;
          const pending = new Set();
          let framePending = false;
          let lastVisiblePage = null;

          const post = payload => {
            window.webkit?.messageHandlers?.moduSourceViewport?.postMessage(payload);
          };

          const highlight = code => {
            try {
              const language = Array.from(code.classList)
                .find(value => value.startsWith('language-'))
                ?.slice('language-'.length);
              if (globalThis.hljs && (!language || globalThis.hljs.getLanguage(language))) {
                globalThis.hljs.highlightElement(code);
              } else {
                code.classList.add('hljs');
              }
            } catch (_) {
              code.classList.add('hljs');
            }
          };

          const selectRange = (code, start, length) => {
            if (!Number.isInteger(start) || !Number.isInteger(length)) return;
            const targetEnd = start + length;
            const walker = document.createTreeWalker(code, NodeFilter.SHOW_TEXT);
            let cursor = 0;
            let startNode = null;
            let startOffset = 0;
            let endNode = null;
            let endOffset = 0;
            while (walker.nextNode()) {
              const node = walker.currentNode;
              const next = cursor + node.nodeValue.length;
              if (!startNode && start >= cursor && start <= next) {
                startNode = node;
                startOffset = start - cursor;
              }
              if (targetEnd >= cursor && targetEnd <= next) {
                endNode = node;
                endOffset = targetEnd - cursor;
                break;
              }
              cursor = next;
            }
            if (!startNode || !endNode) return;
            const range = document.createRange();
            range.setStart(startNode, startOffset);
            range.setEnd(endNode, endOffset);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            startNode.parentElement?.scrollIntoView({ block: 'center', inline: 'nearest' });
          };

          const makeSegment = payload => {
            const segment = document.createElement('section');
            segment.className = 'source-segment';
            segment.dataset.pageIndex = String(payload.pageIndex);
            segment.dataset.startLine = String(payload.startLine);
            segment.dataset.endLine = String(payload.endLine);
            segment.dataset.hasPrevious = String(Boolean(payload.hasPrevious));
            segment.dataset.hasNext = String(Boolean(payload.hasNext));

            const numbers = document.createElement('pre');
            numbers.className = 'source-line-numbers';
            numbers.setAttribute('aria-hidden', 'true');
            numbers.textContent = payload.lineNumbers;

            const source = document.createElement('pre');
            source.className = 'source-code';
            const code = document.createElement('code');
            code.id = `source-code-${payload.pageIndex}`;
            code.className = `language-${payload.language}`;
            code.textContent = payload.text;
            source.appendChild(code);
            segment.append(numbers, source);
            highlight(code);
            return { segment, code };
          };

          const scrollToLine = (segment, line) => {
            if (!Number.isInteger(line)) return;
            const startLine = Number(segment.dataset.startLine || 1);
            const code = segment.querySelector('.source-code');
            const lineHeight = parseFloat(getComputedStyle(code).lineHeight) || 21;
            const topPadding = parseFloat(getComputedStyle(code).paddingTop) || 0;
            const offset = Math.max(0, line - startLine);
            const top = segment.offsetTop + topPadding + offset * lineHeight - window.innerHeight * 0.32;
            window.scrollTo({ top: Math.max(0, top), behavior: 'auto' });
          };

          const apply = payload => {
            if (payload.action === 'clearPending') {
              pending.clear();
              schedule();
              return true;
            }
            if (payload.action === 'releasePrevious') {
              pending.delete('previous');
              return true;
            }
            if (payload.action === 'releaseNext') {
              pending.delete('next');
              return true;
            }
            const existing = container.querySelector(
              `.source-segment[data-page-index="${payload.pageIndex}"]`
            );
            pending.delete(payload.action === 'prepend' ? 'previous' : 'next');
            if (existing && payload.action !== 'replace') {
              schedule();
              return false;
            }

            const { segment, code } = makeSegment(payload);
            if (payload.action === 'replace') {
              pending.clear();
              container.replaceChildren(segment);
              window.getSelection()?.removeAllRanges();
              if (Number.isInteger(payload.targetLine)) {
                scrollToLine(segment, payload.targetLine);
              }
            } else if (payload.action === 'prepend') {
              container.prepend(segment);
              const addedHeight = segment.getBoundingClientRect().height;
              window.scrollBy(0, addedHeight);
              while (container.children.length > maximumSegments) {
                container.lastElementChild?.remove();
              }
            } else {
              container.append(segment);
              while (container.children.length > maximumSegments) {
                const first = container.firstElementChild;
                const removedHeight = first?.getBoundingClientRect().height || 0;
                first?.remove();
                window.scrollBy(0, -removedHeight);
              }
            }

            if (Number.isInteger(payload.selectionStart)) {
              selectRange(code, payload.selectionStart, payload.selectionLength || 0);
            } else if (payload.action === 'replace' && Number.isInteger(payload.targetLine)) {
              scrollToLine(segment, payload.targetLine);
            }
            schedule();
            return true;
          };

          const requestBoundary = (direction, segment) => {
            if (!segment || pending.has(direction)) return;
            pending.add(direction);
            post({
              type: 'boundary',
              direction,
              pageIndex: Number(segment.dataset.pageIndex)
            });
          };

          const update = () => {
            framePending = false;
            const segments = Array.from(container.querySelectorAll('.source-segment'));
            if (segments.length === 0) return;

            const marker = Math.min(window.innerHeight * 0.35, 320);
            let visible = segments[0];
            for (const segment of segments) {
              const rect = segment.getBoundingClientRect();
              if (rect.top <= marker) visible = segment;
              if (rect.bottom > marker) break;
            }
            const visiblePage = Number(visible.dataset.pageIndex);
            if (visiblePage !== lastVisiblePage) {
              lastVisiblePage = visiblePage;
              post({ type: 'visible', pageIndex: visiblePage });
            }

            const threshold = Math.max(720, window.innerHeight * 1.2);
            const first = segments[0];
            const last = segments[segments.length - 1];
            if (window.scrollY < threshold && first.dataset.hasPrevious === 'true') {
              requestBoundary('previous', first);
            }
            const remaining = document.documentElement.scrollHeight - (window.scrollY + window.innerHeight);
            if (remaining < threshold && last.dataset.hasNext === 'true') {
              requestBoundary('next', last);
            }
          };

          const schedule = () => {
            if (framePending) return;
            framePending = true;
            window.requestAnimationFrame(update);
          };
          const cleanup = () => {
            window.removeEventListener('scroll', schedule);
            window.removeEventListener('resize', schedule);
            window.__moduSourceViewport = null;
          };

          window.addEventListener('scroll', schedule, { passive: true });
          window.addEventListener('resize', schedule, { passive: true });
          window.addEventListener('pagehide', cleanup, { once: true });
          window.__moduSourceViewport = { apply, schedule, cleanup };
          schedule();
          return true;
        })();
        """

        private func showInteractiveHTMLFallbackIfNeeded(in webView: WKWebView) {
            guard
                renderingMode == .interactiveHTML,
                !interactiveLoadFinished,
                !isDisplayingHTMLFallback,
                let lastInteractiveHTMLFallback
            else { return }
            isDisplayingHTMLFallback = true
            isAwaitingInitialInteractiveNavigation = false
            isDocumentReady = false
            webView.loadHTMLString(lastInteractiveHTMLFallback, baseURL: nil)
        }

        private var interactiveDocumentURL: URL? {
            guard let lastDocumentURL, let lastRootURL else { return nil }
            return LocalResourceSchemeHandler.resourceURL(
                for: lastDocumentURL,
                inside: lastRootURL
            )
        }

        private func installInteractiveHTMLOutline(in webView: WKWebView) {
            guard
                let data = try? JSONSerialization.data(
                    withJSONObject: lastOutline.map(\.anchor),
                    options: []
                ),
                let anchors = String(data: data, encoding: .utf8)
            else { return }

            let script = """
            (() => {
              const headings = Array.from(document.querySelectorAll(
                'h1, h2, h3, h4, h5, h6'
              ));
              const anchors = \(anchors);
              headings.forEach((heading, index) => {
                if (!heading.id && anchors[index]) heading.id = anchors[index];
              });
            })();
            """
            webView.evaluateJavaScript(script) { [weak self, weak webView] _, _ in
                guard let self, let webView else { return }
                self.installOutlineTracking(in: webView, rootSelector: "body")
            }
        }

        private func installOutlineTracking(in webView: WKWebView, rootSelector: String = "#write") {
            guard let rootSelectorLiteral = Self.javaScriptLiteral(rootSelector) else { return }
            let script = """
            (() => {
              if (window.__moduOutlineTracking) return;

              const content = document.querySelector(\(rootSelectorLiteral));
              if (!content) return;
              const headings = Array.from(content.querySelectorAll(
                'h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]'
              ));
              let lastAnchor = null;
              let framePending = false;

              const update = () => {
                framePending = false;
                let active = headings.length > 0 ? headings[0] : null;
                const marker = Math.min(96, Math.max(56, window.innerHeight * 0.12));
                for (const heading of headings) {
                  if (heading.getBoundingClientRect().top <= marker) {
                    active = heading;
                  } else {
                    break;
                  }
                }

                const root = document.documentElement;
                const isScrollable = root.scrollHeight > window.innerHeight + 2;
                if (
                  headings.length > 0 &&
                  isScrollable &&
                  window.scrollY > 0 &&
                  window.scrollY + window.innerHeight >= root.scrollHeight - 2
                ) {
                  active = headings[headings.length - 1];
                }

                const anchor = active ? active.id : '';
                if (anchor !== lastAnchor) {
                  lastAnchor = anchor;
                  window.webkit.messageHandlers.moduOutline.postMessage(anchor);
                }
              };

              const scheduleUpdate = () => {
                if (framePending) return;
                framePending = true;
                window.requestAnimationFrame(update);
              };

              window.addEventListener('scroll', scheduleUpdate, { passive: true });
              window.addEventListener('resize', scheduleUpdate);
              var observer = null;
              if (window.ResizeObserver) {
                if (content) {
                  observer = new ResizeObserver(scheduleUpdate);
                  observer.observe(content);
                }
              }
              const cleanup = () => {
                window.removeEventListener('scroll', scheduleUpdate);
                window.removeEventListener('resize', scheduleUpdate);
                observer?.disconnect();
                window.__moduOutlineTracking = null;
              };
              window.__moduOutlineTracking = { cleanup };
              window.addEventListener('pagehide', cleanup, { once: true });
              scheduleUpdate();
            })();
            """
            webView.evaluateJavaScript(script)
        }

        private static func webContentRecoveryFailureHTML(style: ResolvedReaderTheme?) -> String {
            let stylesheet = style?.stylesheet ?? ""
            return """
            <!doctype html>
            <html lang="\(L10n.htmlLanguageCode)">
            <head>
              <meta charset="utf-8">
              <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
              <style id="modu-theme">\(stylesheet)</style>
            </head>
            <body>
              <main id="write">
                <h2>\(htmlEscaped(L10n.string(.webViewRecoveryTitle)))</h2>
                <p>\(htmlEscaped(L10n.string(.webViewRecoveryMessage)))</p>
              </main>
            </body>
            </html>
            """
        }

        nonisolated private static func javaScriptLiteral(_ value: String) -> String? {
            guard
                let data = try? JSONSerialization.data(withJSONObject: [value]),
                var encoded = String(data: data, encoding: .utf8)
            else { return nil }
            encoded.removeFirst()
            encoded.removeLast()
            return encoded
        }

        private static func htmlEscaped(_ value: String) -> String {
            value
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }

        nonisolated static var staticHTMLCompatibilityScript: String {
            """
            (() => {
              if (window.__moduStaticHTML) return true;

              const root = document.querySelector('#write.modu-html-document');
              if (!root) return false;

              const slides = Array.from(root.querySelectorAll('.slide'));
              if (slides.length < 2) return false;

              const visibleSlides = slides.filter(slide => getComputedStyle(slide).display !== 'none');
              const parent = slides[0].parentElement;
              if (
                visibleSlides.length > 1 ||
                !parent ||
                !slides.every(slide => slide.parentElement === parent)
              ) {
                return false;
              }

              const fallbackStyle = document.createElement('style');
              fallbackStyle.id = 'modu-static-html-fallback';
              fallbackStyle.textContent = `
                html.modu-static-html,
                html.modu-static-html body {
                  height: auto !important;
                  min-height: 100% !important;
                  overflow: auto !important;
                }
                #write.modu-html-document.modu-static-slides {
                  width: 100% !important;
                  max-width: none !important;
                  min-height: 100% !important;
                  margin: 0 !important;
                  padding: 24px !important;
                  overflow: visible !important;
                }
                #write.modu-html-document .modu-static-slide-stack {
                  position: static !important;
                  inset: auto !important;
                  display: flex !important;
                  flex-direction: column !important;
                  align-items: center !important;
                  justify-content: flex-start !important;
                  width: 100% !important;
                  height: auto !important;
                  min-height: 0 !important;
                  overflow: visible !important;
                }
                #write.modu-html-document .modu-static-slide-frame {
                  position: relative !important;
                  flex: none !important;
                  margin: 0 auto 24px !important;
                  overflow: visible !important;
                }
                #write.modu-html-document .modu-static-slide-frame > .slide {
                  position: relative !important;
                  inset: auto !important;
                  display: block !important;
                  margin: 0 !important;
                  transform-origin: top left !important;
                }
                #write.modu-html-document #hud,
                #write.modu-html-document #progress {
                  display: none !important;
                }
              `;
              document.head.appendChild(fallbackStyle);
              document.documentElement.classList.add('modu-static-html');
              root.classList.add('modu-static-slides');
              parent.classList.add('modu-static-slide-stack');

              const entries = slides.map(slide => {
                slide.style.setProperty('display', 'block', 'important');
                slide.style.setProperty('position', 'relative', 'important');
                slide.style.setProperty('inset', 'auto', 'important');
                slide.style.setProperty('transform', 'none', 'important');
                slide.style.setProperty('transform-origin', 'top left', 'important');

                const computed = getComputedStyle(slide);
                const width = Math.max(parseFloat(computed.width) || slide.scrollWidth || 1, 1);
                const height = Math.max(parseFloat(computed.height) || slide.scrollHeight || 1, 1);
                const frame = document.createElement('div');
                frame.className = 'modu-static-slide-frame';
                parent.insertBefore(frame, slide);
                frame.appendChild(slide);
                return { slide, frame, width, height };
              });

              let frameRequest = 0;
              const layout = () => {
                frameRequest = 0;
                const rootStyle = getComputedStyle(root);
                const horizontalPadding =
                  (parseFloat(rootStyle.paddingLeft) || 0) +
                  (parseFloat(rootStyle.paddingRight) || 0);
                const availableWidth = Math.max(root.clientWidth - horizontalPadding, 1);

                entries.forEach(({ slide, frame, width, height }) => {
                  const scale = Math.min(1, availableWidth / width);
                  slide.style.setProperty('transform', `scale(${scale})`, 'important');
                  frame.style.width = `${Math.ceil(width * scale)}px`;
                  frame.style.height = `${Math.ceil(height * scale)}px`;
                });
              };
              const scheduleLayout = () => {
                if (frameRequest) return;
                frameRequest = window.requestAnimationFrame(layout);
              };
              const cleanup = () => {
                window.removeEventListener('resize', scheduleLayout);
                if (frameRequest) window.cancelAnimationFrame(frameRequest);
                window.__moduStaticHTML = null;
              };

              window.addEventListener('resize', scheduleLayout, { passive: true });
              window.addEventListener('pagehide', cleanup, { once: true });
              window.__moduStaticHTML = { cleanup, slideCount: slides.length };
              layout();
              return true;
            })();
            """
        }

        nonisolated static func mermaidRenderingScript(isDark: Bool) -> String {
            let unableMessage = javaScriptLiteral(L10n.string(.mermaidUnable)) ?? "\"Mermaid error\""
            let missingMessage = javaScriptLiteral(L10n.string(.mermaidOfflineMissing)) ?? "\"Mermaid unavailable\""
            let renderingMessage = javaScriptLiteral(L10n.string(.mermaidRendering)) ?? "\"Rendering Mermaid…\""
            let syntaxMessage = javaScriptLiteral(L10n.string(.mermaidSyntax)) ?? "\"Check Mermaid syntax.\""
            let failedMessage = javaScriptLiteral(L10n.string(.mermaidFailed)) ?? "\"Mermaid rendering failed.\""
            return """
            (() => {
              const diagrams = Array.from(document.querySelectorAll(
                '.mermaid-diagram[data-mermaid-renderable="true"]'
              ));
              if (diagrams.length === 0) return;

              const generation = (window.__moduMermaidGeneration || 0) + 1;
              window.__moduMermaidGeneration = generation;

              const setError = (diagram, detail) => {
                diagram.classList.remove('is-rendering', 'is-ready');
                diagram.classList.add('is-error');
                diagram.setAttribute('aria-busy', 'false');
                diagram.querySelector('.mermaid-status').textContent = \(unableMessage);
                diagram.querySelector('.mermaid-error-detail').textContent = detail;
              };

              const cleanupTemporaryNode = (identifier) => {
                document.getElementById(identifier)?.remove();
                document.getElementById(`d${identifier}`)?.remove();
              };

              const renderAll = async () => {
                if (generation !== window.__moduMermaidGeneration) return;
                if (!globalThis.mermaid || typeof globalThis.mermaid.render !== 'function') {
                  diagrams.forEach((diagram) => setError(diagram, \(missingMessage)));
                  return;
                }

                const computed = getComputedStyle(document.documentElement);
                const color = (name, fallback) => computed.getPropertyValue(name).trim() || fallback;
                globalThis.mermaid.initialize({
                  startOnLoad: false,
                  securityLevel: 'strict',
                  secure: [
                    'secure', 'securityLevel', 'startOnLoad', 'maxTextSize',
                    'suppressErrorRendering', 'maxEdges', 'theme', 'themeVariables',
                    'themeCSS', 'darkMode', 'htmlLabels', 'fontFamily', 'altFontFamily'
                  ],
                  suppressErrorRendering: true,
                  maxTextSize: 50000,
                  maxEdges: 500,
                  htmlLabels: false,
                  fontFamily: '-apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif',
                  altFontFamily: '-apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif',
                  deterministicIds: true,
                  deterministicIDSeed: `modu-${generation}`,
                  theme: 'base',
                  darkMode: \(isDark ? "true" : "false"),
                  themeVariables: {
                    background: color('--page-bg', '#ffffff'),
                    primaryColor: color('--code-bg', '#f6f8fa'),
                    primaryTextColor: color('--text', '#1f2328'),
                    primaryBorderColor: color('--accent', '#0969da'),
                    secondaryColor: color('--table-head', '#f6f8fa'),
                    secondaryTextColor: color('--text', '#1f2328'),
                    secondaryBorderColor: color('--border', '#d0d7de'),
                    tertiaryColor: color('--table-head', '#f6f8fa'),
                    tertiaryTextColor: color('--text', '#1f2328'),
                    tertiaryBorderColor: color('--border', '#d0d7de'),
                    lineColor: color('--muted', '#656d76'),
                    textColor: color('--text', '#1f2328'),
                    mainBkg: color('--code-bg', '#f6f8fa'),
                    nodeBorder: color('--accent', '#0969da'),
                    clusterBkg: color('--code-bg', '#f6f8fa'),
                    clusterBorder: color('--border', '#d0d7de'),
                    titleColor: color('--heading', '#1f2328'),
                    edgeLabelBackground: color('--page-bg', '#ffffff'),
                    fontFamily: '-apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif'
                  },
                  flowchart: { useMaxWidth: true, htmlLabels: false }
                });

                for (const [index, diagram] of diagrams.entries()) {
                  if (generation !== window.__moduMermaidGeneration) return;

                  const source = diagram.querySelector('.mermaid-source code')?.textContent || '';
                  const output = diagram.querySelector('.mermaid-output');
                  const renderIdentifier = `modu-mermaid-${generation}-${index}`;
                  diagram.classList.remove('is-ready', 'is-error');
                  diagram.classList.add('is-rendering');
                  diagram.setAttribute('aria-busy', 'true');
                  diagram.querySelector('.mermaid-status').textContent = \(renderingMessage);
                  diagram.querySelector('.mermaid-error-detail').textContent = '';

                  try {
                    const result = await globalThis.mermaid.render(renderIdentifier, source);
                    if (generation !== window.__moduMermaidGeneration) {
                      cleanupTemporaryNode(renderIdentifier);
                      return;
                    }
                    output.innerHTML = result.svg;
                    if (typeof result.bindFunctions === 'function') result.bindFunctions(output);
                    diagram.classList.remove('is-rendering', 'is-error');
                    diagram.classList.add('is-ready');
                    diagram.setAttribute('aria-busy', 'false');
                  } catch (error) {
                    cleanupTemporaryNode(renderIdentifier);
                    if (generation !== window.__moduMermaidGeneration) return;
                    const detail = String(error?.message || error || \(syntaxMessage)).slice(0, 240);
                    setError(diagram, detail);
                  }
                }
              };

              const guardedRender = async () => {
                try {
                  await renderAll();
                } catch (error) {
                  if (generation !== window.__moduMermaidGeneration) return;
                  const detail = String(error?.message || error || \(failedMessage)).slice(0, 240);
                  diagrams.forEach((diagram) => setError(diagram, detail));
                }
              };

              window.__moduMermaidPending = guardedRender;
              if (window.__moduMermaidRunning) return;
              window.__moduMermaidRunning = true;
              void (async () => {
                while (window.__moduMermaidPending) {
                  const nextRender = window.__moduMermaidPending;
                  window.__moduMermaidPending = null;
                  await nextRender();
                }
              })().finally(() => {
                window.__moduMermaidRunning = false;
              });
            })();
            """
        }
    }
}

private final class FocusReportingWebView: WKWebView {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        onFocus?()
        super.mouseDown(with: event)
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
