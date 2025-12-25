# EasyGit

EasyGit is a lightweight Flutter desktop client focused on the daily Git workflow: inspect repo state, stage files, review diffs, and craft commits without leaving a polished UI.

## Highlights
- **Repository overview** – sidebar lists local branches/remotes with quick checkout/switch actions.
- **History-first layout** – landing view shows recent commits; selecting one opens a detail pane with `git show` output (stat + patch).
- **Commit workflow overlay** – tapping `Add` opens the staging+diff workspace with staged/unstaged columns, inline diff preview, commit message panel, and live git output log.
- **Custom desktop chrome** – GitHub-dark theme, draggable title bar, and native window buttons for macOS/Windows/Linux (via `window_manager`).
- **UTF-8 aware Git service** – every git command decodes stdout/stderr properly, so Chinese/emoji commit messages render correctly.

## Getting Started
1. Ensure Flutter is installed and `flutter doctor` passes for your platform.
2. Clone this repo and open it in VS Code or your preferred IDE.
3. Run `flutter pub get` to install dependencies.
4. Launch the desktop app:
	```powershell
	flutter run -d windows   # macOS: -d macos, Linux: -d linux
	```
5. When prompted, select (or hardcode) a repository path. The Repo Page will display commit history by default; hit `Add` to enter the staging/commit workspace.

## Project Structure
- `lib/repo_page.dart` – primary UI: branch/remote sidebar, commit history/detail view, staging panels, diff viewer, commit form, and log console.
- `lib/git_service.dart` – thin wrapper around Git CLI commands (`status`, `diff`, `log`, `show`, etc.).
- `lib/ui/` – shared theming, colors, and custom window controls.

## Roadmap
- Drag-and-drop staging.
- Inline file diff search and navigation.
- Multi-repo workspace view.

## AI
- Use AI to generate commit message need a local file named .env in root path.
- 'DEEPSEEK_API_KEY=sk-xxxxxxxxxxx' is needed in .env file

Feel free to fork and adapt EasyGit to your workflow. Issues/PRs welcome!
