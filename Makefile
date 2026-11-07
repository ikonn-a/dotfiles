# dotfiles — macOS / Linux, без Homebrew.
# Совместимо с GNU Make 3.81 (системный make в macOS).

SHELL := /bin/sh
.DEFAULT_GOAL := help

REPO_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
export REPO_ROOT

PKGS ?=
NODE_VERSION ?=

.PHONY: help install dry-run uninstall deps bin node npmrc secrets doctor check bootstrap update repo

help: ## Список целей
	@printf '\n dotfiles: %s\n\n' "$(REPO_ROOT)"
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z_-]+:.*## / { printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2 }' "$(REPO_ROOT)/Makefile"
	@printf '\n  Переменные: PKGS="rg bat" make bin\n              NODE_VERSION=24.22.2 make node\n\n'

install: ## Симлинки src/ -> $$HOME (старое в backup/)
	@sh "$(REPO_ROOT)/install.sh"

dry-run: ## Показать план линковки
	@sh "$(REPO_ROOT)/install.sh" --dry-run

uninstall: ## Снять симлинки, ведущие в этот репозиторий
	@sh "$(REPO_ROOT)/unlink.sh"

deps: ## Поставить пакеты из packages/packages.csv (apt-get/dnf)
	@sh "$(REPO_ROOT)/scripts/install-packages.sh"

bin: ## Скачать CLI в ~/.local/bin (без brew и root)
	@sh "$(REPO_ROOT)/scripts/fetch-bin.sh" $(PKGS)

node: ## Поставить Node.js LTS в ~/.local/share/nodejs (NODE_VERSION=x.y.z)
	@sh "$(REPO_ROOT)/scripts/install-node.sh" $(NODE_VERSION)

npmrc: ## Проверить npm: глобальные пакеты в ~/.local, без sudo
	@printf '  конфиг: %s\n' "$$HOME/.npmrc"
	@if [ -f "$$HOME/.npmrc" ]; then \
		printf '  (уже есть, не трогаю — make install залинкует версию из репозитория)\n'; \
	else \
		printf '  отсутствует, выполните: make install\n'; \
	fi
	@printf '  проверка: npm config get prefix  (ожидается %s/.local)\n' "$$HOME"

secrets: ## Создать local/work/personal.gitconfig и secrets.env из шаблонов
	@mkdir -p "$$HOME/.config/secrets.d"
	@if [ -f "$$HOME/.config/secrets.d/secrets.env" ]; then \
		printf '  уже существует: %s (не трогаю)\n' "$$HOME/.config/secrets.d/secrets.env"; \
	else \
		cp "$(REPO_ROOT)/src/.config/secrets.d/env.example" "$$HOME/.config/secrets.d/secrets.env"; \
		chmod 600 "$$HOME/.config/secrets.d/secrets.env"; \
		printf '  создан: %s (chmod 600)\n' "$$HOME/.config/secrets.d/secrets.env"; \
	fi
	@mkdir -p "$$HOME/.config/git"
	@for f in local work personal; do \
		if [ -f "$$HOME/.config/git/$$f.gitconfig" ]; then \
			printf '  уже существует: %s (не трогаю)\n' "$$HOME/.config/git/$$f.gitconfig"; \
		else \
			cp "$(REPO_ROOT)/src/.config/git/$$f.gitconfig.example" "$$HOME/.config/git/$$f.gitconfig"; \
			printf '  создан: %s\n' "$$HOME/.config/git/$$f.gitconfig"; \
		fi; \
	done
	@printf '\n  дальше: заполните имя/почту в\n'
	@printf '    %s  — рабочая identity (по умолчанию)\n' "$$HOME/.config/git/work.gitconfig"
	@printf '    %s — личная identity для ~/projects/\n' "$$HOME/.config/git/personal.gitconfig"

doctor: ## Проверить окружение
	@sh "$(REPO_ROOT)/scripts/doctor.sh"

check: ## Проверить синтаксис конфигов и скриптов
	@sh "$(REPO_ROOT)/scripts/check.sh"

bootstrap: deps secrets install doctor ## Новая машина: deps + secrets + install + doctor

update: ## git pull --ff-only && make install
	@git -C "$(REPO_ROOT)" pull --ff-only
	@sh "$(REPO_ROOT)/install.sh"

repo: ## git init -b main + добавить origin
	@cd "$(REPO_ROOT)" && { [ -d .git ] || git init -b main; }
	@cd "$(REPO_ROOT)" && { git remote get-url origin >/dev/null 2>&1 || git remote add origin https://github.com/ikonn-a/dotfiles.git; }
	@cd "$(REPO_ROOT)" && git status --short --branch
