# meta-skills — agent orientation

This is a **meta-repo**, not a normal repo. It contains no skills of its own — it
*references* other skill repositories via [`meta`](https://github.com/mateodelnorte/meta).
The `meta-repo` skill (in `akafred-skills/skills/engineering/meta-repo/SKILL.md`)
is the authoritative guide to the pattern.

## Use `make` as the entry point

Every operation on this repo is a `make` target. Run `make help` first and use the
matching target — adding a repo, updating, listing/searching/showing available
skills, listing what's installed in a repo, installing or uninstalling them,
status, stats all map to one. The `## ` text on each target
is its full usage (parameters included), so don't open the `Makefile` to confirm a
command, don't reverse-engineer from `.meta`, and don't hand-roll `meta`/`git`
invocations; the target is the interface. A request like "add obra/superpowers" is
just `make add` with the conventions below.

Each target reports its own result — read that output and report it. Don't
re-verify with `ls` or a second command, and don't pre-check before a target that
would fail clearly on its own.

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

A skill you install is **active immediately**: install only finds skills that live
in an already-cloned sub-repo, so the new link resolves right away — don't tell the
user it will activate later. The "dangles until materialized" caveat applies only
to this meta-repo's own **committed** `.claude/skills/` links on a fresh checkout
(before `meta git update`), never to a fresh install. See `README.md` for the full
command set and `make help` for the menu.

## Using the plugins (Claude Code only)

Some sub-repos are also **Claude Code plugins** (they have a top-level
`.claude-plugin/`, possibly with their own marketplace). These install through
Claude Code's plugin system, not symlinks: `make list-plugins` shows them,
`make install-plugins` installs (needs the `claude` CLI; `TARGET=`, `SCOPE=`
local/project/user, `SOURCE=` origin/local), `make list-installed-plugins` and
`make uninstall-plugins` complete the set. Plugins install from their upstream
repo by default (`SOURCE=origin`); repos without their own marketplace are served
by a synthesized `meta-skills` marketplace generated (gitignored) at this repo's
root. The two mechanisms coexist: a plugin repo's skills remain individually
symlinkable via `make install-skills`, and installing the plugin is a separate,
additional choice — don't treat one as replacing the other.

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
