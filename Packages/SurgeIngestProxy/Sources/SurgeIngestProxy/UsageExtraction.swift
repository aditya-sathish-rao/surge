import Foundation

struct UsageReport: Sendable, Equatable {
    let modelName: String?
    let inputTokens: Int
    let outputTokens: Int
    let cacheHitTokens: Int
    /// The provider's own exact cost for the call, when it reports one (OpenRouter with
    /// `usage: { include: true }`). Nil means no reported cost, not a cost of zero.
    let reportedCostUSD: Double?

    init(
        modelName: String?,
        inputTokens: Int,
        outputTokens: Int,
        cacheHitTokens: Int,
        reportedCostUSD: Double? = nil
    ) {
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheHitTokens = cacheHitTokens
        self.reportedCostUSD = reportedCostUSD
    }
}

enum JSONUsageParser {
    static func model(from data: Data) -> String? {
        guard let object = jsonObject(from: data) else { return nil }
        return object["model"] as? String
    }

    static func report(from data: Data, fallbackModel: String?) -> UsageReport? {
        guard let object = jsonObject(from: data) else { return nil }
        return report(from: object, fallbackModel: fallbackModel)
    }

    static func report(from object: [String: Any], fallbackModel: String?) -> UsageReport? {
        guard let usage = object["usage"] as? [String: Any] else { return nil }
        let input = integer(usage["prompt_tokens"]) ?? integer(usage["input_tokens"])
        guard let input else { return nil }
        let output = integer(usage["completion_tokens"]) ?? integer(usage["output_tokens"]) ?? 0
        let cache =
            integer(usage["prompt_cache_hit_tokens"])
            ?? integer(usage["cache_read_input_tokens"])
            ?? integer((usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"])
            ?? 0
        let model = object["model"] as? String ?? fallbackModel
        return UsageReport(
            modelName: model,
            inputTokens: input,
            outputTokens: output,
            cacheHitTokens: cache,
            reportedCostUSD: Self.cost(usage["cost"])
        )
    }

    private static func cost(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            let amount = number.doubleValue
            return amount.isFinite && amount >= 0 ? amount : nil
        }
        if let string = value as? String, let amount = Double(string) {
            return amount.isFinite && amount >= 0 ? amount : nil
        }
        return nil
    }

    private static func jsonObject(from data: Data) -> [String: Any]? {
        guard !data.isEmpty, let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return parsed as? [String: Any]
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }
}

/// Incremental SSE reader for the final `usage` event. It never needs the full response buffered.
struct SSEUsageCollector {
    private static let maximumLineBytes = 1_048_576
    private static let dataPrefix = Array("data:".utf8)

    private var buffer = Data()
    private var modelName: String?
    private var report: UsageReport?
    private var sawDone = false

    mutating func consume(_ data: Data) {
        guard !sawDone else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex...newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            process(line: line)
            if sawDone { return }
        }
        if buffer.count > Self.maximumLineBytes {
            buffer.removeAll()
        }
    }

    mutating func finish() -> UsageReport? {
        if !sawDone, !buffer.isEmpty {
            process(line: buffer)
        }
        buffer.removeAll()
        return report
    }

    private mutating func process(line: Data) {
        var bytes = line
        if bytes.last == 0x0A {
            bytes.removeLast()
        }
        if bytes.last == 0x0D {
            bytes.removeLast()
        }
        guard bytes.count > Self.dataPrefix.count, bytes.starts(with: Self.dataPrefix) else {
            return
        }
        var payload = Data(bytes.dropFirst(Self.dataPrefix.count))
        if payload.first == 0x20 {
            payload.removeFirst()
        }
        if payload == Data("[DONE]".utf8) {
            sawDone = true
            return
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: payload),
            let object = parsed as? [String: Any]
        else {
            return
        }
        if let model = object["model"] as? String {
            modelName = model
        }
        if let found = JSONUsageParser.report(from: object, fallbackModel: modelName) {
            report = found
        }
    }
}

/// Chooses the right inspector for a response without ever holding the whole stream.
struct ResponseUsageCollector {
    private enum Mode {
        case undecided
        case sse
        case json
        case ignored
    }

    private static let maximumJSONBytes = 4 * 1_048_576
    private static let jsonPrefix = Array("{".utf8)
    private static let ssePrefix = Array("data:".utf8)

    private let contentType: String?
    private let fallbackModel: String?
    private var mode: Mode = .undecided
    private var sse = SSEUsageCollector()
    private var json = Data()

    init(contentType: String?, fallbackModel: String?) {
        self.contentType = contentType?.lowercased()
        self.fallbackModel = fallbackModel
    }

    mutating func consume(_ data: Data) {
        decideModeIfNeeded(with: data)
        switch mode {
        case .sse:
            sse.consume(data)
        case .json:
            guard json.count < Self.maximumJSONBytes else {
                mode = .ignored
                json.removeAll()
                return
            }
            json.append(data)
        case .undecided, .ignored:
            break
        }
    }

    mutating func finish() -> UsageReport? {
        switch mode {
        case .sse:
            return sse.finish()
        case .json:
            return JSONUsageParser.report(from: json, fallbackModel: fallbackModel)
        case .undecided, .ignored:
            return nil
        }
    }

    private mutating func decideModeIfNeeded(with data: Data) {
        guard case .undecided = mode else { return }
        if let contentType, contentType.contains("text/event-stream") {
            mode = .sse
            return
        }
        if let contentType, contentType.contains("json") {
            mode = .json
            return
        }
        let trimmed = data.drop { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
        if trimmed.starts(with: Self.ssePrefix) {
            mode = .sse
        } else if trimmed.starts(with: Self.jsonPrefix) {
            mode = .json
        } else if !data.isEmpty {
            mode = .ignored
        }
    }
}
