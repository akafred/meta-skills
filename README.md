# meta-skills

Agent skills live scattered across many separate repos — your own and third parties'. **meta-skills** is one place to clone, update, and search them all, then symlink the ones you want into any project — working across Claude Code, Copilot CLI, OpenCode, and Codex, with each source repo staying authoritative.

Because skills are symlinked in rather than copied, it's easy to try them out and develop them across several projects at once: edit a skill in one place and every project that links it picks up the change immediately. To share your skills with other people, though, install them the conventional way — the symlinks are for your own local use, not for distribution.

## Referenced skill repositories

| Folder | Source |
| --- | --- |
| `addyosmani-agent-skills` | `https://github.com/addyosmani/agent-skills.git` |
| `akafred-code-design-review` | `git@github.com:akafred/code-design-review.git` |
| `akafred-prezzie` | `git@github.com:akafred/prezzie.git` |
| `akafred-skills` | `git@github.com:akafred/skills.git` |
| `kjetiljd-skills` | `https://github.com/kjetiljd/skills.git` |
| `mattpocock-skills` | `https://github.com/mattpocock/skills.git` |
| `obra-superpowers` | `https://github.com/obra/superpowers.git` |

## Clone everything

Clone the meta-repo and all referenced skill repos in one step (requires `meta`):

```bash
meta git clone git@github.com:akafred/meta-skills.git
```

If you did a plain `git clone` (no `meta` yet), bootstrap from inside the repo — it installs `meta` if missing and materializes the sub-repos:

```bash
make bootstrap
```

## Update everything

`make update` brings everything current — it clones any sub-repos newly added to `.meta`, pulls the rest, and prints a summary of how the available skills changed (added `+`, removed `-`, changed `~`, by `SKILL.md` content):

```bash
make update
# ...
# Skill changes:
#   + new-skill        somerepo/skills/.../new-skill
#   ~ review           mattpocock-skills/skills/in-progress/review
```

`make pull` is the lighter variant: pull every repo (including this meta-repo) in parallel, no summary.

## Add another skill repo

```bash
make add FOLDER=<owner>-<repo> URL=https://github.com/<owner>/<repo>.git
# e.g. "add mattpocock/skills":
make add FOLDER=mattpocock-skills URL=https://github.com/mattpocock/skills.git
```

Conventions: the folder is named `<owner>-<repo>` (e.g. `mattpocock/skills` → `mattpocock-skills`); use an HTTPS URL for third-party repos and SSH (`git@github.com:<owner>/<repo>.git`) only for repos you own and push to — which is why `akafred-skills` uses SSH and the others HTTPS.

`make add` clones the repo into `<folder>` and records it in both `.meta` and `.gitignore`. Then commit the updated `.meta` and `.gitignore` in this meta-repo.

## Install skills

First explore what's available — `make list` lists every skill (name, repo, description), `make search QUERY=<text>` searches names, descriptions, and bodies across all sub-repos with ranked, concise results (`LIMIT=all` for the full set, `SNIPPETS=0` for no body lines), `make show SKILL=<name>` pretty-prints a skill's `SKILL.md` (rendered with `glow`/`bat`/`mdcat` if installed, else plain), and `make peek SKILL=<name>` prints just a skill's frontmatter (`name`/`description`).

`make install-skills` symlinks the skills you pick into a target repo, choosing skill folders for **cross-tool compatibility** (Claude Code, Copilot CLI, OpenCode, Codex). Pass `TARGET=<repo>` to install elsewhere; with no target it installs into this meta-repo itself. `SKILLS=` names one or more skills (or `all`); omit it for an interactive picker.

```bash
make install-skills                                  # interactive, into this meta-repo
make install-skills SKILLS=meta-repo                 # named skill(s), into this meta-repo
make install-skills TARGET=~/code/app SKILLS=all     # everything, into another repo
```

### Where skills get installed

Different agents discover skills from different per-repo folders. A one-line summary: by default you get `.agents/skills` (the vendor-neutral standard) with `.claude/skills` symlinked to it, which together cover all four tools. In detail: `make install-skills` only ever auto-creates those two folders, but also recognizes `.github/skills`, `.gemini/skills`, and `.opencode/skills` if a repo already uses them. The target is chosen by how many of those folders already physically exist:

