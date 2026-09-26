# cadbench

`cadbench` measures how well an agent models parts through the CAD assistant tools. It gives the model a task
prompt, lets it work through the same tools and system prompt the app uses, with no UI, and grades the document the
model ends with.

A run calls the Claude API and costs money. CI runs only the unit tests; it never runs the benchmark.

## Run it

Run from the repository root, so the default `Bench/tasks` and `Bench/results` paths resolve:

```bash
export ANTHROPIC_API_KEY=…            # or pass --app-key to use the key saved in the app's settings
xcrun swift run --package-path Packages/CADAssistantTools cadbench run
```

The first build compiles Open CASCADE and takes several minutes. Later builds are incremental.

| Command                                 | What it does                                                                                                 |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `cadbench list`                         | Lists the tasks with their kind and prompt.                                                                  |
| `cadbench run`                          | Runs every task once and writes the results.                                                                 |
| `cadbench grade TASK DOCUMENT.cadmodel` | Grades a document against a task's checks, without a model. Exits 0 when every check passes and 1 otherwise. |

Options for `run`:

| Option              | Default           | Meaning                                                                |
| ------------------- | ----------------- | ---------------------------------------------------------------------- |
| `--tasks ID,…`      | all tasks         | Runs only these tasks.                                                 |
| `--repeat K`        | 1                 | Runs each task K times and reports pass@1 and pass@K.                  |
| `--model M`         | `claude-opus-5-5` | The Claude model.                                                      |
| `--effort E`        | `medium`          | The model's effort: `low`, `medium`, `high`, `xhigh` or `max`.         |
| `--timeout SECONDS` | 600               | Ends a run that takes longer. The document it reached is still graded. |
| `--max-rounds N`    | 30                | The most tool rounds per run.                                          |
| `--out DIR`         | `Bench/results`   | Where the timestamped result folder goes.                              |
| `--tasks-dir DIR`   | `Bench/tasks`     | Where the tasks are. `list` and `grade` take it too.                   |
| `--app-key`         | off               | If `ANTHROPIC_API_KEY` is not set, uses the key saved in the app.      |

`cadbench` never prints the key or writes it to a file. It replaces any occurrence of the key in the results with
`[redacted]`.

## Results

Each run writes a folder `Bench/results/<timestamp>/`, which Git ignores:

```
summary.md                 table per task: passes, pass@1, pass@K, tool calls, tokens, cost, time; failed checks
summary.json               the same data, plus every check outcome of every run
<task>/run-<n>/
  document.cadmodel        the final document; open it in the app
  listing.txt              the final listing, as the model saw it
  transcript.json          every message, tool call, tool result and per-turn context (image captions only)
  run.json                 how the run ended, check outcomes, usage and cost
  view-<name>.png          the final model rendered iso, top, front and right, as render_views returns it
```

A run passes when its final document passes every check. How the run ended (`completed`, `maxToolRounds`,
`timedOut` or `failed`) is recorded next to the verdict. The cost is an estimate from input and output tokens at the
model's list price. Put `summary.md` in the pull request description.

## Tasks

Each task is a folder `Bench/tasks/<id>/`:

- `task.json` — the kind, the prompt and the checks.
- `seed.cadmodel` — the starting document. Modify tasks need one; build tasks start from an empty document and must
  not have one.
- `reference.cadmodel` — a correct solution. The `referenceIoU` check needs it, and the tests grade it.

```json
{
  "kind": "modify",
  "prompt": "Move the hole 20 mm in the +X direction so that its centre is at x = 60 mm, y = 25 mm. …",
  "checks": [
    { "type": "gate" },
    { "type": "bodyCount", "equals": 1 },
    { "type": "volume", "expected": 23528.761, "tolerance": 0.002 },
    { "type": "referenceIoU", "threshold": 0.995 },
    { "type": "unchangedExcept", "features": ["Hole"] }
  ]
}
```

Lengths are millimetres. A task file with an unknown key, or a check with an unknown key, is refused when it loads.

| Check             | Keys (default)                                                                                            | Passes when                                                                                                                                                                 |
| ----------------- | --------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `gate`            | none                                                                                                      | Every feature rebuilds (none failed or skipped), there is at least one body, and every body is one valid closed solid.                                                      |
| `bodyCount`       | `equals`                                                                                                  | The document has exactly that many bodies.                                                                                                                                  |
| `boundingBox`     | `part`, `body`, `min`, `max`, `size` (each `[x, y, z]`, at least one), `tolerance` (0.01 mm)              | The bounds of the selected bodies are within the tolerance, per component.                                                                                                  |
| `volume`          | `part`, `body`, `expected`, `tolerance` (0.005, relative)                                                 | The total volume of the selected bodies is within the tolerance.                                                                                                            |
| `parameter`       | `name`, `value`, `tolerance` (1e-6)                                                                       | The parameter exists and evaluates to the value.                                                                                                                            |
| `featureCount`    | `feature` (`box`, `cylinder`, `sphere`, `cone`, `torus`, `boolean`, `transform`, `fillet`, `chamfer`, `shell`), `equals` or `min`/`max` | The number of unsuppressed features of that type is within the bounds.                                                                                                      |
| `referenceIoU`    | `threshold`                                                                                               | The volume shared with the reference, divided by the combined volume, is at least the threshold.                                                                            |
| `unchangedExcept` | `features` ([]), `parameters` ([]), `allowNewFeatures` (false)                                            | Compared with the seed, only the named features and parameters changed. New parameters are always allowed; new features only when named or when `allowNewFeatures` is true. |

Without `part` and `body`, `boundingBox` and `volume` use every body. A `body` name that exists in several parts
fails the check; add `part`.

### Add a task

1. Create the folder and write `task.json`. State every dimension and position in the prompt. The checks test
   absolute positions, so say where the part sits, for example "one corner at the origin" or "axis on Z, bottom face
   at z = 0".
2. Write `reference.cadmodel`, by hand or by building it in the app, and `seed.cadmodel` for a modify task.
3. Check the reference passes:

   ```bash
   xcrun swift run --package-path Packages/CADAssistantTools cadbench grade <id> Bench/tasks/<id>/reference.cadmodel
   ```

4. Add the id to `TaskGradingTests.ids` and add a wrong solution to `WrongSolution` in
   `Packages/CADAssistantTools/Tests/CADBenchTests/TaskGradingTests.swift` to prove that the checks catch a plausible
   mistake. Run `cd Packages/CADAssistantTools && xcrun swift test --filter TaskGradingTests`.

Each later layer of the CAD stack adds tasks for what it enables.

### Current tasks

| Task                | Kind   | What it exercises                                                        |
| ------------------- | ------ | ------------------------------------------------------------------------ |
| `plate-hole`        | build  | A box with a through hole cut by a cylinder.                             |
| `washer`            | build  | A ring from two cylinders.                                               |
| `flanged-shaft`     | build  | Two cylinders joined into one body.                                      |
| `block-pocket`      | build  | A blind rectangular pocket.                                              |
| `l-bracket`         | build  | Two plates joined at an edge.                                            |
| `hemisphere`        | build  | A sphere intersected with a box.                                         |
| `rounded-plate`     | build  | A plate with its vertical corner edges filleted, by an edge filter.      |
| `open-box`          | build  | A box shelled open at the top face, by a face name.                      |
| `plate-thickness`   | modify | Changing a parameter.                                                    |
| `plate-move-hole`   | modify | Moving an existing feature.                                              |
| `plate-second-hole` | modify | Adding a feature that reuses a parameter.                                |
| `chamfered-hole`    | modify | Chamfering one named circular edge, the hole's top rim, not the bottom. |
