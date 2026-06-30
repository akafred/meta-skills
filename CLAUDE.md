# meta-skills — agent orientation

This is a **meta-repo**, not a normal repo. It contains no skills of its own — it
*references* other skill repositories via [`meta`](https://github.com/mateodelnorte/meta).
The `meta-repo` skill (in `akafred-skills/skills/engineering/meta-repo/SKILL.md`)
is the authoritative guide to the pattern.

## Use `make` as the entry point

Every operation on this repo is a `make` target. Run `make help` first and use the
matching target — adding a repo, updating, listing or searching skills, installing
or uninstalling them, status, stats all map to one. The `## ` text on each target
is its full usage (parameters included), so don't open the `Makefile` to confirm a
command, don't reverse-engineer from `.meta`, and don't hand-roll `meta`/`git`
invocations; the target is the interface. A request like "add obra/superpowers" is
just `make add` with the conventions below.

## What a plain `git clone` gives you (and the trap)

`git clone` fetches only `.meta`, `.gitignore`, `README.md`, `Makefile`,
`bin/`, `docs/`. The referenced sub-repos — `akafred-skills/`,
`mattpocock-skills/` — are **git-ignored and absent**. The repo is not broken;
the sub-repos are materialized separately.

To get everything:

```bash
make bootstrap                                          # installs meta if missing, then clones sub-repos
# equivalently, if meta is already installed:
meta git clone git@github.com:akafred/meta-skills.git   # meta-repo + all sub-repos
meta git update                                         # inside an existing clone: clone missing sub-repos
```

`make bootstrap` is the safe first step after a plain `git clone`. It needs
`node`/`npm`; `cloc` is optional (used by `make stats`).

## Using the skills

Explore what's available with `make list` (list all skills) and
`make search QUERY=<text>` (search name/description/body across sub-repos).

The aggregated skills only become active after they are symlinked into a repo's
`.claude/skills/`. Discover and install them with:

```bash
make install-skills                          # interactive picker (into this meta-repo)
make install-skills TARGET=~/code/app SKILLS=all
# or the script directly for finer control:
bin/install-skills.sh --target ~/code/app all
```

This meta-repo's own `.claude/skills/` is **committed** (relative symlinks), so a
fresh checkout already has the skills wired up — they resolve once the sub-repos
are materialized (`meta git update`) and dangle until then. See `README.md` for
the full command set and `make help` for the menu.

## Conventions `make help` can't show

- **Adding a repo** (`make add`): name the folder `<owner>-<repo>` (e.g.
  `mattpocock/skills` → `mattpocock-skills`), and use an HTTPS URL for third-party
  repos — SSH (`git@github.com:<owner>/<repo>.git`) only for repos you own and
  push to, which is why `akafred-skills` uses SSH and the rest HTTPS. Commit the
  updated `.meta` + `.gitignore` afterward.

## What lives where

- `.meta` — the source of truth: folder → sub-repo git URL. Add repos with
  `make add` (see above), then commit `.meta` + `.gitignore`.
- Sub-repo contents belong to *those* repos; commits there have their own
  remotes and PRs. This meta-repo only tracks its coordination files.
- `docs/` — cross-repo documentation that no single sub-repo owns.
