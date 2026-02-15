import AppKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class StatusViewModel {
    struct LocalRuntimeHealthEntry: Identifiable, Sendable, Equatable {
        let id: UUID
        let checkedAt: Date
        let readiness: LoomReadiness
        let ollamaReachable: Bool
        let installedModelCount: Int
        let lowDiskSpace: Bool
    }

    private let log = Logger(subsystem: "com.loom.app", category: "StatusViewModel")
    private let client: any OllamaStatusProviding
    private var refreshTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private let runtimeHistoryLimit = 12

    private nonisolated static func isAutoRefreshEnabled() -> Bool {
        if let stored = UserDefaults.standard.object(forKey: LoomPreferenceKeys.statusAutoRefreshEnabled) as? Bool {
            return stored
        }
        return true
    }

    var snapshot: LoomStatusSnapshot = .unavailable
    var isRefreshing: Bool = false
    var lastRefreshAt: Date?
    var ollamaAppInstalled: Bool = false
    var recentRuntimeHealth: [LocalRuntimeHealthEntry] = []

    init(client: any OllamaStatusProviding = OllamaClient()) {
        self.client = client
    }

    func startMonitoring() {
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                guard Self.isAutoRefreshEnabled() else { return }
                Task { await self.refresh() }
            }
        }

        if refreshTask == nil {
            refreshTask = Task { [weak self] in
                guard let self else { return }

                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    guard Self.isAutoRefreshEnabled() else { continue }
                    await self.refresh()
                }
            }
        }

        Task { await refresh() }
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil

        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshAt = Date()
        }

        let diagnosis = await client.diagnose()
        ollamaAppInstalled = diagnosis.isInstalled
        let isReachable = diagnosis.isRunning
        let diskSpace = DiskSpaceSnapshot.currentForOllamaModels()

        var models: [OllamaModel] = []
        if isReachable {
            do {
                let listedModels = try await client.listModels()
                models = listedModels
            } catch {
                log.error("Failed to list models: \(String(describing: error), privacy: .public)")
            }
        }

        let activeModelTag = UserDefaults.standard.string(forKey: LoomPreferenceKeys.activeModelTag)?.nonEmptyTrimmed

        snapshot = LoomStatusSnapshot(
            ollamaReachable: isReachable,
            installedModelCount: models.count,
            activeModelTag: activeModelTag,
            offlineAvailable: isReachable && !models.isEmpty && activeModelTag != nil,
            diskSpace: diskSpace
        )

        recordRuntimeHealth(snapshot: snapshot)
    }

    var ollamaActionTitle: String {
        if snapshot.ollamaReachable {
            return "Ollama is running"
        }
        return ollamaAppInstalled ? "Start Ollama" : "Install Ollama…"
    }

    func openOrInstallOllama() {
        if let appURL = Self.ollamaAppURL() {
            NSWorkspace.shared.open(appURL)
        } else {
            NSWorkspace.shared.open(Self.ollamaDownloadURL)
        }
    }

    private static let ollamaDownloadURL = URL(string: "https://ollama.com/download")!

    private func recordRuntimeHealth(snapshot: LoomStatusSnapshot) {
        let entry = LocalRuntimeHealthEntry(
            id: UUID(),
            checkedAt: Date(),
            readiness: snapshot.readiness,
            ollamaReachable: snapshot.ollamaReachable,
            installedModelCount: snapshot.installedModelCount,
            lowDiskSpace: snapshot.lowDiskSpaceWarning != nil
        )

        if let last = recentRuntimeHealth.last,
           last.readiness == entry.readiness,
           last.ollamaReachable == entry.ollamaReachable,
           last.installedModelCount == entry.installedModelCount,
           last.lowDiskSpace == entry.lowDiskSpace,
           entry.checkedAt.timeIntervalSince(last.checkedAt) < 25 {
            recentRuntimeHealth[recentRuntimeHealth.count - 1] = entry
        } else {
            recentRuntimeHealth.append(entry)
            if recentRuntimeHealth.count > runtimeHistoryLimit {
                recentRuntimeHealth.removeFirst(recentRuntimeHealth.count - runtimeHistoryLimit)
            }
        }
    }

    private static func ollamaAppURL() -> URL? {
        let bundleIdentifiers = [
            "ai.ollama.Ollama",
            "com.ollama.app"
        ]

        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }

        let fallbackPaths = [
            "/Applications/Ollama.app",
            NSString(string: "~/Applications/Ollama.app").expandingTildeInPath
        ]

        for path in fallbackPaths where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }
}

