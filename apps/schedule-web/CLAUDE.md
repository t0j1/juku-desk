# Project Development Rules

## 1. Plan First

For any non-trivial task involving:
- 3 or more steps
- database changes
- architecture changes
- authentication
- API changes
- UI restructuring

Create or update `tasks/todo.md` before implementation.

For simple changes such as:
- typo fixes
- small CSS changes
- simple text changes

planning is optional.

---

## 2. Understand Before Changing

Before modifying existing code:

1. Find the relevant files.
2. Read the surrounding implementation.
3. Understand existing patterns.
4. Avoid rewriting code unnecessarily.

Do not create a new abstraction when an existing one can be reused.

---

## 3. Minimal Changes

Prefer the smallest change that solves the problem.

Do not:
- refactor unrelated code
- rename unrelated variables
- change architecture unnecessarily
- introduce new dependencies without justification

---

## 4. Verification

Never consider a task complete without verification.

After implementation:

1. Run relevant tests.
2. Check for errors.
3. Check affected UI/API behavior.
4. Review the diff.
5. Fix failures before reporting completion.

If verification cannot be performed, clearly state what was not verified.

---

## 5. Bug Fixing

When a bug is reported:

1. Reproduce the problem.
2. Identify the root cause.
3. Fix the root cause.
4. Add or update a regression test when appropriate.
5. Run the relevant tests.

Do not apply temporary workarounds unless explicitly requested.

---

## 6. Database Safety

Before database changes:

- Check existing schema.
- Check migrations.
- Consider existing production data.
- Do not destroy or reset data unless explicitly instructed.

---

## 7. Security

Never expose:
- API keys
- passwords
- authentication tokens
- `.env` secrets

Do not commit secrets to Git.

---

## 8. Task Tracking

Use:

`tasks/todo.md`

for current work.

Use:

`tasks/lessons.md`

for recurring mistakes and project-specific lessons.

---

## 9. Code Quality

Prefer:

- simple solutions
- readable code
- existing project conventions
- small changes
- explicit behavior

Avoid over-engineering.

Before implementing a complex solution, ask:

"Is there a simpler solution using the existing architecture?"

---

## 10. Communication

Before major implementation, explain the planned approach briefly.

After implementation, report:

- What changed
- Why
- Tests/verification performed
- Remaining issues
