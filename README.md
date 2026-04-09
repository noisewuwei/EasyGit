# EasyGit

EasyGit is a Flutter desktop Git client focused on daily workflows: inspect status, review history, stage changes, resolve conflicts, and complete commits without leaving a single UI.

## Current Capabilities

- Repository launcher with local repo management and remote clone support.
- Multi-window desktop mode: opening a repo creates a dedicated sub-window.
- History-first workspace with commit search and commit detail viewer (`git show --stat --patch`).
- Commit overlay with staged/unstaged columns, file diff preview, hunk-level actions, and commit panel.
- Branch, remote branch, tag, and submodule navigation from the sidebar.
- Common Git operations from toolbar and context menus (fetch/pull/push/merge/rebase/reset/cherry-pick/revert/stash/tag).
- Conflict-aware workflow: detect conflicts, compare ours/theirs/base, and resolve with one-click actions.
- Settings dialog for remotes, Git user info, proxy config, auto refresh, and refresh interval.
- UTF-8 Git command execution for proper Chinese/emoji output.

## Requirements

- Flutter SDK available in PATH.
- Git installed and available in PATH.
- Desktop target enabled for your platform:
	- Windows
	- macOS
	- Linux

## Quick Start

1. Install dependencies:

```powershell
flutter pub get
```

2. Run the app:

```powershell
# Windows
flutter run -d windows

# macOS
flutter run -d macos

# Linux
flutter run -d linux
```

3. On the home screen:
	 - Add a local repository, or
	 - Clone a remote repository into a selected parent directory.

4. Open a repository window and start in history mode.

5. Click Commit in the toolbar to switch into commit overlay mode.

## Main UI Workflow

### 1) History Mode (default)

- View recent commits with infinite loading.
- Search commits by message, author, or hash.
- Select a commit to view patch/stat details.
- Use commit context menu for:
	- Revert
	- Cherry-pick
	- Reset (soft/mixed/hard)
	- Rebase current branch onto selected commit

### 2) Commit Overlay Mode

- Left: unstaged files
- Middle: staged files
- Right: diff preview
- Bottom: commit message editor

Supported actions:

- Stage/unstage single file or all files.
- Restore unstaged file changes.
- Open hunk dialog to stage/unstage/discard at hunk level.
- Commit staged changes.
- Generate commit message with AI (Deepseek).

## Sidebar Features

- Local branches:
	- Select branch to load history
	- Double-click to checkout
	- Context menu for push/merge/delete
	- Ahead/behind badges for pull/push counts

- Remote branches:
	- Lazy-loaded by selected remote
	- Double-click to checkout tracking branch

- Tags:
	- Select to browse history on tag ref
	- Double-click to checkout tag (detached HEAD)
	- Context menu:
		- Push tag
		- Delete local tag
		- Delete remote tag
		- Generate changelog from selected tag to HEAD

- Submodules:
	- List submodule path/commit/init state
	- Double-click to open submodule in a new repo page
	- Update all submodules action

## Toolbar and More Actions

- Direct actions: Fetch, Pull, Push, Commit toggle, Settings, Open Remote URL, Open Shell, Refresh.
- More menu:
	- Amend last commit
	- Stash save
	- Stash list/apply/pop/drop/clear
	- Rebase onto branch
	- Rebase continue/skip/abort

## AI Commit Message (Deepseek)

EasyGit can generate a commit message from current diffs.

Set API key in one of these locations:

1. Environment variable `DEEPSEEK_API_KEY`
2. `.env` file in the opened repository root
3. Fallback `.env` in current process working directory

Example `.env`:

```env
DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxx
```

## Settings

The Settings dialog currently supports:

- Remotes: add/edit/remove remote URL.
- Git user info:
	- Use global user.name/user.email
	- Or override with local repo config
- Git proxy:
	- Enable/disable proxy
	- Set both `http.proxy` and `https.proxy`
	- Choose global or local scope
- Auto refresh:
	- Enable/disable periodic refresh
	- Adjustable interval (5s to 60s)

## Project Structure

- `lib/main.dart`: app entry, repository launcher, desktop window bootstrap.
- `lib/repo_page.dart`: main repository workspace and Git operation orchestration.
- `lib/git_service.dart`: Git CLI wrapper and parsing logic.
- `lib/widgets/repo_sidebar.dart`: branches/remotes/tags/submodules panel.
- `lib/widgets/commit_history.dart`: commit list, search, detail view.
- `lib/widgets/changes_and_diff.dart`: staged/unstaged lists and diff preview.
- `lib/widgets/commit_panel.dart`: commit editor and AI generation trigger.
- `lib/widgets/repo_toolbar.dart`: top action bar.
- `lib/ui/`: theme, colors, diff highlighting, desktop window controls.

## Development Commands

```powershell
flutter pub get
flutter analyze
flutter test

flutter run -d windows
flutter run -d macos
flutter run -d linux

flutter build windows
flutter build macos
flutter build linux
```

## Notes

- This project is desktop-focused and optimized for daily Git operations.
- Current automated test coverage is minimal.

Issues and pull requests are welcome.
