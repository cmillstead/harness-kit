# Code Style Rules

Language-specific rules that agents must follow across all projects.

## Python
- NEVER use bare `except:` or `except Exception:` — catch specific exceptions
- NEVER use mutable default arguments (`def foo(items=[])`) — use `None` + conditional
- NEVER use `# type: ignore` to suppress mypy — fix the type
- NEVER use `import *` — use explicit imports
- Prefer `pathlib.Path` over `os.path`
- Prefer f-strings over `.format()` or `%`
- Use `if __name__ == "__main__":` in scripts

## TypeScript / Angular
- NEVER use `subscribe()` in components — use `async` pipe in templates
- NEVER leave observables unsubscribed — use `takeUntilDestroyed()` or `DestroyRef`
- NEVER put business logic in components — move it to services
- NEVER use `any` — use `unknown` if the type is genuinely unknown
- NEVER use default exports — use named exports only
- Prefer `readonly` for properties that shouldn't change
- Prefer `interface` over `type` for object shapes (Angular convention)

## JavaScript
- NEVER use `var` — use `const` by default, `let` when reassignment is needed
- NEVER use `==` — always `===`
- NEVER leave promise rejections unhandled — use `.catch()` or try/catch with await
- Prefer `async`/`await` over `.then()` chains

## HTML
- NEVER use `<div>` for interactive elements — use semantic HTML (`button`, `nav`, `main`, `section`, `article`)
- NEVER omit `alt` on images — use descriptive text or `alt=""` for decorative images
- NEVER use inline styles — use classes
- Use `aria-label` when visual label is absent

## SCSS
- NEVER nest deeper than 3 levels — flatten with BEM or utility classes
- NEVER use `!important` — fix the specificity instead
- NEVER use magic numbers — define variables for spacing, colors, breakpoints
- Use variables for all colors and repeated values
- Use mixins for repeated patterns (media queries, flex layouts)
