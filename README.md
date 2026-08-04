# NeoNotes

Markdown notes in your macOS menu bar — always one click away.

<img alt="NeoNotes" src="preview.png" height="500" />

## Features

- **Menu bar native** — lives in your menu bar, no dock icon
- **Plain markdown files** — notes are just `.md` files in a folder you choose
- **Live syntax highlighting** — headings, bold/italic, code, quotes, links
- **Preview mode** — rendered markdown with clickable checkboxes
- **Tasks** — `- [ ]` checkboxes, toggle by clicking in editor or preview
- **List autocomplete** — Return continues bullets, numbered lists, and tasks
- **Auto-sync** — external file changes are picked up automatically
- **Note colors, resizable panel, launch at login**

## Install

Build from source (requires Xcode 15+ / macOS 14+):

```sh
git clone https://github.com/lodev09/neonotes.git
cd neonotes
open NeoNotes.xcodeproj
```

Then build and run the `NeoNotes` scheme.

The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) — after changing `project.yml`, run `xcodegen`.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘N | New note |
| ⌘E | Toggle preview |
| ⌘[ / ⌘] | Previous / next note |
| ⌘, | Settings |

## Notes Storage

Notes are stored as plain markdown files — by default inside the app's sandbox container (`~/Library/Containers/com.lodev09.NeoNotes/Data/Library/Application Support/NeoNotes/Notes`), or any folder you pick in Settings (e.g. `~/Documents/Notes`). Existing `.md` files in the chosen folder are loaded automatically.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)

---

Made with ❤️ by [@lodev09](http://linkedin.com/in/lodev09/)
