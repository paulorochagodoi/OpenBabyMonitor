#!/bin/bash
# update.sh — Atualizador zipado do OpenBabyMonitor (preserva todos os dados).
#
# Este script é distribuído DENTRO do pacote de atualização (.zip). Ele copia
# os arquivos novos/alterados para a instalação existente, aplica as migrações
# do banco de dados e reinicia o servidor — sem precisar de git.
#
# Uso (no Raspberry Pi):
#   1. Baixe e extraia o pacote de atualização.
#   2. Entre na pasta extraída e execute:
#        ./update.sh                       (detecta a instalação automaticamente)
#        ./update.sh --target /caminho     (informa a pasta da instalação)
#        ./update.sh --dry-run             (mostra o que faria, sem alterar nada)
#        ./update.sh --help
#
# Deve ser executado pelo usuário que instalou o sistema (ex.: pi) ou root.

set -euo pipefail

# ── Cores ──────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERRO]${NC}  $*" >&2; }
die()   { error "$*"; exit 1; }

# ── Pasta do pacote (onde este script e os arquivos novos estão) ───────────────
PACKAGE_DIR=$(dirname "$(readlink -f "$0")")

# ── Argumentos ─────────────────────────────────────────────────────────────────
INSTALL_DIR=""
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        --target)
            INSTALL_DIR="${2:-}"; shift 2 ;;
        --target=*)
            INSTALL_DIR="${1#*=}"; shift ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        *)
            die "Argumento desconhecido: $1 (use --help)" ;;
    esac
done

echo ""
echo "════════════════════════════════════════════════════"
echo "  OpenBabyMonitor — Atualização (pacote zipado)     "
echo "════════════════════════════════════════════════════"
echo ""
$DRY_RUN && warn "Modo simulação (--dry-run): nenhum arquivo será alterado."

# ── Lista de arquivos que esta atualização instala ─────────────────────────────
# (config/config.json NÃO entra aqui — é atualizado por patch, mais abaixo.)
FILES=(
    "control/listen.py"
    "control/recording.py"
    "detection/features.py"
    "site/config/language_config.php"
    "site/config/path_config.php"
    "site/config/site_config.php"
    "site/public/listen.php"
    "site/public/timeline.php"
    "site/public/get_events.php"
    "site/public/clear_events.php"
    "site/public/recordings.php"
    "site/public/get_recordings.php"
    "site/public/get_recording_audio.php"
    "site/public/delete_recording.php"
    "site/public/clear_recordings.php"
    "site/public/js/timeline.js"
    "site/public/js/recordings.js"
    "site/src/events.php"
    "site/src/recordings.php"
    "site/templates/navbar.php"
    "site/public/lang/en/common.json"
    "site/public/lang/en/timeline.json"
    "site/public/lang/en/recordings.json"
    "site/public/lang/en/listen_settings.json"
    "site/public/lang/no/common.json"
    "site/public/lang/no/timeline.json"
    "site/public/lang/no/recordings.json"
    "site/public/lang/no/listen_settings.json"
    "site/public/lang/pt-br/common.json"
    "site/public/lang/pt-br/main.json"
    "site/public/lang/pt-br/index.json"
    "site/public/lang/pt-br/listen_settings.json"
    "site/public/lang/pt-br/audiostream_settings.json"
    "site/public/lang/pt-br/videostream_settings.json"
    "site/public/lang/pt-br/network_settings.json"
    "site/public/lang/pt-br/system_settings.json"
    "site/public/lang/pt-br/debugging.json"
    "site/public/lang/pt-br/timeline.json"
    "site/public/lang/pt-br/recordings.json"
)

# ── 1. Validar o pacote ────────────────────────────────────────────────────────
info "Validando o pacote de atualização..."
[[ -f "$PACKAGE_DIR/config/config.json" ]] || die "Pacote inválido: config/config.json não encontrado em $PACKAGE_DIR"
MISSING=()
for f in "${FILES[@]}"; do
    [[ -f "$PACKAGE_DIR/$f" ]] || MISSING+=("$f")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    error "O pacote está incompleto. Arquivos ausentes:"
    for f in "${MISSING[@]}"; do error "    - $f"; done
    die "Baixe o pacote de atualização completo e tente novamente."
fi
ok "Pacote válido."

# ── 2. Localizar a instalação existente ────────────────────────────────────────
is_install() {  # uma instalação válida tem config.json e a pasta env/ gerada no setup
    [[ -f "$1/config/config.json" && -f "$1/site/public/index.php" && -d "$1/env" ]]
}

