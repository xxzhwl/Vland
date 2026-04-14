/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * WebPluginView - WKWebView wrapper that renders a web plugin and provides
 * a JS ↔ Swift bridge via WKScriptMessageHandler.
 */

import SwiftUI
import WebKit

// MARK: - JS Bridge Protocol Name

let kVlandPluginBridgeName = "vlandPlugin"

// MARK: - Session

@MainActor
final class WebPluginSession: NSObject {
    weak var webView: WKWebView?
    var snapshotJSON: String?

    func captureLatestState(completion: @escaping () -> Void) {
        guard let webView, webView.url != nil else {
            completion()
            return
        }

        let js = "window.vland && window.vland._serializeState ? window.vland._serializeState() : null"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            if let snapshot = result as? String, !snapshot.isEmpty {
                self?.snapshotJSON = snapshot
            }

            DispatchQueue.main.async {
                completion()
            }
        }
    }
}

// MARK: - WebPluginView

/// NSViewRepresentable wrapping a WKWebView to render a web plugin's HTML.
/// Injects a JS bridge (`window.vland`) so the plugin can:
///   - Read the search query
///   - Copy text to clipboard
///   - Request dismissal
///   - Send results back to the host
///   - Persist common form state across pin/unpin transitions
@MainActor
struct WebPluginView: NSViewRepresentable {
    let session: WebPluginSession
    let pluginDirectory: URL
    let mainHTMLPath: String
    let preloadScriptPath: String?
    let query: String
    let onDismiss: () -> Void
    let onResult: ((String) -> Void)?
    let allowNetwork: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onDismiss: onDismiss, onResult: onResult)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let userController = WKUserContentController()

        let bridgeScript = WKUserScript(
            source: Self.bridgeJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userController.addUserScript(bridgeScript)

        if let preloadPath = preloadScriptPath {
            let preloadURL = pluginDirectory.appendingPathComponent(preloadPath)
            if let preloadJS = try? String(contentsOf: preloadURL, encoding: .utf8) {
                let userScript = WKUserScript(
                    source: preloadJS,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
                userController.addUserScript(userScript)
            }
        }

        userController.add(context.coordinator, name: kVlandPluginBridgeName)
        config.userContentController = userController

        let webView = InteractiveWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.wantsLayer = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.layer?.backgroundColor = NSColor.clear.cgColor

        context.coordinator.attach(webView)
        context.coordinator.update(query: query, onDismiss: onDismiss, onResult: onResult)

        let htmlURL = pluginDirectory.appendingPathComponent(mainHTMLPath)
        if FileManager.default.fileExists(atPath: htmlURL.path) {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: pluginDirectory)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.attach(webView)
        context.coordinator.update(query: query, onDismiss: onDismiss, onResult: onResult)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: kVlandPluginBridgeName)
        if coordinator.session.webView === webView {
            coordinator.session.webView = nil
        }
    }

    // MARK: - Bridge JS

    /// JavaScript injected at document start to provide `window.vland` API.
    static let bridgeJS = """
    (function() {
        'use strict';

        const _listeners = {};
        let _query = '';
        let _snapshotTimer = null;

        function _emit(event, data) {
            const fns = _listeners[event];
            if (fns) fns.forEach(function(fn) { try { fn(data); } catch(e) {} });
        }

        function _formElements() {
            return Array.from(document.querySelectorAll('textarea, input, select'));
        }

        function _elementState(el, index) {
            const tag = el.tagName.toLowerCase();
            const type = typeof el.type === 'string' ? el.type : '';
            const state = {
                index: index,
                tag: tag,
                type: type,
                value: typeof el.value === 'string' ? el.value : '',
                checked: !!el.checked,
                selectedIndex: typeof el.selectedIndex === 'number' ? el.selectedIndex : null,
                scrollTop: typeof el.scrollTop === 'number' ? el.scrollTop : 0,
                scrollLeft: typeof el.scrollLeft === 'number' ? el.scrollLeft : 0
            };

            if (typeof el.selectionStart === 'number') state.selectionStart = el.selectionStart;
            if (typeof el.selectionEnd === 'number') state.selectionEnd = el.selectionEnd;
            return state;
        }

        function _serializeState() {
            const fields = _formElements().map(_elementState);
            const active = document.activeElement;
            const activeIndex = _formElements().indexOf(active);
            return JSON.stringify({
                fields: fields,
                activeIndex: activeIndex >= 0 ? activeIndex : null,
                scrollX: window.scrollX || 0,
                scrollY: window.scrollY || 0
            });
        }

        function _postSnapshot() {
            try {
                window.webkit.messageHandlers.vlandPlugin.postMessage({
                    action: 'snapshotState',
                    snapshot: _serializeState()
                });
            } catch (e) {}
        }

        function _scheduleSnapshot() {
            if (_snapshotTimer) clearTimeout(_snapshotTimer);
            _snapshotTimer = setTimeout(function() {
                _snapshotTimer = null;
                _postSnapshot();
            }, 0);
        }

        function _restoreState(snapshot) {
            if (!snapshot || !Array.isArray(snapshot.fields)) return;
            const elements = _formElements();

            snapshot.fields.forEach(function(saved) {
                const el = elements[saved.index];
                if (!el) return;

                const isToggle = saved.tag === 'input' && (saved.type === 'checkbox' || saved.type === 'radio');
                if (isToggle) {
                    el.checked = !!saved.checked;
                } else if (saved.tag === 'select' && typeof saved.selectedIndex === 'number') {
                    el.selectedIndex = saved.selectedIndex;
                } else if (typeof saved.value === 'string') {
                    el.value = saved.value;
                }

                if (typeof saved.scrollTop === 'number') el.scrollTop = saved.scrollTop;
                if (typeof saved.scrollLeft === 'number') el.scrollLeft = saved.scrollLeft;

                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));

                if (typeof saved.selectionStart === 'number' && typeof saved.selectionEnd === 'number' && typeof el.setSelectionRange === 'function') {
                    try { el.setSelectionRange(saved.selectionStart, saved.selectionEnd); } catch (e) {}
                }
            });

            if (typeof snapshot.scrollX === 'number' || typeof snapshot.scrollY === 'number') {
                window.scrollTo(snapshot.scrollX || 0, snapshot.scrollY || 0);
            }

            if (typeof snapshot.activeIndex === 'number') {
                const activeEl = elements[snapshot.activeIndex];
                if (activeEl && typeof activeEl.focus === 'function') {
                    try { activeEl.focus(); } catch (e) {}
                }
            }

            _scheduleSnapshot();
        }

        document.addEventListener('input', _scheduleSnapshot, true);
        document.addEventListener('change', _scheduleSnapshot, true);

        window.vland = {
            _setQuery: function(q) {
                _query = q;
                _emit('queryChange', q);
            },

            _emit: _emit,

            on: function(event, fn) {
                if (!_listeners[event]) _listeners[event] = [];
                _listeners[event].push(fn);
            },

            off: function(event, fn) {
                if (!_listeners[event]) return;
                _listeners[event] = _listeners[event].filter(function(f) { return f !== fn; });
            },

            _serializeState: _serializeState,
            _restoreState: _restoreState,

            get query() { return _query; },

            copyToClipboard: function(text) {
                window.webkit.messageHandlers.vlandPlugin.postMessage({
                    action: 'copyToClipboard',
                    text: text
                });
            },

            dismiss: function() {
                window.webkit.messageHandlers.vlandPlugin.postMessage({
                    action: 'dismiss'
                });
            },

            setResult: function(text) {
                window.webkit.messageHandlers.vlandPlugin.postMessage({
                    action: 'setResult',
                    text: text
                });
            },

            showNotification: function(message) {
                window.webkit.messageHandlers.vlandPlugin.postMessage({
                    action: 'showNotification',
                    text: message
                });
            }
        };

        document.addEventListener('DOMContentLoaded', function() {
            _emit('ready', { query: _query });
            _scheduleSnapshot();
        });

        if (document.readyState !== 'loading') {
            setTimeout(function() {
                _emit('ready', { query: _query });
                _scheduleSnapshot();
            }, 0);
        }
    })();
    """

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let session: WebPluginSession
        var webView: WKWebView?
        var query: String = ""
        var onDismiss: () -> Void
        var onResult: ((String) -> Void)?

        init(session: WebPluginSession, onDismiss: @escaping () -> Void, onResult: ((String) -> Void)?) {
            self.session = session
            self.onDismiss = onDismiss
            self.onResult = onResult
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            session.webView = webView
        }

        func update(query: String, onDismiss: @escaping () -> Void, onResult: ((String) -> Void)?) {
            self.query = query
            self.onDismiss = onDismiss
            self.onResult = onResult
            pushQueryToPageIfPossible()
        }

        private func pushQueryToPageIfPossible() {
            guard let webView, webView.url != nil else { return }
            let js = "if(window.vland){window.vland._setQuery(\(query.jsonEscaped))}"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func restoreSnapshotIfNeeded() {
            guard let webView, let snapshot = session.snapshotJSON, !snapshot.isEmpty else { return }
            let js = "if(window.vland && window.vland._restoreState){window.vland._restoreState(\(snapshot))}"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }

            switch action {
            case "dismiss":
                DispatchQueue.main.async { self.onDismiss() }

            case "copyToClipboard":
                if let text = body["text"] as? String {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                }

            case "setResult":
                if let text = body["text"] as? String {
                    onResult?(text)
                }

            case "showNotification":
                if let text = body["text"] as? String {
                    DispatchQueue.main.async {
                        let notification = NSUserNotification()
                        notification.title = "Plugin"
                        notification.informativeText = text
                        notification.deliveryDate = Date()
                        NSUserNotificationCenter.default.deliver(notification)
                    }
                }

            case "snapshotState":
                if let snapshot = body["snapshot"] as? String, !snapshot.isEmpty {
                    session.snapshotJSON = snapshot
                }

            default:
                break
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pushQueryToPageIfPossible()
            restoreSnapshotIfNeeded()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""
            if scheme == "file" || scheme == "about" || scheme == "data" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }

    // MARK: - Interactive WebView

    private final class InteractiveWKWebView: WKWebView {
        override var acceptsFirstResponder: Bool { true }
    }
}

// MARK: - String Helper

private extension String {
    /// Escapes a string for safe inclusion in a JavaScript string literal.
    var jsonEscaped: String {
        var result = self
        result = result.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "\"", with: "\\\"")
        result = result.replacingOccurrences(of: "'", with: "\\'")
        result = result.replacingOccurrences(of: "\n", with: "\\n")
        result = result.replacingOccurrences(of: "\r", with: "\\r")
        result = result.replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(result)\""
    }
}