nonisolated enum AIChatbotOperationalState: String, Sendable, Equatable {
    case operational
    case degraded
    case outage
    case unknown

    var label: String {
        switch self {
        case .operational: "Operational"
        case .degraded: "Issues"
        case .outage: "Outage"
        case .unknown: "Unknown"
        }
    }
}

nonisolated struct AIChatbotServiceSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let homepageURL: URL
    let statusPageURL: URL
    let state: AIChatbotOperationalState
    let summary: String
    let knownIssues: [String]
    let checkedAt: Date
}

protocol AIChatbotStatusProviding: Actor {
    func placeholderSnapshots() -> [AIChatbotServiceSnapshot]
    func fetchStatuses() async -> [AIChatbotServiceSnapshot]
}

actor AIChatbotStatusClient: AIChatbotStatusProviding {
    struct ServiceDefinition: Sendable {
        let id: String
        let name: String
        let homepageURL: URL
        let statusPageURL: URL
        let feeds: [Feed]
    }

    enum Feed: Sendable {
        case atlassianSummary(URL)
        case atlassianStatus(URL)
        case instatusSummary(URL)
        case statusPageHTML(URL)
    }

    private let session: URLSession
    private let services: [ServiceDefinition]
    private let requestTimeout: TimeInterval

    init(
        session: URLSession = .shared,
        services: [ServiceDefinition] = AIChatbotStatusClient.defaultServices,
        requestTimeout: TimeInterval = 12
    ) {
        self.session = session
        self.services = services
        self.requestTimeout = requestTimeout
    }

    func placeholderSnapshots() -> [AIChatbotServiceSnapshot] {
        let now = Date()
        return services.map { service in
            AIChatbotServiceSnapshot(
                id: service.id,
                name: service.name,
                homepageURL: service.homepageURL,
                statusPageURL: service.statusPageURL,
                state: .unknown,
                summary: "Checking status feed...",
                knownIssues: [],
                checkedAt: now
            )
        }
    }

    func fetchStatuses() async -> [AIChatbotServiceSnapshot] {
        await withTaskGroup(of: (Int, AIChatbotServiceSnapshot).self) { group in
            for (index, service) in services.enumerated() {
                group.addTask {
                    let snapshot = await self.fetchStatus(for: service)
                    return (index, snapshot)
                }
            }

            var ordered: [(Int, AIChatbotServiceSnapshot)] = []
            for await (index, snapshot) in group {
                ordered.append((index, snapshot))
            }

            return ordered
                .sorted { lhs, rhs in lhs.0 < rhs.0 }
                .map(\.1)
        }
    }

    private func fetchStatus(for service: ServiceDefinition) async -> AIChatbotServiceSnapshot {
        for feed in service.feeds {
            if let snapshot = await fetchSnapshot(from: feed, for: service) {
                return snapshot
            }
        }

        return AIChatbotServiceSnapshot(
            id: service.id,
            name: service.name,
            homepageURL: service.homepageURL,
            statusPageURL: service.statusPageURL,
            state: .unknown,
            summary: "Couldn’t reach the public status feed.",
            knownIssues: [],
            checkedAt: Date()
        )
    }

    private func fetchSnapshot(from feed: Feed, for service: ServiceDefinition) async -> AIChatbotServiceSnapshot? {
        do {
            let data: Data
            switch feed {
            case .atlassianSummary(let url):
                data = try await fetchData(from: url)
                return try Self.parseAtlassianSnapshot(
                    from: data,
                    serviceID: service.id,
                    serviceName: service.name,
                    homepageURL: service.homepageURL,
                    statusPageURL: service.statusPageURL,
                    checkedAt: Date()
                )
            case .atlassianStatus(let url):
                data = try await fetchData(from: url)
                return try Self.parseAtlassianStatusSnapshot(
                    from: data,
                    serviceID: service.id,
                    serviceName: service.name,
                    homepageURL: service.homepageURL,
                    statusPageURL: service.statusPageURL,
                    checkedAt: Date()
                )
            case .instatusSummary(let url):
                data = try await fetchData(from: url)
                return try Self.parseInstatusSnapshot(
                    from: data,
                    serviceID: service.id,
                    serviceName: service.name,
                    homepageURL: service.homepageURL,
                    statusPageURL: service.statusPageURL,
                    checkedAt: Date()
                )
            case .statusPageHTML(let url):
                data = try await fetchData(from: url)
                return Self.parseStatusPageHTMLSnapshot(
                    from: data,
                    serviceID: service.id,
                    serviceName: service.name,
                    homepageURL: service.homepageURL,
                    statusPageURL: service.statusPageURL,
                    checkedAt: Date()
                )
            }
        } catch {
            return nil
        }
    }

    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    nonisolated static func parseAtlassianSnapshot(
        from data: Data,
        serviceID: String,
        serviceName: String,
        homepageURL: URL,
        statusPageURL: URL,
        checkedAt: Date
    ) throws -> AIChatbotServiceSnapshot {
        let decoder = JSONDecoder()
        let response = try decoder.decode(AtlassianSummaryResponse.self, from: data)
        let indicator = response.status.indicator?.lowercased() ?? ""

        let state: AIChatbotOperationalState
        switch indicator {
        case "none":
            state = .operational
        case "minor":
            state = .degraded
        case "major", "critical":
            state = .outage
        default:
            state = .unknown
        }

        var issues: [String] = []
        for incident in response.incidents where (incident.status?.lowercased() ?? "") != "resolved" {
            let title = incident.name.nonEmptyTrimmed ?? "Incident"
            let phase = prettifyStatus(incident.status ?? "active")
            issues.append("\(title) (\(phase))")
        }
        for maintenance in response.scheduledMaintenances where maintenance.status?.lowercased() == "in_progress" {
            let title = maintenance.name.nonEmptyTrimmed ?? "Scheduled maintenance"
            issues.append("Maintenance: \(title)")
        }

        let uniqueIssues = deduplicating(issues)
        let summaryText = response.status.description?.nonEmptyTrimmed ?? state.label

        return AIChatbotServiceSnapshot(
            id: serviceID,
            name: serviceName,
            homepageURL: homepageURL,
            statusPageURL: statusPageURL,
            state: state,
            summary: summaryText,
            knownIssues: uniqueIssues,
            checkedAt: checkedAt
        )
    }

    nonisolated static func parseAtlassianStatusSnapshot(
        from data: Data,
        serviceID: String,
        serviceName: String,
        homepageURL: URL,
        statusPageURL: URL,
        checkedAt: Date
    ) throws -> AIChatbotServiceSnapshot {
        let decoder = JSONDecoder()
        let response = try decoder.decode(AtlassianStatusResponse.self, from: data)
        let indicator = response.status.indicator?.lowercased() ?? ""

        let state: AIChatbotOperationalState
        switch indicator {
        case "none":
            state = .operational
        case "minor":
            state = .degraded
        case "major", "critical":
            state = .outage
        default:
            state = .unknown
        }

        let summary = response.status.description?.nonEmptyTrimmed ?? state.label
        return AIChatbotServiceSnapshot(
            id: serviceID,
            name: serviceName,
            homepageURL: homepageURL,
            statusPageURL: statusPageURL,
            state: state,
            summary: summary,
            knownIssues: [],
            checkedAt: checkedAt
        )
    }

    nonisolated static func parseInstatusSnapshot(
        from data: Data,
        serviceID: String,
        serviceName: String,
        homepageURL: URL,
        statusPageURL: URL,
        checkedAt: Date
    ) throws -> AIChatbotServiceSnapshot {
        let decoder = JSONDecoder()
        let response = try decoder.decode(InstatusSummaryResponse.self, from: data)
        let pageStatus = response.page?.status?.uppercased() ?? ""

        var state = stateFromInstatus(pageStatus)
        var issues: [String] = []

        for incident in response.activeIncidents ?? [] {
            let title = incident.name.nonEmptyTrimmed ?? "Incident"
            let phase = prettifyStatus(incident.status ?? "active")
            issues.append("\(title) (\(phase))")
            if incident.impact?.uppercased() == "MAJOROUTAGE" || incident.impact?.uppercased() == "CRITICAL" {
                state = .outage
            } else if state == .operational {
                state = .degraded
            }
        }

        for maintenance in response.activeMaintenances ?? [] {
            let title = maintenance.name.nonEmptyTrimmed ?? "Scheduled maintenance"
            let phase = prettifyStatus(maintenance.status ?? "active")
            issues.append("Maintenance: \(title) (\(phase))")
            if state == .operational {
                state = .degraded
            }
        }

        let uniqueIssues = deduplicating(issues)
        let summaryText: String
        if uniqueIssues.isEmpty {
            summaryText = state == .operational ? "All systems operational." : state.label
        } else {
            summaryText = "\(uniqueIssues.count) known issue\(uniqueIssues.count == 1 ? "" : "s")."
        }

        return AIChatbotServiceSnapshot(
            id: serviceID,
            name: serviceName,
            homepageURL: homepageURL,
            statusPageURL: statusPageURL,
            state: state,
            summary: summaryText,
            knownIssues: uniqueIssues,
            checkedAt: checkedAt
        )
    }

    nonisolated static func parseStatusPageHTMLSnapshot(
        from data: Data,
        serviceID: String,
        serviceName: String,
        homepageURL: URL,
        statusPageURL: URL,
        checkedAt: Date
    ) -> AIChatbotServiceSnapshot {
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let cleaned = cleanedStatusPageText(fromHTML: html)
        let normalized = cleaned.lowercased()
        let extractedIssueLines = extractIssueLines(from: cleaned)

        let outageSignals = [
            "major outage",
            "critical outage",
            "widespread outage",
            "system is down",
            "systems are down",
            "service is down"
        ]
        let degradedSignals = [
            "partial outage",
            "degraded performance",
            "service disruption",
            "investigating",
            "identified",
            "monitoring",
            "issues affecting",
            "under maintenance"
        ]
        let operationalSignals = [
            "all systems operational",
            "all systems are operational",
            "we're fully operational",
            "we are fully operational",
            "not aware of any issues affecting our systems",
            "no incidents reported"
        ]

        let hasOutageSignal = containsAny(of: outageSignals, in: normalized)
        let hasDegradedSignal = containsAny(of: degradedSignals, in: normalized)
        let hasOperationalSignal = containsAny(of: operationalSignals, in: normalized)

        let state: AIChatbotOperationalState
        if hasOutageSignal {
            state = hasOperationalSignal && extractedIssueLines.isEmpty ? .operational : .outage
        } else if hasDegradedSignal {
            state = hasOperationalSignal && extractedIssueLines.isEmpty ? .operational : .degraded
        } else if hasOperationalSignal {
            state = .operational
        } else {
            state = .unknown
        }

        let knownIssues: [String]
        switch state {
        case .operational:
            knownIssues = []
        case .degraded, .outage:
            knownIssues = extractedIssueLines.isEmpty
                ? ["Check the public status page for current incident details."]
                : extractedIssueLines
        case .unknown:
            knownIssues = []
        }

        let summary: String
        switch state {
        case .operational:
            summary = "All systems operational."
        case .degraded:
            summary = "Status page reports active issues."
        case .outage:
            summary = "Status page reports a major outage."
        case .unknown:
            summary = "Status page reachable, but state is unclear."
        }

        return AIChatbotServiceSnapshot(
            id: serviceID,
            name: serviceName,
            homepageURL: homepageURL,
            statusPageURL: statusPageURL,
            state: state,
            summary: summary,
            knownIssues: knownIssues,
            checkedAt: checkedAt
        )
    }

    private nonisolated static func stateFromInstatus(_ value: String) -> AIChatbotOperationalState {
        switch value {
        case "UP":
            return .operational
        case "HASISSUES", "DEGRADED", "PARTIALOUTAGE", "UNDERMAINTENANCE":
            return .degraded
        case "DOWN", "MAJOROUTAGE":
            return .outage
        default:
            return .unknown
        }
    }

    private nonisolated static func prettifyStatus(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "Active" }
        return normalized.prefix(1).uppercased() + normalized.dropFirst().lowercased()
    }

    private nonisolated static func containsAny(of phrases: [String], in text: String) -> Bool {
        phrases.contains { phrase in
            text.contains(phrase)
        }
    }

    private nonisolated static func cleanedStatusPageText(fromHTML html: String) -> String {
        var prepared = html.replacingOccurrences(
            of: "(?is)<script\\b[^>]*>.*?</script>",
            with: " ",
            options: .regularExpression
        )
        prepared = prepared.replacingOccurrences(
            of: "(?is)<style\\b[^>]*>.*?</style>",
            with: " ",
            options: .regularExpression
        )
        prepared = prepared.replacingOccurrences(
            of: "(?is)<!--.*?-->",
            with: " ",
            options: .regularExpression
        )

        let blockBreakTags = ["</p>", "</li>", "</div>", "<br>", "<br/>", "<br />"]
        for tag in blockBreakTags {
            prepared = prepared.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }

        let withoutTags = prepared.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private nonisolated static func extractIssueLines(from text: String) -> [String] {
        let keywords = [
            "incident",
            "investigating",
            "identified",
            "monitoring",
            "degraded",
            "outage",
            "maintenance",
            "disruption"
        ]

        let filteredLines = text
            .split(separator: "\n")
            .map { segment in
                segment
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                guard line.count >= 12 else { return false }
                guard line.count <= 220 else { return false }
                guard isLikelyHumanReadableStatusLine(line) else { return false }
                let normalized = line.lowercased()
                return keywords.contains(where: normalized.contains)
            }
        let lines = Array(filteredLines.prefix(3))

        return deduplicating(lines)
    }

    private nonisolated static func isLikelyHumanReadableStatusLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let machineNoiseSignals = [
            "self.__next_f.push",
            "_next/static",
            "static/chunks",
            "status_page_id",
            "component_id",
            "children\":[",
            "dpl_",
            "href=",
            "src=",
            "http://",
            "https://"
        ]
        guard !machineNoiseSignals.contains(where: lowercased.contains) else { return false }

        let symbols = line.unicodeScalars.filter { scalar in
            let value = scalar.value
            return value == 123 || value == 125 || value == 91 || value == 93 || value == 92 || value == 34
        }.count
        guard symbols <= 2 else { return false }

        let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 8 else { return false }
        let scalarCount = max(line.unicodeScalars.count, 1)
        let letterRatio = Double(letters) / Double(scalarCount)
        return letterRatio >= 0.4
    }

    private nonisolated static func deduplicating(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        output.reserveCapacity(values.count)
        for value in values {
            if seen.insert(value).inserted {
                output.append(value)
            }
        }
        return output
    }

    nonisolated private static let defaultServices: [ServiceDefinition] = [
        ServiceDefinition(
            id: "chatgpt",
            name: "ChatGPT",
            homepageURL: URL(string: "https://chatgpt.com")!,
            statusPageURL: URL(string: "https://status.openai.com")!,
            feeds: [
                .atlassianSummary(URL(string: "https://status.openai.com/api/v2/summary.json")!),
                .atlassianStatus(URL(string: "https://status.openai.com/api/v2/status.json")!),
                .statusPageHTML(URL(string: "https://status.openai.com")!)
            ]
        ),
        ServiceDefinition(
            id: "claude",
            name: "Claude",
            homepageURL: URL(string: "https://claude.ai")!,
            statusPageURL: URL(string: "https://status.claude.com")!,
            feeds: [
                .atlassianSummary(URL(string: "https://status.claude.com/api/v2/summary.json")!),
                .atlassianStatus(URL(string: "https://status.claude.com/api/v2/status.json")!),
                .atlassianSummary(URL(string: "https://status.anthropic.com/api/v2/summary.json")!),
                .atlassianStatus(URL(string: "https://status.anthropic.com/api/v2/status.json")!),
                .statusPageHTML(URL(string: "https://status.claude.com")!)
            ]
        ),
        ServiceDefinition(
            id: "perplexity",
            name: "Perplexity",
            homepageURL: URL(string: "https://www.perplexity.ai")!,
            statusPageURL: URL(string: "https://status.perplexity.com")!,
            feeds: [
                .instatusSummary(URL(string: "https://status.perplexity.com/summary.json")!),
                .statusPageHTML(URL(string: "https://status.perplexity.com")!)
            ]
        ),
        ServiceDefinition(
            id: "poe",
            name: "Poe",
            homepageURL: URL(string: "https://poe.com")!,
            statusPageURL: URL(string: "https://status.poe.com")!,
            feeds: [
                .atlassianSummary(URL(string: "https://status.poe.com/api/v2/summary.json")!),
                .atlassianStatus(URL(string: "https://status.poe.com/api/v2/status.json")!),
                .statusPageHTML(URL(string: "https://status.poe.com")!)
            ]
        ),
        ServiceDefinition(
            id: "character-ai",
            name: "Character.AI",
            homepageURL: URL(string: "https://character.ai")!,
            statusPageURL: URL(string: "https://status.character.ai")!,
            feeds: [
                .atlassianSummary(URL(string: "https://status.character.ai/api/v2/summary.json")!),
                .atlassianStatus(URL(string: "https://status.character.ai/api/v2/status.json")!),
                .statusPageHTML(URL(string: "https://status.character.ai")!)
            ]
        ),
        ServiceDefinition(
            id: "grok",
            name: "Grok",
            homepageURL: URL(string: "https://x.ai")!,
            statusPageURL: URL(string: "https://status.x.ai")!,
            feeds: [
                .atlassianSummary(URL(string: "https://status.x.ai/api/v2/summary.json")!),
                .atlassianStatus(URL(string: "https://status.x.ai/api/v2/status.json")!),
                .statusPageHTML(URL(string: "https://status.x.ai")!)
            ]
        )
    ]
}

