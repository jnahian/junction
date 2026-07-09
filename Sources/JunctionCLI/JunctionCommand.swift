import ArgumentParser
import Foundation
import JunctionCore

#if canImport(AppKit)
import AppKit
import JunctionMacKit
#endif

@main
struct JunctionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "junction",
        abstract: "Rule-based link router — CLI companion to Junction.app.",
        subcommands: [Open.self, Test.self, ConfigCommand.self]
    )
}

private func loadEngine(configPath: String?) throws -> RoutingEngine {
    let url = configPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        ?? ConfigStore.defaultURL()
    let config: Config
    if FileManager.default.fileExists(atPath: url.path) {
        config = try ConfigStore.load(from: url)
    } else {
        config = Config()
    }
    #if canImport(AppKit)
    return RoutingEngine(config: config, isSchemeHandled: { BrowserDiscovery.isSchemeHandled($0) })
    #else
    return RoutingEngine(config: config)
    #endif
}

private func parseURL(_ s: String) throws -> URL {
    guard let url = URL(string: s), url.host != nil, let scheme = url.scheme,
          ["http", "https"].contains(scheme.lowercased()) else {
        throw ValidationError("\"\(s)\" is not a valid http(s) URL")
    }
    return url
}

// MARK: junction test (F8)

struct Test: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Dry-run a URL through the rule engine and print what would happen."
    )

    @Argument(help: "The URL to test.")
    var url: String

    @Option(name: .customLong("source"), help: "Simulated source app bundle ID (e.g. com.tinyspeck.slackmacgap).")
    var sourceApp: String?

    @Option(help: "Path to a config file (defaults to ~/.config/junction/config.json).")
    var config: String?

    func run() throws {
        let engine = try loadEngine(configPath: config)
        let event = LinkEvent(url: try parseURL(url), sourceApp: sourceApp)
        let trace = engine.trace(event)

        print("input:       \(event.url.absoluteString)")
        if let source = sourceApp { print("source:      \(source)") }
        if trace.transformedURL != event.url {
            print("transformed: \(trace.transformedURL.absoluteString)")
        }
        if let rule = trace.matchedRule {
            print("rule:        [\(trace.matchedRuleIndex.map { String($0 + 1) } ?? "?")] \(rule)")
        } else if let rewriter = trace.rewriterID {
            print("rule:        (built-in rewriter: \(rewriter))")
        } else {
            print("rule:        none")
        }
        switch trace.decision {
        case .open(let app, let profile, let url):
            print("action:      open in \(app)\(profile.map { " --profile-directory=\"\($0)\"" } ?? "")")
            print("url:         \(url.absoluteString)")
        case .deepLink(let url, let id, _):
            print("action:      deep link (\(id))")
            print("url:         \(url.absoluteString)")
        case .prompt(let url):
            print("action:      show picker")
            print("url:         \(url.absoluteString)")
        case .clipboard(let url):
            print("action:      copy to clipboard")
            print("url:         \(url.absoluteString)")
        case .fallback(let app, let url):
            print("action:      fallback → \(app)")
            print("url:         \(url.absoluteString)")
        }
    }
}

// MARK: junction open (F10)

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Route a URL through the engine and actually open it."
    )

    @Argument(help: "The URL to open.")
    var url: String

    @Option(name: .customLong("source"), help: "Simulated source app bundle ID.")
    var sourceApp: String?

    @Option(help: "Path to a config file.")
    var config: String?

    func run() throws {
        #if canImport(AppKit)
        let engine = try loadEngine(configPath: config)
        let event = LinkEvent(url: try parseURL(url), sourceApp: sourceApp)
        var decision = engine.route(event)

        // The picker needs Junction.app's UI; from the CLI, degrade to the fallback browser.
        if case .prompt(let promptURL) = decision {
            print("note: picker rules fall back to the default browser when run from the CLI")
            decision = .fallback(app: engine.config.fallback.app, url: promptURL)
        }
        if case .clipboard = decision {
            print("copied to clipboard")
        }

        let dispatcher = Dispatcher(fallbackApp: engine.config.fallback.app)
        let semaphore = DispatchSemaphore(value: 0)
        dispatcher.dispatch(decision) { outcome in
            if case .failed(let message) = outcome {
                FileHandle.standardError.write(Data("junction: failed to open: \(message)\n".utf8))
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        #else
        throw ValidationError("junction open requires macOS")
        #endif
    }
}

// MARK: junction config (F10)

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Config-file tooling for dotfiles setups.",
        subcommands: [Path.self, Validate.self]
    )

    struct Path: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the config file path.")
        func run() {
            print(ConfigStore.defaultURL().path)
        }
    }

    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Validate the config file and explain any problems.")

        @Option(help: "Path to a config file (defaults to ~/.config/junction/config.json).")
        var config: String?

        func run() throws {
            let url = config.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                ?? ConfigStore.defaultURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("no config file at \(url.path) — Junction will use defaults")
                return
            }
            do {
                let loaded = try ConfigStore.load(from: url)
                print("✓ valid — \(loaded.rules.count) rule(s), fallback \(loaded.fallback.app)")
            } catch let error as ConfigError {
                print("✗ \(error.description)")
                throw ExitCode(1)
            }
        }
    }
}
