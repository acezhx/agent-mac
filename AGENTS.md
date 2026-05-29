# Agent Development Standards

This file defines language-agnostic and project-agnostic development standards for coding agents.
It is not a product requirements document and must not encode business rules, product modules,
specific API inventories, schema inventories, deployment topology, or roadmap commitments.

Project-specific architecture, product decisions, and operational details should live in the
project's own documentation. Code should follow the current project documents and the existing
implementation. When this standard conflicts with a project document, use this file for development
process and engineering discipline, and use the project document for product and architecture facts.

## Core Operating Rule

Before changing anything, understand the request, inspect the relevant files, state assumptions when
needed, make the smallest correct change, and verify the result.

Every changed line should be traceable to the user request or to cleanup directly required by that
change.

## Think Before Coding

Do not assume. Do not hide confusion. Surface tradeoffs.

Before implementing:

- State assumptions explicitly when they affect the solution.
- If multiple interpretations exist, present them instead of silently choosing.
- If a simpler approach exists, say so and prefer it unless there is a concrete reason not to.
- If something is unclear enough to change the implementation, stop and ask.

## Simplicity First

Write the minimum code that solves the problem. Nothing speculative.

- Do not add features beyond what was requested.
- Do not add abstractions for single-use code.
- Do not add flexibility or configurability that was not requested.
- Do not add defensive handling for scenarios that cannot happen in the current design.
- If a solution becomes much larger than necessary, simplify it before moving on.

Ask: would a senior engineer consider this overcomplicated? If yes, reduce it.

## Surgical Changes

Touch only what must be touched. Clean up only the mess created by the current change.

When editing existing code:

- Do not improve adjacent code, comments, naming, or formatting unless required.
- Do not refactor unrelated code.
- Match the existing style, even when another style would be personally preferred.
- If unrelated dead code or design debt is noticed, mention it instead of deleting it.

When the current change creates unused imports, variables, functions, files, or tests, remove those
orphans. Do not remove pre-existing dead code unless asked.

## Goal-Driven Execution

Define success criteria and loop until verified.

Convert vague tasks into verifiable goals:

- "Add validation" means add or update checks for invalid inputs and verify they work.
- "Fix a bug" means reproduce the bug when practical, then prove the fix.
- "Refactor" means preserve behavior and run the relevant tests before finishing.

For multi-step work, use a short plan:

```text
1. [Step] -> verify: [check]
2. [Step] -> verify: [check]
3. [Step] -> verify: [check]
```

Weak criteria such as "make it work" are not enough for non-trivial work.

## Standard Workflow

Use this sequence for normal implementation tasks:

1. Inspect context: read the relevant docs, source files, tests, and available project scripts.
2. Identify scope: decide which files must change and which files should remain untouched.
3. Define verification: choose the smallest meaningful test, type check, lint, build, or manual
   check.
4. Prepare module artifacts: identify or create the module development document and test location
   for the changed module when the project requires them.
5. Implement: make focused edits that follow local patterns.
6. Verify: run the selected checks. If a check cannot be run, explain why.
7. Summarize: report what changed, what was verified, and any remaining risk.

For reviews, lead with findings ordered by severity. Include file and line references. If there are
no findings, say that clearly and mention any test gaps.

## Project-Scoped Skills

This repository may include project-scoped Codex skills under `.codex/skills`.
When a user request matches a skill folder name or the `description` in a skill's `SKILL.md`, read
that `SKILL.md` before implementation and load referenced files only as needed. If the runtime's
global skills list does not include these project-scoped skills, use this section as the discovery
mechanism.

## Project Documents

Before implementing project features, read the relevant project documents:

- `doc/project-goals-and-standards.md` for product goals, scope, and constraints.
- `doc/technical-design.md` for architecture, module boundaries, and dependencies.
- `doc/development-plan.md` for implementation order and milestones.
- `doc/schemas-and-file-formats.md` before changing Agent, tool, settings, or resource file formats.
- `doc/runtime-protocol.md` before changing Swift-to-Node Runtime Host communication.
- `doc/runtime-packaging.md` before changing embedded Node/Pi packaging or runtime paths.
- `doc/testing-strategy.md` before adding or changing verification flows.
- `doc/module-plans/<module>.md` before implementing or changing a specific module.

## Module Development

Every module that receives functional changes should have appropriate development documentation and
tests, unless the project explicitly uses another standard.

For each module:

- Maintain module documentation that explains purpose, boundaries, public contracts, important
  flows, dependencies, configuration, and verification method.
- Keep documentation where the project convention says it belongs.
- Add or update tests for new behavior, changed behavior, bug fixes, and meaningful edge cases.
- Keep tests focused on observable behavior, not private implementation details.
- Do not mark a module-level feature complete until documentation and tests are present, or until a
  reason for an exception is explicitly recorded.

When a feature spans multiple modules, update documentation and tests for each affected module.
Shared integration behavior may also need integration tests, but integration tests do not replace
module-level tests.

## Scope Control

Keep agent standards limited to engineering process and collaboration discipline.

Do not add:

- Business-specific terminology or business module definitions.
- Concrete product feature lists.
- Concrete API endpoint inventories.
- Concrete database table inventories.
- Concrete deployment service inventories.
- Roadmap commitments.
- Architecture diagrams that belong in project documentation.

When business or architecture decisions change, update the project document that owns the decision
instead of encoding the decision in agent operating standards.