nonisolated private struct AtlassianSummaryResponse: Decodable {
    nonisolated struct Status: Decodable {
        let indicator: String?
        let description: String?
    }

    nonisolated struct Incident: Decodable {
        let name: String
        let status: String?
    }

    nonisolated struct Maintenance: Decodable {
        let name: String
        let status: String?
    }

    let status: Status
    let incidents: [Incident]
    let scheduledMaintenances: [Maintenance]

    enum CodingKeys: String, CodingKey {
        case status
        case incidents
        case scheduledMaintenances = "scheduled_maintenances"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(Status.self, forKey: .status)
        incidents = try container.decodeIfPresent([Incident].self, forKey: .incidents) ?? []
        scheduledMaintenances = try container.decodeIfPresent([Maintenance].self, forKey: .scheduledMaintenances) ?? []
    }
}

nonisolated private struct AtlassianStatusResponse: Decodable {
    nonisolated struct Status: Decodable {
        let indicator: String?
        let description: String?
    }

    let status: Status
}

nonisolated private struct InstatusSummaryResponse: Decodable {
    nonisolated struct Page: Decodable {
        let status: String?
    }

    nonisolated struct Incident: Decodable {
        let name: String
        let status: String?
        let impact: String?
    }

    nonisolated struct Maintenance: Decodable {
        let name: String
        let status: String?
    }

    let page: Page?
    let activeIncidents: [Incident]?
    let activeMaintenances: [Maintenance]?
}

