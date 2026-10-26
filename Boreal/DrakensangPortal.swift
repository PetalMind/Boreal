import Foundation

nonisolated enum DrakensangLaunchError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        }
    }
}

/// The Steam ticket and portal cookies exist only for this launch, in memory.
nonisolated final class DrakensangPortal: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static func permits(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
            url.port == nil || url.port == 443,
            let host = url.host?.lowercased()
        else { return false }
        return host == "drakensang.com" || host.hasSuffix(".drakensang.com")
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(Self.permits) == true ? request : nil)
    }

    func launchArguments(ticket: Data) async throws -> [String] {
        guard !ticket.isEmpty, ticket.count <= 4096 else {
            throw DrakensangLaunchError.unavailable("Steam did not return a valid Drakensang sign-in ticket.")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 45
        configuration.httpAdditionalHeaders = [
            "User-Agent":
                "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/538.1 (KHTML, like Gecko) DROThinClient Safari/538.1"
        ]
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (_, response) = try await session.data(from: Self.loginURL(ticket: ticket))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                let finalURL = http.url, Self.permits(finalURL),
                finalURL.host != "steam.partner.drakensang.com",
                var play = URLComponents(url: finalURL, resolvingAgainstBaseURL: false)
            else {
                throw DrakensangLaunchError.unavailable(
                    "Steam sign-in was not accepted. Sign in to Steam and try Play again.")
            }
            play.path = "/pl/play"
            play.query = nil
            play.fragment = nil
            let (data, playResponse) = try await session.data(from: play.url!)
            guard let http = playResponse as? HTTPURLResponse, http.statusCode == 200,
                let url = http.url, Self.permits(url), data.count <= 2_000_000,
                let html = String(data: data, encoding: .utf8)
            else {
                throw DrakensangLaunchError.unavailable("Drakensang did not return its game launch information.")
            }
            return try Self.arguments(in: html)
        } catch let error as DrakensangLaunchError {
            throw error
        } catch {
            // URLSession errors can contain the complete ticket-bearing URL.
            throw DrakensangLaunchError.unavailable(
                "Could not connect to the official Drakensang sign-in service. Check the connection and try Play again."
            )
        }
    }

    static func loginURL(ticket: Data) -> URL {
        var login = URLComponents(string: "https://steam.partner.drakensang.com/")!
        login.queryItems = [
            URLQueryItem(name: "token", value: ticket.base64EncodedString()),
            URLQueryItem(name: "lang", value: "pl_PL"),
        ]
        // The portal uses form-style query decoding, where a bare '+' is a
        // space. URLComponents intentionally permits '+' in RFC 3986 queries.
        login.percentEncodedQuery = login.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return login.url!
    }

    static func arguments(in html: String) throws -> [String] {
        let regex = try NSRegularExpression(
            pattern: #"nebula3\.launch\(\s*(["'])(.*?)\1\s*\)"#, options: .dotMatchesLineSeparators)
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
            let range = Range(match.range(at: 2), in: html)
        else {
            throw DrakensangLaunchError.unavailable(
                "Drakensang's launch information is unavailable. Open the game account once in the official launcher, then try again."
            )
        }
        let arguments = try splitArguments(String(html[range]))
        guard arguments.count < 256, arguments.contains("-sid"),
            let sid = arguments.firstIndex(of: "-sid"), sid + 1 < arguments.count,
            !arguments[sid + 1].isEmpty, arguments.contains("-standalone")
        else {
            throw DrakensangLaunchError.unavailable("Drakensang returned incomplete game launch information.")
        }
        return arguments
    }

    /// Parse the official argv without evaluating any shell or script code.
    static func splitArguments(_ source: String) throws -> [String] {
        var result: [String] = []
        var value = ""
        var quote: Character?
        var escaped = false
        var started = false
        for character in source {
            guard character != "\0", character != "\n", character != "\r" else {
                throw DrakensangLaunchError.unavailable("Drakensang returned invalid game arguments.")
            }
            if escaped {
                value.append(character)
                escaped = false
                started = true
            } else if character == "\\", quote != "'" {
                escaped = true
                started = true
            } else if let active = quote {
                if character == active { quote = nil } else { value.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                started = true
            } else if character.isWhitespace {
                if started {
                    result.append(value)
                    value = ""
                    started = false
                }
            } else {
                value.append(character)
                started = true
            }
        }
        guard quote == nil, !escaped else {
            throw DrakensangLaunchError.unavailable("Drakensang returned unfinished game arguments.")
        }
        if started { result.append(value) }
        return result
    }
}
