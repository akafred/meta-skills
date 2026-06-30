# meta-skills — agent orientation

This is a **meta-repo**, not a normal repo. It contains no skills of its own — it
*references* other skill repositories via [`meta`](https://github.com/mateodelnorte/meta).
The `meta-repo` skill (in `akafred-skills/skills/engineering/meta-repo/SKILL.md`)
is the authoritative guide to the pattern.

## What a plain `git clone` gives you (and the trap)

`git clone` fetches only `.meta`, `.gitignore`, `README.md`, `Makefile`,
`install-skills.sh`, `docs/`. The referenced sub-repos — `akafred-skills/`,
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

The aggregated skills only become active after they are symlinked into a repo's
`.claude/skills/`. Discover and install them with:

```bash
./install-skills.sh                          # interactive picker (into this meta-repo)
./install-skills.sh --target ~/code/app all  # install into another repo
```

This meta-repo's own `.claude/skills/` is **committed** (relative symlinks), so a
fresh checkout already has the skills wired up — they resolve once the sub-repos
are materialized (`meta git update`) and dangle until then. See `README.md` for
the full command set and `make help` for the menu.

## What lives where

- `.meta` — the source of truth: folder → sub-repo git URL. Edit via
  `meta project import <folder> <url>`, then commit `.meta` + `.gitignore`.
- Sub-repo contents belong to *those* repos; commits there have their own
  remotes and PRs. This meta-repo only tracks its coordination files.
- `docs/` — cross-repo documentation that no single sub-repo owns.
