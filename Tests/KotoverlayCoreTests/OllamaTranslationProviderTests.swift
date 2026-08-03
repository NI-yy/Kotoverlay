import Foundation
import Testing
@testable import KotoverlayCore

@Suite("Ollama translation provider")
struct OllamaTranslationProviderTests {
    @Test("Rejects non-loopback endpoints")
    func rejectsRemoteEndpoint() {
        #expect(throws: OllamaError.invalidEndpoint) {
            _ = try OllamaConfiguration(endpoint: URL(string: "https://example.com")!)
        }
    }

    @Test("Extracts technical terms, code, URLs, and mentions for exact preservation")
    func protectedTokens() throws {
        let source = "@nesnrve Metal failed on win/nux at commandBuffer.commit(); see https://example.com/a"
        let tokens = ProtectedTokenExtractor.tokens(in: source)
        #expect(tokens == [
            "@nesnrve",
            "Metal",
            "win/nux",
            "commandBuffer.commit();",
            "https://example.com/a"
        ])
        let masked = ProtectedTokenMasker.mask(source)
        #expect(masked.replacements.count == 5)
        #expect(try ProtectedTokenMasker.restore(
            masked.maskedText,
            replacements: masked.replacements
        ) == source)
        #expect(throws: OllamaError.protectedTokenLost) {
            _ = try ProtectedTokenMasker.restore(
                "translation without placeholders",
                replacements: masked.replacements
            )
        }
    }

    @Test("Discovers installed models")
    func discoversModels() async throws {
        let transport = MockHTTPTransport(
            dataHandler: { _ in
                HTTPDataResponse(
                    data: Data(#"{"models":[{"name":"qwen3:1.7b","model":"qwen3:1.7b"}]}"#.utf8),
                    statusCode: 200,
                    finalURL: URL(string: "http://127.0.0.1:11434/api/tags")
                )
            }
        )
        let models = try await makeProvider(transport: transport).availableModels()
        #expect(models == [OllamaModel(name: "qwen3:1.7b", model: "qwen3:1.7b")])
    }

    @Test("Streams translation chunks")
    func streamsTranslation() async throws {
        let transport = standardTransport { _, receive in
            try await receive(#"{"response":"シェーダーを","done":false}"#)
            try await receive(#"{"response":"コンパイルする","done":true}"#)
            return HTTPStreamMetadata(
                statusCode: 200,
                finalURL: URL(string: "http://127.0.0.1:11434/api/generate")
            )
        }
        let output = try await collect(
            makeProvider(transport: transport).translationStream(
                for: TranslationRequest(sourceText: "compile the shader")
            )
        )
        #expect(output == "シェーダーをコンパイルする")
    }

    @Test("Reports missing model before generation")
    func missingModel() async {
        let transport = MockHTTPTransport(
            dataHandler: { _ in
                HTTPDataResponse(
                    data: Data(#"{"models":[]}"#.utf8),
                    statusCode: 200,
                    finalURL: URL(string: "http://127.0.0.1:11434/api/tags")
                )
            }
        )
        await expectError(.modelNotInstalled("qwen3:1.7b")) {
            _ = try await collect(
                makeProvider(transport: transport).translationStream(
                    for: TranslationRequest(sourceText: "hello")
                )
            )
        }
    }

    @Test("Maps connection failure")
    func serverUnavailable() async {
        let transport = MockHTTPTransport(dataHandler: { _ in
            throw URLError(.cannotConnectToHost)
        })
        do {
            _ = try await makeProvider(transport: transport).availableModels()
            Issue.record("Expected serverUnavailable")
        } catch let error as OllamaError {
            #expect(error == .serverUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects malformed stream")
    func malformedStream() async {
        let transport = standardTransport { _, receive in
            try await receive("not-json")
            return HTTPStreamMetadata(statusCode: 200)
        }
        await expectError(.malformedStream) {
            _ = try await collect(
                makeProvider(transport: transport).translationStream(
                    for: TranslationRequest(sourceText: "hello")
                )
            )
        }
    }

    @Test("Rejects stream without done record")
    func incompleteStream() async {
        let transport = standardTransport { _, receive in
            try await receive(#"{"response":"途中","done":false}"#)
            return HTTPStreamMetadata(statusCode: 200)
        }
        await expectError(.incompleteStream) {
            _ = try await collect(
                makeProvider(transport: transport).translationStream(
                    for: TranslationRequest(sourceText: "hello")
                )
            )
        }
    }

    @Test("Times out a stalled stream")
    func timeout() async {
        let transport = standardTransport { _, _ in
            try await Task.sleep(for: .seconds(5))
            return HTTPStreamMetadata(statusCode: 200)
        }
        await expectError(.timedOut) {
            _ = try await collect(
                makeProvider(transport: transport, timeout: .milliseconds(100))
                    .translationStream(for: TranslationRequest(sourceText: "hello"))
            )
        }
    }

    @Test("Cancels a stalled translation")
    func cancellation() async {
        let probe = CancellationProbe()
        let transport = standardTransport { _, _ in
            await probe.markStarted()
            do {
                try await Task.sleep(for: .seconds(5))
                return HTTPStreamMetadata(statusCode: 200)
            } catch is CancellationError {
                await probe.markCancelled()
                throw CancellationError()
            }
        }
        let task = Task {
            try await collect(
                makeProvider(transport: transport, timeout: .seconds(10))
                    .translationStream(for: TranslationRequest(sourceText: "hello"))
            )
        }
        for _ in 0..<100 where !(await probe.wasStarted) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        _ = try? await task.value
        for _ in 0..<100 where !(await probe.wasCancelled) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        let transportWasCancelled = await probe.wasCancelled
        #expect(transportWasCancelled)
    }

    private func makeProvider(
        transport: MockHTTPTransport,
        timeout: Duration = .seconds(1)
    ) -> OllamaTranslationProvider {
        let configuration = try! OllamaConfiguration(timeout: timeout)
        return OllamaTranslationProvider(configuration: configuration, transport: transport)
    }

    private func standardTransport(
        streamHandler: @escaping MockHTTPTransport.StreamHandler
    ) -> MockHTTPTransport {
        MockHTTPTransport(
            dataHandler: { _ in
                HTTPDataResponse(
                    data: Data(#"{"models":[{"name":"qwen3:1.7b","model":"qwen3:1.7b"}]}"#.utf8),
                    statusCode: 200,
                    finalURL: URL(string: "http://127.0.0.1:11434/api/tags")
                )
            },
            streamHandler: streamHandler
        )
    }

    private func collect(
        _ stream: AsyncThrowingStream<String, Error>
    ) async throws -> String {
        var output = ""
        for try await chunk in stream {
            output += chunk
        }
        return output
    }

    private func expectError(
        _ expected: OllamaError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expected)")
        } catch let error as OllamaError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private actor CancellationProbe {
    private(set) var wasStarted = false
    private(set) var wasCancelled = false

    func markStarted() {
        wasStarted = true
    }

    func markCancelled() {
        wasCancelled = true
    }
}

private final class MockHTTPTransport: HTTPTransport, @unchecked Sendable {
    typealias DataHandler = @Sendable (URLRequest) async throws -> HTTPDataResponse
    typealias StreamHandler = @Sendable (
        URLRequest,
        @escaping @Sendable (String) async throws -> Void
    ) async throws -> HTTPStreamMetadata

    private let dataHandler: DataHandler
    private let streamHandler: StreamHandler

    init(
        dataHandler: @escaping DataHandler,
        streamHandler: @escaping StreamHandler = { _, _ in
            Issue.record("Unexpected stream request")
            return HTTPStreamMetadata(statusCode: 500)
        }
    ) {
        self.dataHandler = dataHandler
        self.streamHandler = streamHandler
    }

    func data(for request: URLRequest) async throws -> HTTPDataResponse {
        try await dataHandler(request)
    }

    func streamLines(
        for request: URLRequest,
        receive: @escaping @Sendable (String) async throws -> Void
    ) async throws -> HTTPStreamMetadata {
        try await streamHandler(request, receive)
    }
}