if [[ -n "$INSTALL_DIR" ]]; then
    INSTALL_DIR=$(readlink -f "$INSTALL_DIR")
    is_install "$INSTALL_DIR" || die "A pasta informada não é uma instalação válida do OpenBabyMonitor: $INSTALL_DIR"
else
    info "Procurando a instalação do OpenBabyMonitor..."
    CANDIDATES=(
        "$HOME/OpenBabyMonitor"
        "/home/pi/OpenBabyMonitor"
        "/opt/OpenBabyMonitor"
        "/var/www/babymonitor"
    )
    # Inclui qualquer /home/*/OpenBabyMonitor
    for d in /home/*/OpenBabyMonitor; do CANDIDATES+=("$d"); done
    for d in "${CANDIDATES[@]}"; do
        d=$(readlink -f "$d" 2>/dev/null || echo "$d")
        if [[ "$d" != "$PACKAGE_DIR" ]] && is_install "$d"; then
            INSTALL_DIR="$d"; break
        fi
    done
    # Caso o script tenha sido colocado dentro da própria instalação
    if [[ -z "$INSTALL_DIR" ]] && is_install "$PACKAGE_DIR"; then
        INSTALL_DIR="$PACKAGE_DIR"
    fi
    [[ -n "$INSTALL_DIR" ]] || die "Instalação não encontrada. Use: ./update.sh --target /caminho/para/OpenBabyMonitor"
fi
ok "Instalação encontrada: $INSTALL_DIR"

SAME_DIR=false
[[ "$INSTALL_DIR" == "$PACKAGE_DIR" ]] && SAME_DIR=true
$SAME_DIR && info "O pacote e a instalação são a mesma pasta; os arquivos já estão no lugar."

# ── 3. Carregar variáveis de ambiente da instalação ────────────────────────────
ENV_FILE="$INSTALL_DIR/env/envvar_exports"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi
BM_USER="${BM_USER:-pi}"
BM_WEB_GROUP="${BM_WEB_GROUP:-www-data}"
BM_READ_PERMISSIONS="${BM_READ_PERMISSIONS:-750}"

CURRENT_USER="$(whoami)"
if [[ "$CURRENT_USER" != "$BM_USER" && "$CURRENT_USER" != "root" ]]; then
    warn "Recomenda-se executar como '$BM_USER' ou root (usuário atual: $CURRENT_USER)."
fi

# ── 4. Backup dos arquivos que serão substituídos ──────────────────────────────
STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$INSTALL_DIR/.update_backup_$STAMP"
if ! $SAME_DIR; then
    info "Criando backup dos arquivos atuais em: $BACKUP_DIR"
    for f in "${FILES[@]}" "config/config.json"; do
        if [[ -f "$INSTALL_DIR/$f" ]]; then
            if ! $DRY_RUN; then
                mkdir -p "$BACKUP_DIR/$(dirname "$f")"
                cp -p "$INSTALL_DIR/$f" "$BACKUP_DIR/$f"
            fi
        fi
    done
    ok "Backup concluído."
fi

# ── 5. Copiar os arquivos novos/alterados ──────────────────────────────────────
if ! $SAME_DIR; then
    info "Instalando os arquivos atualizados..."
    for f in "${FILES[@]}"; do
        if $DRY_RUN; then
            echo "    copiaria  $f"
        else
            mkdir -p "$INSTALL_DIR/$(dirname "$f")"
            cp -f "$PACKAGE_DIR/$f" "$INSTALL_DIR/$f"
        fi
    done
    ok "Arquivos instalados."
else
    info "Pulando a cópia de arquivos (mesma pasta)."
fi

# ── 6. Patch do config.json (preserva credenciais e customizações) ─────────────
info "Atualizando config/config.json (idioma pt-br, configurações de gravação)..."
PATCH_PY=$(cat <<'PYEOF'
import json, sys, collections
path = sys.argv[1]
with open(path, encoding='utf-8') as fh:
    cfg = json.load(fh, object_pairs_hook=collections.OrderedDict)
changed = False
lang = cfg.get('language', {}).get('current')
if lang is not None:
    if lang.get('type') != 'CHAR(5) NOT NULL':
        lang['type'] = 'CHAR(5) NOT NULL'; changed = True
    vals = lang.setdefault('values', [])
    if 'pt-br' not in vals:
        vals.append('pt-br'); changed = True
listen = cfg.get('listen_settings')
if listen is not None:
    if 'enable_recording' not in listen:
        new_listen = collections.OrderedDict()
        for key, value in listen.items():
            if key == 'amplification':
                new_listen['enable_recording'] = collections.OrderedDict([
                    ('group', 'recording'),
                    ('name', 'enable_recording'),
                    ('type', 'BOOLEAN NOT NULL'),
                    ('initial_value', True)])
                new_listen['recording_max_storage'] = collections.OrderedDict([
                    ('group', 'recording'),
                    ('name', 'recording_max_storage'),
                    ('type', 'INT UNSIGNED NOT NULL'),
                    ('initial_value', 500),
                    ('range', collections.OrderedDict([
                        ('min', 50), ('max', 5000), ('step', 50)])),
                    ('disabled_when', {'enable_recording': {
                        'operator': '!=', 'value': '1'}})])
            new_listen[key] = value
        cfg['listen_settings'] = new_listen
        changed = True
if changed:
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(cfg, fh, indent=4, ensure_ascii=False)
        fh.write('\n')
    print('patched')
else:
    print('unchanged')
PYEOF
)
if $DRY_RUN; then
    echo "    aplicaria patch em $INSTALL_DIR/config/config.json"
else
    RESULT=$(python3 -c "$PATCH_PY" "$INSTALL_DIR/config/config.json")
    if [[ "$RESULT" == "patched" ]]; then
        ok "config.json atualizado (pt-br adicionado, coluna de idioma ampliada)."
    else
        ok "config.json já estava atualizado."
    fi
fi

# ── 7. Ajustar permissões dos arquivos instalados ──────────────────────────────
if ! $SAME_DIR && ! $DRY_RUN; then
    info "Ajustando permissões..."
    for f in "${FILES[@]}" "config/config.json"; do
        target="$INSTALL_DIR/$f"
        [[ -e "$target" ]] || continue
        sudo chown "$BM_USER:$BM_WEB_GROUP" "$target" 2>/dev/null || true
        sudo chmod "$BM_READ_PERMISSIONS" "$target" 2>/dev/null || true
    done
    # Garante que a pasta de idioma pt-br tenha as permissões corretas
    if [[ -d "$INSTALL_DIR/site/public/lang/pt-br" ]]; then
        sudo chown -R "$BM_USER:$BM_WEB_GROUP" "$INSTALL_DIR/site/public/lang/pt-br" 2>/dev/null || true
        sudo chmod "$BM_READ_PERMISSIONS" "$INSTALL_DIR/site/public/lang/pt-br" 2>/dev/null || true
    fi
    ok "Permissões ajustadas."
fi

# ── 8. Migração do banco de dados (best-effort) ────────────────────────────────
# Observação: o código novo também migra automaticamente na primeira execução,
# então esta etapa é apenas para aplicar as mudanças imediatamente.
echo ""
info "Aplicando migrações do banco de dados..."
CONFIG_JSON="$INSTALL_DIR/config/config.json"
DB_HOST=$(python3 -c "import json; print(json.load(open('$CONFIG_JSON'))['database']['account']['host'])")
DB_USER=$(python3 -c "import json; print(json.load(open('$CONFIG_JSON'))['database']['account']['user'])")
DB_PASS=$(python3 -c "import json; print(json.load(open('$CONFIG_JSON'))['database']['account']['password'])")
DB_NAME=$(python3 -c "import json; print(json.load(open('$CONFIG_JSON'))['database']['name'])")

run_sql() {
    if [[ -n "$DB_PASS" ]]; then
        mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASS" "$DB_NAME" -N -e "$1" 2>/dev/null
    else
        mysql --host="$DB_HOST" --user="$DB_USER" "$DB_NAME" -N -e "$1" 2>/dev/null
    fi
}

if $DRY_RUN; then
    echo "    migraria a coluna language.current, criaria a tabela events"
    echo "    e adicionaria as colunas de gravação em listen_settings"
elif ! command -v mysql &>/dev/null; then
    warn "Cliente mysql não encontrado; o banco será migrado automaticamente pelo site na primeira execução."
elif ! run_sql "SELECT 1;" >/dev/null; then
    warn "Não foi possível conectar ao banco agora; o site fará a migração automaticamente na primeira execução."
else
    COL_TYPE=$(run_sql "SELECT COLUMN_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='language' AND COLUMN_NAME='current';")
    if [[ "${COL_TYPE,,}" == "char(2)" ]]; then
        run_sql "ALTER TABLE \`language\` MODIFY COLUMN \`current\` CHAR(5) NOT NULL;" && \
            ok "  Coluna 'language.current' ampliada para CHAR(5)."
    else
        ok "  Coluna 'language.current' já está adequada (${COL_TYPE:-ausente})."
    fi
    run_sql "CREATE TABLE IF NOT EXISTS \`events\` (
        \`id\` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        \`type\` VARCHAR(20) NOT NULL,
        \`recorded_at\` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP);" && \
        ok "  Tabela 'events' verificada/criada."
    HAS_ENABLE_RECORDING=$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='listen_settings' AND COLUMN_NAME='enable_recording';")
    if [[ "$HAS_ENABLE_RECORDING" == "0" ]]; then
        run_sql "ALTER TABLE \`listen_settings\` ADD COLUMN \`enable_recording\` BOOLEAN NOT NULL DEFAULT TRUE;" && \
            ok "  Coluna 'listen_settings.enable_recording' adicionada."
    else
        ok "  Coluna 'listen_settings.enable_recording' já existe."
    fi
    HAS_MAX_STORAGE=$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='listen_settings' AND COLUMN_NAME='recording_max_storage';")
    if [[ "$HAS_MAX_STORAGE" == "0" ]]; then
        run_sql "ALTER TABLE \`listen_settings\` ADD COLUMN \`recording_max_storage\` INT UNSIGNED NOT NULL DEFAULT 500;" && \
            ok "  Coluna 'listen_settings.recording_max_storage' adicionada."
    else
        ok "  Coluna 'listen_settings.recording_max_storage' já existe."
    fi
fi

# ── 8b. Pasta de gravações ─────────────────────────────────────────────────────
echo ""
info "Verificando a pasta de gravações..."
RECORDINGS_DIR="${BM_RECORDINGS_DIR:-$INSTALL_DIR/recordings}"
if $DRY_RUN; then
    echo "    criaria $RECORDINGS_DIR (se ausente) com permissões de escrita"
else
    mkdir -p "$RECORDINGS_DIR"
    sudo chown "$BM_USER:$BM_WEB_GROUP" "$RECORDINGS_DIR" 2>/dev/null || true
    sudo chmod "${BM_WRITE_PERMISSIONS:-770}" "$RECORDINGS_DIR" 2>/dev/null || true
    # Registra BM_RECORDINGS_DIR nos arquivos de ambiente, se ainda não estiver lá
    if [[ -f "$ENV_FILE" ]] && ! grep -q "BM_RECORDINGS_DIR" "$ENV_FILE"; then
        echo "export BM_RECORDINGS_DIR=$RECORDINGS_DIR" >> "$ENV_FILE"
    fi
    SERVICE_ENV_FILE="$INSTALL_DIR/env/envvars"
    if [[ -f "$SERVICE_ENV_FILE" ]] && ! grep -q "BM_RECORDINGS_DIR" "$SERVICE_ENV_FILE"; then
        echo "BM_RECORDINGS_DIR=$RECORDINGS_DIR" >> "$SERVICE_ENV_FILE"
    fi
    ok "Pasta de gravações pronta: $RECORDINGS_DIR"
fi

# ── 9. Reiniciar Apache ────────────────────────────────────────────────────────
echo ""
if $DRY_RUN; then
    info "Reiniciaria o Apache."
else
    info "Reiniciando o Apache..."
    if command -v systemctl &>/dev/null; then
        sudo systemctl restart apache2 2>/dev/null && ok "Apache reiniciado." \
            || warn "Não foi possível reiniciar o Apache automaticamente. Reinicie manualmente."
    elif command -v service &>/dev/null; then
        sudo service apache2 restart && ok "Apache reiniciado." \
            || warn "Não foi possível reiniciar o Apache automaticamente. Reinicie manualmente."
    else
        warn "Apache não encontrado; reinicie o servidor web manualmente se necessário."
    fi
fi

# ── Conclusão ─────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
if $DRY_RUN; then
    ok "Simulação concluída — nenhuma alteração foi feita."
else
    ok "Atualização concluída com sucesso!"
    ! $SAME_DIR && echo "  Backup dos arquivos anteriores: $BACKUP_DIR"
fi
echo ""
echo "  Novidades desta versão:"
echo "  • Tradução para Português (Brasil) no menu de idioma"
echo "  • Nova tela de Histórico (timeline.php) que registra"
echo "    automaticamente cada evento detectado (choro, balbucio, som),"
echo "    com filtro por tipo, agrupamento por dia e limpeza do histórico"
echo "  • Gravação contínua no modo de notificação: o áudio é salvo em"
echo "    segmentos e os mais antigos são apagados automaticamente quando"
echo "    o limite de armazenamento é atingido (configurável)"
echo "  • Nova tela de Gravações com player, marcando os momentos em que"
echo "    houve identificação de choro (clique no marcador para ouvir)"
echo ""
echo "  Obs.: reinicie o modo de notificação (ou o dispositivo) para que"
echo "  a gravação comece a funcionar."
echo "════════════════════════════════════════════════════"
echo ""
