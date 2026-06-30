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

update: ## Clone sub-repos newly added to .meta
	@meta git update

add: ## Add a sub-repo: make add FOLDER=<name> URL=<git-url>
	@test -n "$(FOLDER)" && test -n "$(URL)" || { echo "Usage: make add FOLDER=<name> URL=<git-url>"; exit 1; }
	@meta project import $(FOLDER) $(URL)
	@echo "✓ added '$(FOLDER)'. Commit the updated .meta and .gitignore."

status: ## Git status across all repos
	@meta git status

pull: ## Pull all repos (parallel, rebase, autostash)
	@meta exec "git pull --rebase --autostash" --parallel

stats: ## Lines of code per skill repo (needs cloc)
	@meta exec "cloc . --vcs=git --quiet" --exclude "$(meta_project)"

list: ## List configured projects (folder -> url, from .meta)
	@node -e 'const p=JSON.parse(require("fs").readFileSync(".meta","utf8")).projects; for (const [k,v] of Object.entries(p)) console.log(k+" -> "+v);'

install-skills: ## Install skills (interactive; SKILLS="name..." TARGET=/path/to/repo)
	@./install-skills.sh $(if $(TARGET),--target $(TARGET)) $(SKILLS)
