# Assistant skills

## Goal

Give the modelling assistant skills: folders of guidance it loads when a task needs them, instead of carrying
everything in the system prompt. The first PR moves the task-specific sections of `CADAssistantPrompt.system` into
skills, word for word. Later PRs add recipe skills (and the `batch` tool and pattern features ship with their own
skills; each has its own spec).

Success: `cadbench` pass@k on all tasks stays the same while input tokens drop on tasks that use neither sketches nor
joints.

## Skill format

A skill is a folder, compatible with the Agent Skills format:

```
Skills/
  sketches/
    SKILL.md
    constraints.md      (optional extra files, read on demand)
```

`SKILL.md` starts with a frontmatter block:

```
---
name: sketches
description: Constrained sketches, extrude and revolve. Load before add_sketch, edit_sketch, extrude or revolve.
---
<body>
```

- `name` and `description` are required, one line each. `name` equals the folder name.
- Other keys are ignored. A small parser reads the block; no YAML dependency.
- Scripts in skills are not supported: nothing in a skill is executed.

## SwiftUIAssistant

- `Skill`: `name`, `description`, `body` (the `SKILL.md` text after the frontmatter), `files` (paths of the other
  files in the folder, relative to it, sorted), and the folder URL.
- `SkillLibrary(directory: URL) throws`: loads every subfolder of `directory` as a skill. It throws a `SkillError`
  naming the folder for: a missing `SKILL.md`, missing frontmatter or a missing key, a `name` that differs from the
  folder name, or two skills with the same name. `skills` is sorted by name; `skill(named:)` looks one up;
  `index` is the text for the prompt, one line per skill: `- name: description`.
- `ListSkillsTool(library:)` (`list_skills`, no parameters): the index.
- `GetSkillTool(library:)` (`get_skill`, `name` required, `file` optional):
  - No `file`: the body, then `Files: a.md, b.cadmodel` when the folder has other files.
  - With `file`: that file's text. Refused unless `file` is one of the skill's listed `files` (so `..`, absolute
    paths and unlisted files are refused) and the content is UTF-8.
  - An unknown name is refused with the list of available names.
  - Refusals are tool errors in the same form the CAD tools use, so the model can correct the call.

## CADAssistantTools

- Skills live in `Sources/CADAssistantTools/Resources/Skills/<name>/`, added to the target with
  `.copy("Resources/Skills")` (`.process` would flatten the folders and collide the `SKILL.md` files).
- `CADSkills.library`: the bundled `SkillLibrary`, loaded once from `Bundle.module`. A load failure is a programmer
  error (`fatalError` with the `SkillError`), caught by the tests.
- `CADTools.all(session:)` adds `ListSkillsTool` and `GetSkillTool` over `CADSkills.library`.
- `CADAssistantPrompt.system` becomes the core text plus a Skills section built from `CADSkills.library.index`.

### Prompt split

Moved word for word, so a bench difference comes only from the loading:

| Skill        | From section(s)         | Load before                                   |
| ------------ | ----------------------- | --------------------------------------------- |
| `sketches`   | Sketches                | `add_sketch`, `edit_sketch`, extrude, revolve |
| `assemblies` | Parts and assemblies    | `add_part`, `add_instance`, `edit_instance`   |
| `joints`     | Joints (mating), Motion | `add_joint`, `edit_joint`, `move_joint`       |

Stay in the core prompt: the role, The model, Faces and edges, Working.

New core section:

```
## Skills
Detailed guides for some kinds of work are skills. Before your first write of a kind a skill covers, call
get_skill with its name and follow it; you need not load it again in the same conversation. A skill may list
more files; read one with get_skill(name, file) when the guide points you to it.
<index>
```

If the bench shows the model skipping skills, the next step is a hint in the result of the first write the skill
covers ("load the sketches skill"), not a refusal. That is not part of this PR.

## Testing

- SwiftUIAssistant: frontmatter parsing (keys, extra keys, missing block); `SkillLibrary` over temporary folders,
  one test per error case and one for `files` and sorting; `get_skill` without and with `file`, unknown name,
  unlisted file, `../x`, `/etc/passwd`, non-UTF-8 file; `list_skills` output.
- CADAssistantTools: the bundled library loads with `sketches`, `assemblies` and `joints`; the prompt contains the
  index and none of the moved section headings; `CADTools.all` contains both skill tools; an `AssistantLoopTests`
  run that calls `get_skill("sketches")` and then `add_sketch` completes.
- While moving the sections, check once that the moved text equals the old sections (not kept as a test).
- `cadbench run` on all tasks before and after; pass@k, tool calls, tokens and cost in the PR description.

## Out of scope

- Extra files in the moved skills, and recipe skills (later PRs).
- A user skills folder (the library takes a directory, so adding one later does not change the tools).
- The `batch` tool and linear/circular pattern features (own specs).