- **2 or more exist** → real per-skill links are installed into **each** of them (the repo's existing conventions are respected; nothing new is created).
- **Exactly 1 exists** → it becomes canonical (real links live there), and the missing folder of `.claude/skills` / `.agents/skills` is created as a **folder-level symlink** to it.
- **None exist** → `.agents/skills` is created as canonical, with `.claude/skills` symlinked to it.

Sub-repos must be cloned first (`make bootstrap` / `make update`). Links are **relative**, so they survive across clones and machines. This meta-repo's own `.claude/skills/` is committed (with `.agents/skills` symlinked to it) — a fresh checkout already has the skills wired up for every agent; the links resolve once the sub-repos are materialized (`make update`), and dangle until then.

### Listing what's installed

`make list-installed` shows the skills currently installed in a repo and where each link points — back into this meta-repo (with `(dangling)` if the sub-repo isn't materialized yet), or `(external)`/`(local dir)` for links `make install-skills` didn't create. Folder-level mirrors (e.g. `.agents/skills → .claude/skills`) are noted, not double-listed. Pass `TARGET=<repo>` to inspect another repo.

### Uninstalling

`make uninstall-skills` removes the selected skills' links from the target repo. It only removes symlinks that point back into this meta-repo (your own files and foreign symlinks are left untouched), then cleans up: emptied skill dirs are removed and any now-dangling folder-level symlinks (e.g. `.agents/skills → .claude/skills`) are dropped.

```bash
make uninstall-skills SKILLS=meta-repo               # remove one skill, from this meta-repo
make uninstall-skills TARGET=~/code/app SKILLS=all   # remove everything, from another repo
```

## Install plugins (Claude Code only)

Some sub-repos are also **Claude Code plugins** — beyond skills they ship slash commands, subagents, and hooks, declared in a `.claude-plugin/` directory. Plugins install through Claude Code's own plugin system (no other agent properly supports plugins), which runs alongside the skill symlinks: the same repo's skills stay individually symlinkable via `make install-skills`, and installing it as a plugin is an independent, additional option.

```bash
make list-plugins                                    # what's available, and from which marketplace
make install-plugins                                 # interactive picker, into this meta-repo
make install-plugins PLUGINS=superpowers TARGET=~/code/app
make list-installed-plugins TARGET=~/code/app        # what's enabled in a repo
make uninstall-plugins PLUGINS=all TARGET=~/code/app
```

Requires the `claude` CLI (only for install/uninstall — the two list targets work without it).

### Where plugins install from (`SOURCE=`)

By default (`SOURCE=origin`) plugins install from their **upstream repo** — the URL recorded in `.meta` — so they track the original source like a normal plugin install would; the local clones remain your browsing/searching catalog. `SOURCE=local` instead registers the local clone as the marketplace, so installs come from what's on your disk (useful offline, or when developing a plugin). One caveat the tooling flags at install time: a marketplace entry that itself pins a GitHub source (addyosmani's does) is fetched from GitHub even in local mode.

Sub-repos that ship their own `.claude-plugin/marketplace.json` are registered as marketplaces directly. For plugin-only repos (a `plugin.json` but no marketplace), a **synthesized marketplace** named `meta-skills` is generated at this repo's root (`.claude-plugin/marketplace.json`, gitignored, regenerated on each install) so they're installable the same way. Marketplace registrations are recorded in your user settings and are never removed automatically — `make uninstall-plugins` prints the `claude plugin marketplace remove` commands if you want them gone.

### Where plugins get enabled (`SCOPE=`)

Plugin content is cached under `~/.claude/plugins/`; what's per-repo is the **enablement**, written to the target's settings per `SCOPE=`:

- `local` (default) → `<target>/.claude/settings.local.json` — personal, typically gitignored
- `project` → `<target>/.claude/settings.json` — committed, shared with your team
- `user` → `~/.claude/settings.json` — enabled globally, in every repo

## Common operations

`make help` lists everything; the central operations all have targets:

| Command | Does |
| --- | --- |
| `make bootstrap` | Install `meta` if missing, clone all sub-repos |
| `make update` | Update all sub-repos (clone new, pull rest) + summarize skill changes |
| `make add FOLDER=.. URL=..` | Add a sub-repo |
| `make status` | Git status across all repos |
| `make pull` | Pull all repos (parallel) |
| `make stats` | Lines of code per repo (needs `cloc`) |
| `make list` | List all skills across sub-repos (name, repo, description) |
| `make list-repos` | List configured sub-repos (folder → url) |
| `make search QUERY=..` | Ranked skill search with concise snippets (`LIMIT=`, `SNIPPETS=`) |
| `make show SKILL=..` | Pretty-print a skill's `SKILL.md` (name or substring) |
| `make peek SKILL=..` | Print a skill's frontmatter only (name or substring) |
| `make install-skills` | Symlink skills into a repo (see above) |
| `make list-installed` | List skills installed in a repo, and where each link points |
| `make uninstall-skills` | Remove skill links from a repo (see above) |
| `make list-plugins` | List Claude Code plugins across sub-repos |
| `make install-plugins` | Install plugins via Claude Code (see above) |
| `make list-installed-plugins` | List plugins enabled in a repo |
| `make uninstall-plugins` | Uninstall plugins from a repo |

The only operation not behind `make` is the very first clone — `meta git clone <url>` — since there is no checkout to run `make` from yet (or use plain `git clone` then `make bootstrap`). See `docs/` for cross-repo documentation.
