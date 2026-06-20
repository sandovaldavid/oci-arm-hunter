SHELL        := /bin/bash
SCRIPT_DIR   := $(CURDIR)
CAZADOR      := $(SCRIPT_DIR)/cazador.sh
SETUP        := $(SCRIPT_DIR)/setup.sh
LOG          := $(SCRIPT_DIR)/cazador.log
TMUX_SESSION := cazador
SERVICE_NAME := cazador-arm
SERVICE_FILE := /etc/systemd/system/$(SERVICE_NAME).service
RUN_USER     := $(shell whoami)

.PHONY: help setup run run-bg logs status stop install uninstall docs-sync

.DEFAULT_GOAL := help

help: ## Muestra todos los comandos disponibles
	@echo ""
	@echo "  OCI ARM Instance Hunter"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""

setup: ## Wizard interactivo para generar .env con tus OCIDs
	@bash $(SETUP)

run: ## Lanza el cazador en primer plano (Ctrl+C para detener)
	@if [[ ! -f "$(SCRIPT_DIR)/.env" ]]; then \
		echo -e "\033[31m[✗]\033[0m No existe .env — ejecuta primero: make setup"; \
		exit 1; \
	fi
	@bash $(CAZADOR)

run-bg: ## Lanza el cazador en sesión tmux persistente (background)
	@if ! command -v tmux &>/dev/null; then \
		echo -e "\033[31m[✗]\033[0m tmux no está instalado."; \
		echo "    Ubuntu: sudo apt install tmux | Oracle Linux: sudo dnf install tmux"; \
		exit 1; \
	fi
	@if [[ ! -f "$(SCRIPT_DIR)/.env" ]]; then \
		echo -e "\033[31m[✗]\033[0m No existe .env — ejecuta primero: make setup"; \
		exit 1; \
	fi
	@tmux new-session -d -s $(TMUX_SESSION) "bash $(CAZADOR)" 2>/dev/null \
		&& echo -e "\033[32m[✓]\033[0m Sesión tmux '$(TMUX_SESSION)' iniciada. Usa 'make logs' para seguir el progreso." \
		|| echo -e "\033[33m[!]\033[0m La sesión '$(TMUX_SESSION)' ya está activa. Usa 'make status'."

logs: ## Muestra el log del cazador en tiempo real (Ctrl+C para salir)
	@if [[ ! -f "$(LOG)" ]]; then \
		echo "No hay log todavía. Inicia el cazador con: make run"; \
	else \
		tail -f $(LOG); \
	fi

status: ## Muestra si el cazador está corriendo (tmux o systemd)
	@echo ""
	@echo "  --- tmux ---"
	@tmux list-sessions 2>/dev/null | grep $(TMUX_SESSION) \
		&& true || echo "  Sin sesión tmux activa."
	@echo "  --- systemd ---"
	@systemctl is-active $(SERVICE_NAME) 2>/dev/null \
		&& echo "  Servicio $(SERVICE_NAME): activo" \
		|| echo "  Servicio no activo (o no instalado)."
	@echo ""

stop: ## Detiene la sesión tmux del cazador
	@tmux kill-session -t $(TMUX_SESSION) 2>/dev/null \
		&& echo -e "\033[32m[✓]\033[0m Sesión '$(TMUX_SESSION)' detenida." \
		|| echo -e "\033[33m[!]\033[0m No hay sesión '$(TMUX_SESSION)' activa."

install: ## Instala cazador-arm como servicio systemd (persiste ante reinicios)
	@echo "Instalando servicio systemd como usuario $(RUN_USER)..."
	@printf '%s\n' \
		'[Unit]' \
		'Description=OCI ARM Instance Hunter' \
		'After=network-online.target' \
		'Wants=network-online.target' \
		'' \
		'[Service]' \
		'Type=simple' \
		'User=$(RUN_USER)' \
		'WorkingDirectory=$(SCRIPT_DIR)' \
		'ExecStart=/bin/bash $(CAZADOR)' \
		'Restart=on-failure' \
		'RestartSec=10' \
		'' \
		'[Install]' \
		'WantedBy=multi-user.target' \
		| sudo tee $(SERVICE_FILE) > /dev/null
	@sudo systemctl daemon-reload
	@sudo systemctl enable --now $(SERVICE_NAME)
	@echo -e "\033[32m[✓]\033[0m Servicio instalado y activo."
	@echo "    Ver logs en tiempo real: sudo journalctl -fu $(SERVICE_NAME)"

uninstall: ## Desactiva y elimina el servicio systemd
	@sudo systemctl disable --now $(SERVICE_NAME) 2>/dev/null || true
	@sudo rm -f $(SERVICE_FILE)
	@sudo systemctl daemon-reload
	@echo -e "\033[32m[✓]\033[0m Servicio $(SERVICE_NAME) eliminado."

docs-sync: ## Sincroniza README.md y CHANGELOG.md con la web docs/
	@python3 scripts/sync_docs.py

