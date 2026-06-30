.PHONY: $(shell sed -n -e '/^$$/ { n ; /^[^ .\#][^ ]*:/ { s/:.*$$// ; p ; } ; }' $(MAKEFILE_LIST))

meta_project := $(notdir $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))

help: ## Show this help
	@grep -hE '^\S+:.*##' $(MAKEFILE_LIST) | sed -e 's/:.*##\s*/ : /' | \
	while IFS=' : ' read -r cmd desc; do printf "\033[36m%-20s\033[0m %s\n" "$$cmd" "$$desc"; done

status: ## Git status across all repos
	@meta git status

pull: ## Pull all repos (parallel, rebase, autostash)
	@meta exec "git pull --rebase --autostash" --parallel

stats: ## Lines of code per skill repo (needs cloc)
	@meta exec "cloc . --vcs=git --quiet" --exclude "$(meta_project)"

list: ## List configured projects (folder -> url, from .meta)
	@node -e 'const p=JSON.parse(require("fs").readFileSync(".meta","utf8")).projects; for (const [k,v] of Object.entries(p)) console.log(k+" -> "+v);'

install-skills: ## Install skills into this meta-repo (interactive; or: make install-skills SKILLS="meta-repo")
	@./install-skills.sh $(SKILLS)
