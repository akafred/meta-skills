# meta-skills

A meta-repo that aggregates several independent skill repositories: it references the sub-repos via [`meta`](https://github.com/mateodelnorte/meta) and tracks only its own coordination files (`.meta`, `.gitignore`, this `README.md`, the `Makefile`, and `docs/`) — never the sub-repos' contents.

## Referenced skill repositories

| Folder | Source |
| --- | --- |
| `akafred-skills` | `git@github.com:akafred/skills.git` |
| `mattpocock-skills` | `https://github.com/mattpocock/skills.git` |

## Clone everything

Clone the meta-repo and all referenced skill repos in one step:

```bash
meta git clone <this-meta-repo-url>
```

## Update everything

After pulling the meta-repo, materialize any newly-added sub-repos and pull each:

```bash
meta git update          # clone any sub-repos added to .meta since last update
make pull                # pull all repos (parallel, rebase, autostash)
```

## Add another skill repo

```bash
meta project import <folder> <git-url>
```

This clones the repo into `<folder>` and records it in both `.meta` and `.gitignore`. Then commit the updated `.meta` and `.gitignore` in this meta-repo.

## Common operations

Run `make help` for the command menu. See `docs/` for cross-repo documentation.
