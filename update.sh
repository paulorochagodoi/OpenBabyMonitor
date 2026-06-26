#!/bin/bash
# update.sh — Atualiza o OpenBabyMonitor preservando todos os dados existentes.
#
# Uso:
#   ./update.sh            — aplica migrações e reinicia o servidor
#   ./update.sh --pull     — faz git pull antes de aplicar as migrações
#   ./update.sh --help     — exibe este texto
#
# O script deve ser executado pelo mesmo usuário que instalou o sistema
# (geralmente 'pi'), no diretório raiz do repositório.

set -euo pipefail

# ── Cores ──────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERRO]${NC}  $*" >&2; }
die()     { error "$*"; exit 1; }

# ── Diretório base ─────────────────────────────────────────────────────────────
BM_DIR=$(dirname "$(readlink -f "$0")")
cd "$BM_DIR"

# ── Ajuda ──────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--help" ]]; then
    sed -n '2,10p' "$0" | sed 's/^# \{0,2\}//'
    exit 0
fi

# ── Flags ──────────────────────────────────────────────────────────────────────
DO_PULL=false
for arg in "$@"; do
    [[ "$arg" == "--pull" ]] && DO_PULL=true
done

echo ""
echo "════════════════════════════════════════════"
echo "  OpenBabyMonitor — Script de Atualização  "
echo "════════════════════════════════════════════"
echo ""

# ── 1. Verificar usuário ───────────────────────────────────────────────────────
info "Verificando usuário..."

ENV_FILE="$BM_DIR/env/envvar_exports"
CONFIG_ENV="$BM_DIR/config/setup_config.env"

if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
elif [[ -f "$CONFIG_ENV" ]]; then
    source "$CONFIG_ENV"
else
    warn "Arquivo de ambiente não encontrado; usando variáveis padrão."
    BM_USER="${BM_USER:-pi}"
    BM_WEB_GROUP="${BM_WEB_GROUP:-www-data}"
    BM_READ_PERMISSIONS="${BM_READ_PERMISSIONS:-750}"
    BM_WRITE_PERMISSIONS="${BM_WRITE_PERMISSIONS:-770}"
fi

CURRENT_USER="$(whoami)"
if [[ "$CURRENT_USER" != "$BM_USER" && "$CURRENT_USER" != "root" ]]; then
    die "Este script deve ser executado pelo usuário '$BM_USER' (ou root). Usuário atual: $CURRENT_USER"
fi
ok "Usuário: $CURRENT_USER"

# ── 2. Ler credenciais do banco a partir do config.json ────────────────────────
info "Lendo configuração do banco de dados..."

CONFIG_JSON="$BM_DIR/config/config.json"
[[ -f "$CONFIG_JSON" ]] || die "Arquivo config.json não encontrado em: $CONFIG_JSON"

DB_HOST=$(python3 -c "import json,sys; c=json.load(open('$CONFIG_JSON')); print(c['database']['account']['host'])")
DB_USER=$(python3 -c "import json,sys; c=json.load(open('$CONFIG_JSON')); print(c['database']['account']['user'])")
DB_PASS=$(python3 -c "import json,sys; c=json.load(open('$CONFIG_JSON')); print(c['database']['account']['password'])")
DB_NAME=$(python3 -c "import json,sys; c=json.load(open('$CONFIG_JSON')); print(c['database']['name'])")

ok "Banco: $DB_NAME  |  Usuário: $DB_USER  |  Host: $DB_HOST"

# Função auxiliar para executar SQL
run_sql() {
    local sql="$1"
    if [[ -n "$DB_PASS" ]]; then
        mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASS" "$DB_NAME" -e "$sql" 2>&1
    else
        mysql --host="$DB_HOST" --user="$DB_USER" "$DB_NAME" -e "$sql" 2>&1
    fi
}

# Verificar se o banco está acessível
if ! run_sql "SELECT 1;" > /dev/null 2>&1; then
    die "Não foi possível conectar ao banco '$DB_NAME'. Verifique se o MariaDB está rodando e as credenciais em config.json."
fi
ok "Conexão com o banco estabelecida."