## Code Standards

Prefer existing project conventions over new personal preferences.

- Keep modules cohesive and dependencies directional.
- Avoid circular dependencies.
- Keep public interfaces small and explicit.
- Prefer explicit contracts over loosely shaped data.
- Validate external input at system boundaries.
- Keep side effects isolated behind clear interfaces.
- Keep configuration outside code and validate required configuration at startup.
- Never commit secrets, credentials, tokens, private keys, or local machine paths that are not
  intended for the repository.
- Use structured errors and logs where the project already has patterns for them.
- Avoid broad catch blocks that hide failures.
- Avoid global mutable state unless the existing architecture requires it.
- Do not introduce a new dependency without a concrete need and a clear reason.

### SwiftUI Perception Standards

When editing SwiftUI views backed by TCA perceptible state in this repository:

- Read `doc/module-plans/appshell.md` before changing AppShell SwiftUI views.
- Wrap every view body that reads a perceptible `StoreOf<...>` state with
  `WithPerceptionTracking`.
- Re-wrap extracted computed subviews and escaping ViewBuilder closures that read store state,
  including `ForEach`, `List` rows, `GeometryReader`, `ScrollViewReader`, `sheet`, `popover`,
  `alert`, `confirmationDialog`, `toolbar`, `overlay`, and `background`.
- Treat computed state such as `hasOperationInFlight`, `canSave...`, and `canCreate...` as state
  reads; they also require perception tracking.
- Prefer passing plain values into reusable rows and leaf views instead of giving display-only
  subviews direct store access.
- Use `@Perception.Bindable` and `$store.field.sending(\.action)` for bindings derived from
  perceptible state.
- Ensure every `Picker` selection always has a matching `.tag(...)`, including empty, loading, or
  unavailable selections. Keep empty placeholder tags stable when reducers may temporarily clear
  selection during loading or entity switching.

## Comment Standards

Code comments are part of maintainability and must be kept current.

- Follow the repository's language, style, and documentation conventions for comments.
- In this repository, write code documentation comments in Chinese.
- Add standard documentation comments for classes, structs, enums, properties, initializers, and
  methods when adding or changing them.
- Documentation comments should describe the API's purpose, caller-facing contract, parameters,
  return value, thrown errors, persistence behavior, ownership boundary, side effects, and
  non-obvious ordering or validation rules when those details apply.
- Document exported types, public functions, public classes, service classes, repository classes,
  validation helpers, mapper functions, schema helpers, and other module-boundary APIs when their
  caller-facing contract is not obvious from the signature alone.
- Comments should explain purpose, caller-facing contract, ownership boundary, side effects,
  persistence behavior, validation responsibility, transaction constraints, or non-obvious ordering
  rules.
- Add inline comments only for non-obvious implementation decisions.
- Do not add comments that merely repeat the code, restate a name, or narrate obvious control flow.
- Keep test comments minimal unless the test setup or assertion is non-obvious.
- When code behavior, public contracts, persistence semantics, or module boundaries change, update
  nearby comments in the same change.

## Testing And Verification

Tests should match the risk and blast radius of the change.

- For bug fixes, prefer a regression test when practical.
- For module feature work, add or update tests before considering the module complete.
- For shared logic, cover edge cases and failure paths.
- For API or integration behavior, verify request/response contracts where practical.
- For schema or migration changes, verify migration and rollback expectations if the project
  supports rollback.
- For UI changes, verify the relevant viewport or interaction when a frontend exists.
- For documentation-only changes, check consistency with linked documents and terminology.

After functional work is complete, run the relevant unit tests and at least one broader project check
when available, such as type check, lint, build, or integration tests. Run the narrowest meaningful
checks first. Broaden verification when touching shared infrastructure, public contracts,
persistence, runtime behavior, or cross-module boundaries.

If tests or checks cannot be run because the project is not scaffolded, dependencies are missing, or
the environment is unavailable, state the blocker clearly in the final response.

## Documentation Standards

Documentation changes should be made in the document that owns the decision.

- Keep durable product and architecture decisions in project documentation.
- Keep module development documents updated when module behavior, boundaries, contracts,
  dependencies, or verification steps change.
- Keep implementation notes near the code only when they help future maintainers understand
  non-obvious behavior.
- Keep comments useful, accurate, and focused on code purpose and non-obvious design intent.
- Do not duplicate the same decision across many files unless each copy serves a clear purpose.
- When a code change invalidates documentation, update the documentation in the same change.

## Editing Discipline

Respect the existing working tree.

- Do not revert user changes unless explicitly asked.
- Do not run destructive commands unless explicitly asked and confirmed.
- Do not reformat unrelated files.
- Do not move files or rename public APIs unless required.
- Do not mix unrelated cleanup with feature work.
- Use the repository's existing tools and scripts when available.

When editing manually, prefer precise patches. Large rewrites are acceptable only when the requested
change is itself a rewrite or when smaller edits would be less clear and more error-prone.

## Completion Checklist

Before final response, confirm:

- The requested change is complete.
- The scope did not expand silently.
- Each functionally changed module has current documentation when the project requires it.
- Each functionally changed module has relevant tests, or a documented reason why not.
- Relevant tests or checks were run, or the reason they were not run is clear.
- Documentation was updated if behavior, architecture, or public contracts changed.
- The final response names the changed files and verification performed.
