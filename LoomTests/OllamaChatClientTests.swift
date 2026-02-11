import Testing
@testable import Loom

struct OllamaChatClientTests {
    @Test
    func parseStreamLineDelta() throws {
        let line = "{\"message\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"done\":false}"
        let event = try OllamaChatClient.parseStreamLine(line)

        #expect(event?.delta == "Hello")
        #expect(event?.done == false)
        #expect(event?.error == nil)
    }

    @Test
    func parseStreamLineDone() throws {
        let line = "{\"done\":true}"
        let event = try OllamaChatClient.parseStreamLine(line)

        #expect(event?.delta == "")
        #expect(event?.done == true)
        #expect(event?.error == nil)
    }

    @Test
    func parseStreamLineError() throws {
        let line = "{\"error\":\"model not found\",\"done\":true}"
        let event = try OllamaChatClient.parseStreamLine(line)

        #expect(event?.error == "model not found")
        #expect(event?.done == true)
    }

    @Test
    func parseStreamLineIgnoresWhitespace() throws {
        #expect(try OllamaChatClient.parseStreamLine("   ") == nil)
    }

    @Test
    func parseStreamLineTrimsOuterWhitespace() throws {
        let line = "  {\"message\":{\"content\":\"Hi\"},\"done\":false}  "
        let event = try OllamaChatClient.parseStreamLine(line)

        #expect(event?.delta == "Hi")
        #expect(event?.done == false)
        #expect(event?.error == nil)
    }

    @Test
    func parseStreamLineReturnsErrorAndDoneWhenServerSignalsFailure() throws {
        let line = "{\"message\":{\"content\":\"\"},\"error\":\"model is loading\",\"done\":true}"
        let event = try OllamaChatClient.parseStreamLine(line)

        #expect(event?.delta == "")
        #expect(event?.done == true)
        #expect(event?.error == "model is loading")
    }

    @Test
    func parseStreamLineThrowsOnMalformedJSON() {
        let malformed = "{\"message\":{\"content\":\"Hello\"},\"done\":false"

        var didThrow = false
        do {
            _ = try OllamaChatClient.parseStreamLine(malformed)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }
}
