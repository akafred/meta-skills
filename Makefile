.PHONY: $(shell sed -n -e '/^$$/ { n ; /^[^ .\#][^ ]*:/ { s/:.*$$// ; p ; } ; }' $(MAKEFILE_LIST))

meta_project := $(notdir $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))

help: ## Show this help
	@grep -hE '^\S+:.*##' $(MAKEFILE_LIST) | sed -e 's/:.*##\s*/ : /' | \
	while IFS=' : ' read -r cmd desc; do printf "\033[36m%-20s\033[0m %s\n" "$$cmd" "$$desc"; done

bootstrap: ## Install prerequisites (meta) and clone all sub-repos
	@command -v node >/dev/null 2>&1 || { echo "✗ node/npm required — install from https://nodejs.org"; exit 1; }
	@command -v meta >/dev/null 2>&1 || { echo "→ installing meta CLI (npm install -g meta)..."; npm install -g meta; }
	@command -v cloc >/dev/null 2>&1 || echo "ℹ cloc not found — 'make stats' needs it (e.g. brew install cloc)"
	@echo "→ materializing sub-repos (meta git update)..."
	@meta git update
	@echo "✓ ready. Skills committed under .claude/skills now resolve; run 'make install-skills' to add more."

update: ## Update all sub-repos (clone new, pull rest) and summarize skill changes
	@bin/update.sh

add: ## Add a sub-repo: FOLDER=<owner>-<repo> URL=https://github.com/<owner>/<repo>.git
	@test -n "$(FOLDER)" && test -n "$(URL)" || { echo "Usage: make add FOLDER=<owner>-<repo> URL=https://github.com/<owner>/<repo>.git"; exit 1; }
	@meta project import $(FOLDER) $(URL)
	@n=$$(find $(FOLDER) -name SKILL.md 2>/dev/null | wc -l | tr -d ' '); \
	  echo "✓ added '$(FOLDER)' — discovered $$n skill(s). Commit the updated .meta and .gitignore."; \
	  [ "$$n" -gt 0 ] || echo "⚠ no SKILL.md found — check the repo's layout, then 'make list'."

status: ## Git status across all repos
	@meta git status

pull: ## Pull all repos (parallel, rebase, autostash)
	@meta exec "git pull --rebase --autostash" --parallel

stats: ## Lines of code per skill repo (needs cloc)
	@meta exec "cloc . --vcs=git --quiet" --exclude "$(meta_project)"

list: ## List all skills across sub-repos (name, repo, description)
	@bin/skills.sh list

list-repos: ## List configured sub-repos (folder -> url, from .meta)
	@node -e 'const p=JSON.parse(require("fs").readFileSync(".meta","utf8")).projects; for (const [k,v] of Object.entries(p)) console.log(k+" -> "+v);'

search: ## Search skills by name/description/body: make search QUERY=<text>
	@test -n "$(QUERY)" || { echo "Usage: make search QUERY=<text>"; exit 1; }
	@bin/skills.sh search "$(QUERY)"

show: ## Pretty-print a skill's SKILL.md: make show SKILL=<name-or-substring>
	@test -n "$(SKILL)" || { echo "Usage: make show SKILL=<name>"; exit 1; }
	@bin/skills.sh show "$(SKILL)"

list-installed: ## List skills installed in a repo (TARGET=/path/to/repo; default this repo)
	@bin/install-skills.sh --list $(if $(TARGET),--target $(TARGET))

install-skills: ## Install skills (interactive; SKILLS="name..." TARGET=/path/to/repo)
	@bin/install-skills.sh $(if $(TARGET),--target $(TARGET)) $(SKILLS)

uninstall-skills: ## Uninstall skills (interactive; SKILLS="name..."|all TARGET=/path/to/repo)
	@bin/install-skills.sh --uninstall $(if $(TARGET),--target $(TARGET)) $(SKILLS)
