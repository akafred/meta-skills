# meta-skills

A meta-repo that aggregates several independent skill repositories: it references the sub-repos via [`meta`](https://github.com/mateodelnorte/meta) and tracks only its own coordination files (`.meta`, `.gitignore`, this `README.md`, the `Makefile`, `bin/`, and `docs/`) — never the sub-repos' contents.

## Referenced skill repositories

| Folder | Source |
| --- | --- |
| `akafred-skills` | `git@github.com:akafred/skills.git` |
| `mattpocock-skills` | `https://github.com/mattpocock/skills.git` |

## Clone everything

Clone the meta-repo and all referenced skill repos in one step (requires `meta`):

```bash
meta git clone <this-meta-repo-url>
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
# e.g. "add obra/superpowers":
make add FOLDER=obra-superpowers URL=https://github.com/obra/superpowers.git
```

Conventions: the folder is named `<owner>-<repo>` (e.g. `mattpocock/skills` → `mattpocock-skills`); use an HTTPS URL for third-party repos and SSH (`git@github.com:<owner>/<repo>.git`) only for repos you own and push to — which is why `akafred-skills` uses SSH and the others HTTPS.

`make add` clones the repo into `<folder>` and records it in both `.meta` and `.gitignore`. Then commit the updated `.meta` and `.gitignore` in this meta-repo.

## Install skills

First explore what's available — `make list` lists every skill (name, repo, description), `make search QUERY=<text>` searches names, descriptions, and bodies across all sub-repos, and `make show SKILL=<name>` pretty-prints a skill's `SKILL.md` (rendered with `glow`/`bat`/`mdcat` if installed, else plain).

`bin/install-skills.sh` discovers every `SKILL.md` across all sub-repos (read from `.meta`) and symlinks the ones you pick into a target repo, choosing skill folders for **cross-tool compatibility** (Claude Code, Copilot CLI, OpenCode, Codex). Point it at the repo you want the skill installed into with `--target`; with no target it installs into this meta-repo itself.

```bash
bin/install-skills.sh                          # interactive, into this meta-repo
bin/install-skills.sh meta-repo                # named skill(s), into this meta-repo
bin/install-skills.sh --target ~/code/app all  # everything, into another repo
bin/install-skills.sh -t ~/code/app code-review
make install-skills SKILLS=meta-repo           # via make (this meta-repo)
```

### Where skills get installed

Different agents discover skills from different per-repo folders. `.claude/skills` (Claude Code, Copilot CLI, OpenCode) and `.agents/skills` (Copilot CLI, OpenCode, Codex — the vendor-neutral standard) together cover all four, so those are the only folders the installer ever auto-creates. It also recognizes `.github/skills`, `.gemini/skills`, and `.opencode/skills` if a repo already uses them. The target is chosen by how many of those folders already physically exist:

- **2 or more exist** → real per-skill links are installed into **each** of them (the repo's existing conventions are respected; nothing new is created).
- **Exactly 1 exists** → it becomes canonical (real links live there), and the missing folder of `.claude/skills` / `.agents/skills` is created as a **folder-level symlink** to it.
- **None exist** → `.agents/skills` is created as canonical, with `.claude/skills` symlinked to it.

Sub-repos must be cloned first (`make bootstrap` / `make update`). Links are **relative**, so they survive across clones and machines. This meta-repo's own `.claude/skills/` is committed (with `.agents/skills` symlinked to it) — a fresh checkout already has the skills wired up for every agent; the links resolve once the sub-repos are materialized (`make update`), and dangle until then.

### Listing what's installed

`make list-installed` (or `bin/install-skills.sh --list [-t DIR]`) shows the skills currently installed in a repo and where each link points — back into this meta-repo (with `(dangling)` if the sub-repo isn't materialized yet), or `(external)`/`(local dir)` for links this installer didn't create. Folder-level mirrors (e.g. `.agents/skills → .claude/skills`) are noted, not double-listed.

### Uninstalling

Pass `--uninstall` (or `-u`) to remove the selected skills' links from the target repo. It only removes symlinks that point back into this meta-repo (your own files and foreign symlinks are left untouched), then cleans up: emptied skill dirs are removed and any now-dangling folder-level symlinks (e.g. `.agents/skills → .claude/skills`) are dropped.

```bash
bin/install-skills.sh --uninstall code-review   # remove one skill, from this meta-repo
bin/install-skills.sh -u -t ~/code/app all      # remove everything, from another repo
make uninstall-skills SKILLS=meta-repo           # via make
make uninstall-skills TARGET=~/code/app SKILLS=all
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
