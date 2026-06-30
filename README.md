# meta-skills

A meta-repo that aggregates several independent skill repositories: it references the sub-repos via [`meta`](https://github.com/mateodelnorte/meta) and tracks only its own coordination files (`.meta`, `.gitignore`, this `README.md`, the `Makefile`, and `docs/`) — never the sub-repos' contents.

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

After pulling the meta-repo, materialize any newly-added sub-repos and pull each:

```bash
make update   # clone any sub-repos added to .meta since last update
make pull     # pull all repos (parallel, rebase, autostash)
```

## Add another skill repo

```bash
make add FOLDER=<name> URL=<git-url>
```

This clones the repo into `<folder>` and records it in both `.meta` and `.gitignore`. Then commit the updated `.meta` and `.gitignore` in this meta-repo.

## Install skills

`install-skills.sh` discovers every `SKILL.md` across all sub-repos (read from `.meta`) and symlinks the ones you pick into a target repo's `.claude/skills/`. Point it at the repo you want the skill installed into with `--target`; with no target it installs into this meta-repo itself.

```bash
./install-skills.sh                          # interactive, into this meta-repo
./install-skills.sh meta-repo                # named skill(s), into this meta-repo
./install-skills.sh --target ~/code/app all  # everything, into another repo
./install-skills.sh -t ~/code/app code-review
make install-skills SKILLS=meta-repo         # via make (this meta-repo)
```

Sub-repos must be cloned first (`make bootstrap` / `make update`). Links are **relative**, so they survive across clones and machines. This meta-repo's own `.claude/skills/` is committed — a fresh checkout already has the skills wired up; the links resolve once the sub-repos are materialized (`make update`), and dangle until then.

## Common operations

`make help` lists everything; the central operations all have targets:

| Command | Does |
| --- | --- |
| `make bootstrap` | Install `meta` if missing, clone all sub-repos |
| `make update` | Clone sub-repos newly added to `.meta` |
| `make add FOLDER=.. URL=..` | Add a sub-repo |
| `make status` | Git status across all repos |
| `make pull` | Pull all repos (parallel) |
| `make stats` | Lines of code per repo (needs `cloc`) |
| `make list` | List configured projects |
| `make install-skills` | Symlink skills into a repo (see above) |

The only operation not behind `make` is the very first clone — `meta git clone <url>` — since there is no checkout to run `make` from yet (or use plain `git clone` then `make bootstrap`). See `docs/` for cross-repo documentation.
