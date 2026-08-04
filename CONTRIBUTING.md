# Contributing to NeoNotes

Thanks for your interest in contributing!

## Setup

1. Fork and clone the repo
2. Open `NeoNotes.xcodeproj` in Xcode 15+
3. Build and run the `NeoNotes` scheme

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen). If you change `project.yml` (or prefer regenerating after adding files), run:

```sh
xcodegen
```

## Project Structure

```
NeoNotes/
├── Models/        # Note model, NoteStore (persistence, file watching)
├── Views/         # SwiftUI views (panel, editor, preview, settings, about)
├── Support/       # Markdown syntax/highlighting, shared helpers
└── Assets.xcassets
```

## Guidelines

- Keep it simple — this is a small, focused app; avoid over-engineering
- Follow the existing code style and conventions
- Notes are plain `.md` files; don't introduce proprietary formats
- No new dependencies without prior discussion in an issue
- Test your changes manually before submitting (editor, preview, settings)

## Pull Requests

1. Create a branch: `feat/short-description` or `fix/short-description`
2. Keep commits and PRs small and focused
3. Describe what changed and why in the PR body

## Bugs & Ideas

Open an [issue](https://github.com/lodev09/neonotes/issues) with steps to reproduce (for bugs) or a short rationale (for features).