# ── 3. Git pull (opcional) ─────────────────────────────────────────────────────
if [[ "$DO_PULL" == true ]]; then
    info "Atualizando código via git pull..."
    if ! command -v git &>/dev/null; then
        warn "git não encontrado; pulando git pull."
    else
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "desconhecida")
        info "Branch atual: $CURRENT_BRANCH"
        git pull origin "$CURRENT_BRANCH" || die "Falha no git pull. Resolva conflitos e execute novamente."
        ok "Código atualizado."
    fi
else
    info "Pulando git pull (use --pull para atualizar o código automaticamente)."
fi

# ── 4. Migrações do banco de dados ─────────────────────────────────────────────
echo ""
info "Aplicando migrações do banco de dados..."

# 4a. Migrar coluna language.current de CHAR(2) para CHAR(5)
info "  [migração 1/2] Verificando tipo da coluna 'language.current'..."
COL_TYPE=$(run_sql "SELECT COLUMN_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='language' AND COLUMN_NAME='current';" | tail -1)

if [[ "$COL_TYPE" == "char(2)" || "$COL_TYPE" == "CHAR(2)" ]]; then
    info "  Coluna é CHAR(2); ampliando para CHAR(5) para suportar 'pt-br'..."
    run_sql "ALTER TABLE \`language\` MODIFY COLUMN \`current\` CHAR(5) NOT NULL;"
    ok "  Coluna 'language.current' atualizada para CHAR(5)."
elif [[ -z "$COL_TYPE" ]]; then
    warn "  Tabela 'language' não encontrada; pulando migração de idioma."
else
    ok "  Coluna 'language.current' já é '$COL_TYPE'; nenhuma alteração necessária."
fi

# 4b. Criar tabela events (se não existir)
info "  [migração 2/2] Criando tabela 'events' (se não existir)..."
run_sql "
CREATE TABLE IF NOT EXISTS \`events\` (
    \`id\`          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    \`type\`        VARCHAR(20) NOT NULL,
    \`recorded_at\` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);"
ok "  Tabela 'events' verificada/criada."

# ── 5. Corrigir permissões nos arquivos novos ──────────────────────────────────
echo ""
info "Ajustando permissões nos arquivos novos..."

NEW_FILES=(
    "$BM_DIR/site/public/timeline.php"
    "$BM_DIR/site/public/get_events.php"
    "$BM_DIR/site/public/clear_events.php"
    "$BM_DIR/site/public/js/timeline.js"
    "$BM_DIR/site/src/events.php"
    "$BM_DIR/site/public/lang/en/timeline.json"
    "$BM_DIR/site/public/lang/no/timeline.json"
    "$BM_DIR/site/public/lang/pt-br"
)

for path in "${NEW_FILES[@]}"; do
    if [[ -e "$path" ]]; then
        sudo chmod "$BM_READ_PERMISSIONS" "$path"
        sudo chown -R "$BM_USER:$BM_WEB_GROUP" "$path"
    else
        warn "  Arquivo/diretório não encontrado (pode não estar nesta instalação): $path"
    fi
done
ok "Permissões atualizadas."

# ── 6. Reiniciar Apache ────────────────────────────────────────────────────────
echo ""
info "Reiniciando Apache para carregar os novos arquivos PHP..."
if command -v systemctl &>/dev/null && systemctl is-active --quiet apache2 2>/dev/null; then
    sudo systemctl restart apache2
    ok "Apache reiniciado."
elif command -v service &>/dev/null; then
    sudo service apache2 restart
    ok "Apache reiniciado."
else
    warn "Apache não encontrado ou não está rodando via systemctl/service. Reinicie manualmente se necessário."
fi

# ── Conclusão ─────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════"
ok "Atualização concluída com sucesso!"
echo ""
echo "  Novidades desta versão:"
echo "  • Tradução para Português (Brasil) disponível no menu de idioma"
echo "  • Nova tela de Histórico em /timeline.php"
echo "    — registra automaticamente cada evento detectado (choro, balbucio, som)"
echo "    — filtragem por tipo, agrupamento por dia e limpeza do histórico"
echo "════════════════════════════════════════════"
echo ""
