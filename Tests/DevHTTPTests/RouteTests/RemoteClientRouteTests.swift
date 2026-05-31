// ABOUTME: Route tests for the browser-based iPad remote-control client assets.
// ABOUTME: Guards against serving an HTML shell whose Pair button has no JavaScript.

import Foundation
import Testing

@Suite("Remote client routes")
struct RemoteClientRouteTests {
    @Test("remote page references served client script")
    @MainActor
    func remotePageReferencesServedClientScript() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0)
        defer { server.stop() }
        try server.start()
        let port = try #require(server.boundPort)

        let (htmlData, htmlResponse) = try await URLSession.shared.data(
            from: URL(string: "http://localhost:\(port)/remote")!)
        let htmlHTTP = try #require(htmlResponse as? HTTPURLResponse)
        #expect(htmlHTTP.statusCode == 200)
        let html = try #require(String(data: htmlData, encoding: .utf8))
        #expect(html.contains("<script src=\"client.js\"></script>"))

        let (scriptData, scriptResponse) = try await URLSession.shared.data(
            from: URL(string: "http://localhost:\(port)/client.js")!)
        let scriptHTTP = try #require(scriptResponse as? HTTPURLResponse)
        #expect(scriptHTTP.statusCode == 200)
        #expect(scriptHTTP.value(forHTTPHeaderField: "Content-Type")?.contains("application/javascript") == true)
        let script = try #require(String(data: scriptData, encoding: .utf8))
        #expect(script.contains("pairBtnEl.addEventListener('click', sendPair)"))
    }
}
