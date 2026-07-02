# meta-skills

A meta-repo that aggregates several independent skill repositories: it references the sub-repos via [`meta`](https://github.com/mateodelnorte/meta) and tracks only its own coordination files (`.meta`, `.gitignore`, this `README.md`, the `Makefile`, `bin/`, and `docs/`) — never the sub-repos' contents.

## Referenced skill repositories

| Folder | Source |
| --- | --- |
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

First explore what's available — `make list` lists every skill (name, repo, description), `make search QUERY=<text>` searches names, descriptions, and bodies across all sub-repos, and `make show SKILL=<name>` pretty-prints a skill's `SKILL.md` (rendered with `glow`/`bat`/`mdcat` if installed, else plain).

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
| `make search QUERY=..` | Search skills by name/description/body |
| `make show SKILL=..` | Pretty-print a skill's `SKILL.md` (name or substring) |
| `make install-skills` | Symlink skills into a repo (see above) |
| `make list-installed` | List skills installed in a repo, and where each link points |
| `make uninstall-skills` | Remove skill links from a repo (see above) |

The only operation not behind `make` is the very first clone — `meta git clone <url>` — since there is no checkout to run `make` from yet (or use plain `git clone` then `make bootstrap`). See `docs/` for cross-repo documentation.