@MainActor
@Observable
final class AIChatbotStatusViewModel {
    private let client: any AIChatbotStatusProviding
    private var refreshTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    var services: [AIChatbotServiceSnapshot]
    var isRefreshing: Bool = false
    var lastRefreshAt: Date?

    init(client: any AIChatbotStatusProviding = AIChatbotStatusClient()) {
        self.client = client
        self.services = []
    }

    func startMonitoring() {
        if services.isEmpty {
            Task {
                let placeholders = await client.placeholderSnapshots()
                if services.isEmpty {
                    services = applyPreferredServiceOrder(to: placeholders)
                    persistServiceOrder()
                }
            }
        }

        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                guard Self.isAutoRefreshEnabled() else { return }
                Task { await self.refresh() }
            }
        }

        if refreshTask == nil {
            refreshTask = Task { [weak self] in
                guard let self else { return }

                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    guard Self.isAutoRefreshEnabled() else { continue }
                    await self.refresh()
                }
            }
        }

        Task { await refresh() }
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil

        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshAt = Date()
        }

        let fetched = await client.fetchStatuses()
        services = applyPreferredServiceOrder(to: fetched)
        persistServiceOrder()
    }

    func moveService(id: String, before destinationID: String) {
        guard let sourceIndex = services.firstIndex(where: { $0.id == id }),
              let destinationIndex = services.firstIndex(where: { $0.id == destinationID }),
              sourceIndex != destinationIndex else { return }

        var reordered = services
        let movedService = reordered.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < destinationIndex ? (destinationIndex - 1) : destinationIndex
        reordered.insert(movedService, at: insertionIndex)

        guard reordered != services else { return }
        services = reordered
        persistServiceOrder()
    }

    func moveServiceToEnd(id: String) {
        guard let sourceIndex = services.firstIndex(where: { $0.id == id }),
              sourceIndex < services.count - 1 else { return }

        var reordered = services
        let movedService = reordered.remove(at: sourceIndex)
        reordered.append(movedService)

        guard reordered != services else { return }
        services = reordered
        persistServiceOrder()
    }

    private nonisolated static func isAutoRefreshEnabled() -> Bool {
        if let stored = UserDefaults.standard.object(forKey: LoomPreferenceKeys.statusAutoRefreshEnabled) as? Bool {
            return stored
        }
        return true
    }

    private var storedServiceOrder: [String] {
        guard let stored = UserDefaults.standard.array(forKey: LoomPreferenceKeys.aiStatusServiceOrder) as? [String] else {
            return []
        }
        return stored.compactMap(\.nonEmptyTrimmed)
    }

    private func applyPreferredServiceOrder(to snapshots: [AIChatbotServiceSnapshot]) -> [AIChatbotServiceSnapshot] {
        let preferredIDs = storedServiceOrder
        guard !preferredIDs.isEmpty else { return snapshots }

        var preferredRank: [String: Int] = [:]
        for (index, id) in preferredIDs.enumerated() where preferredRank[id] == nil {
            preferredRank[id] = index
        }

        var fallbackOrder: [String: Int] = [:]
        for (index, snapshot) in snapshots.enumerated() where fallbackOrder[snapshot.id] == nil {
            fallbackOrder[snapshot.id] = index
        }

        return snapshots.sorted { lhs, rhs in
            let lhsRank = preferredRank[lhs.id]
            let rhsRank = preferredRank[rhs.id]

            switch (lhsRank, rhsRank) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return (fallbackOrder[lhs.id] ?? 0) < (fallbackOrder[rhs.id] ?? 0)
            }
        }
    }

    private func persistServiceOrder() {
        UserDefaults.standard.set(services.map(\.id), forKey: LoomPreferenceKeys.aiStatusServiceOrder)
    }
}
