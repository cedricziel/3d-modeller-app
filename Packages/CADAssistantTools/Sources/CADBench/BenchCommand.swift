import Foundation

public struct UsageError: Error, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

public struct RunOptions: Sendable, Equatable {
    public var tasksDirectory = "Bench/tasks"
    public var taskIDs: [String]?
    public var repeatCount = 1
    public var model = "claude-opus-5-5"
    public var effort = "medium"
    public var outputDirectory = "Bench/results"
    public var timeoutSeconds = 600
    public var maxToolRounds = 30
    public var useAppKey = false

    public init() {}
}

public enum BenchCommand: Equatable {
    case list(tasksDirectory: String)
    case run(RunOptions)
    case grade(task: String, document: String, tasksDirectory: String)
    case help

    public static let usage = """
        Usage:
          cadbench list [--tasks-dir DIR]
          cadbench run [--tasks ID,…] [--repeat K] [--model M] [--effort E] [--out DIR]
                       [--timeout SECONDS] [--max-rounds N] [--tasks-dir DIR] [--app-key]
          cadbench grade TASK DOCUMENT.cadmodel [--tasks-dir DIR]

        run reads the API key from ANTHROPIC_API_KEY; --app-key falls back to the key saved in the app.
        Defaults: --tasks-dir Bench/tasks, --out Bench/results, --repeat 1, --model claude-opus-5-5,
        --effort medium, --timeout 600, --max-rounds 30.
        """

    public static func parse(_ arguments: [String]) throws(UsageError) -> BenchCommand {
        guard let command = arguments.first else { return .help }
        var rest = Array(arguments.dropFirst())
        var positional: [String] = []
        var options = RunOptions()

        func value(_ flag: String) throws(UsageError) -> String {
            guard !rest.isEmpty else { throw UsageError("\(flag) needs a value") }
            return rest.removeFirst()
        }
        func positive(_ flag: String) throws(UsageError) -> Int {
            let text = try value(flag)
            guard let number = Int(text), number > 0 else {
                throw UsageError("\(flag) needs a positive whole number, not '\(text)'")
            }
            return number
        }

        let runOnly: Set<String> = [
            "--tasks", "--repeat", "--model", "--effort", "--out", "--timeout", "--max-rounds", "--app-key",
        ]
        while !rest.isEmpty {
            let argument = rest.removeFirst()
            if runOnly.contains(argument), command != "run" { throw UsageError("\(argument) only applies to run") }
            switch argument {
            case "--tasks-dir": options.tasksDirectory = try value(argument)
            case "--tasks":
                let ids = try value(argument).split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard !ids.isEmpty else { throw UsageError("--tasks needs at least one task id") }
                options.taskIDs = ids
            case "--repeat": options.repeatCount = try positive(argument)
            case "--model": options.model = try value(argument)
            case "--effort": options.effort = try value(argument)
            case "--out": options.outputDirectory = try value(argument)
            case "--timeout": options.timeoutSeconds = try positive(argument)
            case "--max-rounds": options.maxToolRounds = try positive(argument)
            case "--app-key": options.useAppKey = true
            case "-h", "--help": return .help
            default:
                if argument.hasPrefix("-") { throw UsageError("Unknown option \(argument)") }
                positional.append(argument)
            }
        }

        switch command {
        case "list", "run":
            guard positional.isEmpty else {
                throw UsageError("\(command) takes no arguments, got \(positional.joined(separator: " "))")
            }
            return command == "list" ? .list(tasksDirectory: options.tasksDirectory) : .run(options)
        case "grade":
            guard positional.count == 2 else { throw UsageError("grade needs a task id and a document path") }
            return .grade(task: positional[0], document: positional[1], tasksDirectory: options.tasksDirectory)
        case "help", "-h", "--help":
            return .help
        default:
            throw UsageError("Unknown command '\(command)'")
        }
    }
}
