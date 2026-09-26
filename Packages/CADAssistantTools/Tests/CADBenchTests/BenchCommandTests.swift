import Testing

@testable import CADBench

@Suite("Command line")
struct BenchCommandTests {
    @Test("Commands parse with defaults and options")
    func parses() throws {
        #expect(try BenchCommand.parse([]) == .help)
        #expect(try BenchCommand.parse(["list"]) == .list(tasksDirectory: "Bench/tasks"))
        #expect(
            try BenchCommand.parse(["grade", "washer", "out.cadmodel", "--tasks-dir", "T"])
                == .grade(task: "washer", document: "out.cadmodel", tasksDirectory: "T"))
        #expect(try BenchCommand.parse(["run"]) == .run(RunOptions()))
        var options = RunOptions()
        options.taskIDs = ["washer", "plate-hole"]
        options.repeatCount = 3
        options.model = "claude-sonnet-5"
        options.effort = "high"
        options.outputDirectory = "/tmp/out"
        options.timeoutSeconds = 120
        options.maxToolRounds = 12
        options.useAppKey = true
        #expect(
            try BenchCommand.parse([
                "run", "--tasks", "washer,plate-hole", "--repeat", "3", "--model", "claude-sonnet-5", "--effort",
                "high", "--out", "/tmp/out", "--timeout", "120", "--max-rounds", "12", "--app-key",
            ]) == .run(options))
    }

    @Test(
        "Bad arguments are refused",
        arguments: [
            ["bench"], ["run", "--repeat"], ["run", "--repeat", "0"], ["run", "--repeat", "x"],
            ["run", "--colour", "red"], ["grade", "washer"], ["list", "extra"], ["run", "--tasks", ""],
            ["list", "--repeat", "2"],
        ])
    func refusals(arguments: [String]) {
        #expect(throws: UsageError.self) { try BenchCommand.parse(arguments) }
    }

    @Test("The environment key wins; the app key is used only when asked for; a missing key is refused")
    func keyResolution() throws {
        #expect(
            try APIKey.resolve(environment: ["ANTHROPIC_API_KEY": "env-key"], useAppKey: true, savedInApp: { "app" })
                == "env-key")
        #expect(try APIKey.resolve(environment: [:], useAppKey: true, savedInApp: { "app-key" }) == "app-key")
        #expect(throws: UsageError.self) {
            try APIKey.resolve(environment: [:], useAppKey: false, savedInApp: { "app-key" })
        }
        #expect(throws: UsageError.self) {
            try APIKey.resolve(environment: ["ANTHROPIC_API_KEY": " "], useAppKey: true, savedInApp: { nil })
        }
    }
}
