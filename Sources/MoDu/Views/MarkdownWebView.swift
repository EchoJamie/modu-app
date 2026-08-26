import AppKit
import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let document: RenderedMarkdown
    let documentURL: URL
    let rootURL: URL
    let style: ResolvedReaderTheme
    let scrollRequest: ScrollRequest?
    let onOpenMarkdown: (URL, String?) -> Void
    let onActiveHeading: (String?) -> Void
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            rootURL: rootURL,
            onOpenMarkdown: onOpenMarkdown,
            onActiveHeading: onActiveHeading
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(
            context.coordinator.resourceHandler,
            forURLScheme: MarkdownRenderer.resourceScheme
        )
        configuration.setURLSchemeHandler(
            context.coordinator.bundledAssetHandler,
            forURLScheme: MarkdownRenderer.bundledAssetScheme
        )
        configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: context.coordinator),
            name: Coordinator.outlineMessageName
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
        context.coordinator.lastOutline = document.outline
        context.coordinator.renderingMode = document.renderingMode
        context.coordinator.lastStyle = style
        context.coordinator.webContentRecoveryCount = 0
        context.coordinator.resourceHandler.rootURL = rootURL
        context.coordinator.loadCurrentDocument(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenMarkdown = onOpenMarkdown
        context.coordinator.onActiveHeading = onActiveHeading
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
            context.coordinator.lastOutline = document.outline
            context.coordinator.renderingMode = document.renderingMode
            context.coordinator.lastStyle = style
            context.coordinator.lastScrollID = nil
            context.coordinator.lastReportedAnchor = nil
            context.coordinator.webContentRecoveryCount = 0
            context.coordinator.pendingAnchor = scrollRequest?.anchor
            context.coordinator.loadCurrentDocument(in: webView)
        } else if context.coordinator.lastStyle != style {
            context.coordinator.lastStyle = style
            if document.renderingMode == .styledDocument {
                context.coordinator.apply(style: style, to: webView)
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
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.outlineMessageName
        )
        coordinator.onOpenMarkdown = nil
        coordinator.onActiveHeading = nil
        coordinator.pendingAnchor = nil
        coordinator.lastDocumentHTML = nil
        coordinator.lastOutline = []
        (webView as? FocusReportingWebView)?.onFocus = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let outlineMessageName = "moduOutline"

        let resourceHandler: LocalResourceSchemeHandler
        let bundledAssetHandler = BundledAssetSchemeHandler()
        var onOpenMarkdown: ((URL, String?) -> Void)?
        var onActiveHeading: ((String?) -> Void)?
        var lastDocumentID: UUID?
        var lastDocumentURL: URL?
        var lastRootURL: URL?
        var lastDocumentHTML: String?
        var lastOutline: [OutlineItem] = []
        var renderingMode: ReaderDocumentRenderingMode = .styledDocument
        var lastStyle: ResolvedReaderTheme?
        var lastScrollID: UUID?
        var pendingAnchor: String?
        var lastReportedAnchor: String?
        var webContentRecoveryCount = 0
        var interactiveLoadFinished = false
        var isDisplayingHTMLFallback = false
        private static let maximumWebContentRecoveries = 1

        init(
            rootURL: URL,
            onOpenMarkdown: @escaping (URL, String?) -> Void,
            onActiveHeading: @escaping (String?) -> Void
        ) {
            resourceHandler = LocalResourceSchemeHandler(rootURL: rootURL)
            self.onOpenMarkdown = onOpenMarkdown
            self.onActiveHeading = onActiveHeading
        }

        func loadCurrentDocument(in webView: WKWebView) {
            webView.stopLoading()
            interactiveLoadFinished = false
            isDisplayingHTMLFallback = false

            if
                renderingMode == .interactiveHTML,
                let documentURL = lastDocumentURL,
                let rootURL = lastRootURL
            {
                webView.loadFileURL(documentURL, allowingReadAccessTo: rootURL)
            } else if let lastDocumentHTML {
                webView.loadHTMLString(lastDocumentHTML, baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if renderingMode == .interactiveHTML, !isDisplayingHTMLFallback {
                interactiveLoadFinished = true
                if let pendingAnchor {
                    self.pendingAnchor = nil
                    scroll(to: pendingAnchor, in: webView)
                }
                installInteractiveHTMLOutline(in: webView)
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
            if renderingMode == .interactiveHTML, let documentURL = lastDocumentURL, let rootURL = lastRootURL {
                interactiveLoadFinished = false
                isDisplayingHTMLFallback = false
                webView.loadFileURL(documentURL, allowingReadAccessTo: rootURL)
            } else {
                webView.loadHTMLString(lastDocumentHTML, baseURL: nil)
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
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
            if
                url.absoluteString == "about:blank" ||
                url.absoluteString.hasPrefix("about:blank#") ||
                (
                    scheme == nil &&
                    url.path.isEmpty &&
                    url.query == nil &&
                    url.fragment != nil
                )
            {
                decisionHandler(.allow)
                return
            }

            if renderingMode == .interactiveHTML, !isDisplayingHTMLFallback {
                if scheme == "file" {
                    guard
                        let rootURL = lastRootURL,
                        (try? FileSystemService.validate(url, inside: rootURL)) != nil
                    else {
                        decisionHandler(.cancel)
                        return
                    }

                    if
                        navigationAction.targetFrame?.isMainFrame != false,
                        FileNode.markdownExtensions.contains(url.pathExtension.lowercased())
                    {
                        decisionHandler(.cancel)
                        onOpenMarkdown?(url, url.fragment)
                    } else {
                        decisionHandler(.allow)
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

            if scheme == MarkdownRenderer.markdownScheme {
                decisionHandler(.cancel)
                guard
                    let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "path" })?.value,
                    let rootURL = resourceHandler.rootURL
                else { return }

                let candidate = rootURL.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
                guard
                    FileNode.previewableExtensions.contains(candidate.pathExtension.lowercased()),
                    (try? FileSystemService.validate(candidate, inside: rootURL)) != nil
                else { return }
                onOpenMarkdown?(candidate, url.fragment)
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
            guard let literal = Self.javaScriptLiteral(style.stylesheet) else { return }
            let script = """
            document.getElementById('modu-theme').textContent = \(literal);
            \(Self.mermaidRenderingScript(isDark: style.isDark))
            """
            webView.evaluateJavaScript(script)
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

        private func showInteractiveHTMLFallbackIfNeeded(in webView: WKWebView) {
            guard
                renderingMode == .interactiveHTML,
                !interactiveLoadFinished,
                !isDisplayingHTMLFallback,
                let lastDocumentHTML
            else { return }
            isDisplayingHTMLFallback = true
            webView.loadHTMLString(lastDocumentHTML, baseURL: nil)
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

final class BundledAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    private static let maximumAssetSize = 5 * 1_024 * 1_024

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard
            let requestURL = urlSchemeTask.request.url,
            requestURL.scheme == MarkdownRenderer.bundledAssetScheme,
            requestURL.host == "mermaid",
            requestURL.path == "/mermaid-\(MarkdownRenderer.mermaidVersion).min.js"
        else {
            fail(urlSchemeTask, code: .badURL)
            return
        }

        guard let assetURL = Self.mermaidAssetURL else {
            fail(urlSchemeTask, code: .fileDoesNotExist)
            return
        }

        do {
            let values = try assetURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= Self.maximumAssetSize else {
                fail(urlSchemeTask, code: .dataLengthExceedsMaximum)
                return
            }

            let data = try Data(contentsOf: assetURL, options: [.mappedIfSafe])
            let response = URLResponse(
                url: requestURL,
                mimeType: "application/javascript",
                expectedContentLength: data.count,
                textEncodingName: "utf-8"
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    static var mermaidAssetURL: URL? {
        Bundle.main.url(
            forResource: "mermaid.min",
            withExtension: "js",
            subdirectory: "Mermaid"
        ) ?? AppResources.bundle.url(
            forResource: "mermaid.min",
            withExtension: "js",
            subdirectory: "Mermaid"
        )
    }

    private func fail(_ task: WKURLSchemeTask, code: URLError.Code) {
        task.didFailWithError(URLError(code))
    }
}

final class LocalResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private static let mimeTypes: [String: String] = [
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "heic": "image/heic",
        "heif": "image/heif",
        "tif": "image/tiff",
        "tiff": "image/tiff",
        "bmp": "image/bmp"
    ]

    static func supports(_ fileExtension: String) -> Bool {
        mimeTypes[fileExtension.lowercased()] != nil
    }

    var rootURL: URL?

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard
            let requestURL = urlSchemeTask.request.url,
            requestURL.scheme == MarkdownRenderer.resourceScheme,
            let relativePath = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "path" })?.value,
            let rootURL,
            !relativePath.isEmpty
        else {
            fail(urlSchemeTask, code: .badURL)
            return
        }

        let candidate = rootURL.appendingPathComponent(relativePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let fileExtension = candidate.pathExtension.lowercased()
        guard
            let mimeType = Self.mimeTypes[fileExtension],
            (try? FileSystemService.validate(candidate, inside: rootURL)) != nil
        else {
            fail(urlSchemeTask, code: .noPermissionsToReadFile)
            return
        }

        do {
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= 40 * 1_024 * 1_024 else {
                fail(urlSchemeTask, code: .dataLengthExceedsMaximum)
                return
            }
            let data = try Data(contentsOf: candidate, options: [.mappedIfSafe])
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func fail(_ task: WKURLSchemeTask, code: URLError.Code) {
        task.didFailWithError(URLError(code))
    }
}
