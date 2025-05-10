#!/bin/bash
set -euo pipefail

# ----------------------------------------
# Activate the ComfyUI venv
# ----------------------------------------
source /venv/main/bin/activate

# ----------------------------------------
# Workspace & Paths
# ----------------------------------------
WORKSPACE="/workspace"
COMFYUI_DIR="${WORKSPACE}/ComfyUI"
FLUXGYM_DIR="${WORKSPACE}/FluxGym"
FLUXGYM_VENV="${WORKSPACE}/fluxgym_venv"

# ----------------------------------------
# Package-Listen (leer lassen oder anpassen)
# ----------------------------------------
APT_PACKAGES=(
    # "package-1"
)
PIP_PACKAGES=(
    # "xformers==0.0.20rc2"
)
NODES=(
    # "https://github.com/ltdrdata/ComfyUI-Manager"
)

# Modelle (Beispiel)
CHECKPOINT_MODELS=(
    "https://civitai.com/api/download/models/798204?type=Model&format=SafeTensor&size=full&fp=fp16"
)

# ----------------------------------------
# Hilfsfunktionen
# ----------------------------------------
function die() {
    echo "✖ ERROR: $*" >&2
    exit 1
}

function info() {
    echo "→ $*"
}

function provisioning_download() {
    local url="$1"; local dest="$2"
    local auth_header=()
    if [[ -n "${HF_TOKEN:-}" && "$url" =~ huggingface\.co ]]; then
        auth_header=(-H "Authorization: Bearer $HF_TOKEN")
    elif [[ -n "${CIVITAI_TOKEN:-}" && "$url" =~ civitai\.com ]]; then
        auth_header=(-H "Authorization: Bearer $CIVITAI_TOKEN")
    fi
    wget -q --show-progress --content-disposition "${auth_header[@]}" -P "$dest" "$url" \
        || die "Download fehlgeschlagen: $url"
}

# ----------------------------------------
# 1. Apt-Pakete
# ----------------------------------------
function install_apt() {
    if (( ${#APT_PACKAGES[@]} > 0 )); then
        sudo apt update
        sudo apt install -y "${APT_PACKAGES[@]}" \
            || die "apt install fehlgeschlagen"
    fi
}

# ----------------------------------------
# 2. Pip-Pakete für ComfyUI
# ----------------------------------------
function install_pip_comfyui() {
    if (( ${#PIP_PACKAGES[@]} > 0 )); then
        pip install --no-cache-dir "${PIP_PACKAGES[@]}" \
            || die "pip install (ComfyUI extra) fehlgeschlagen"
    fi
}

# ----------------------------------------
# 3. Custom Nodes
# ----------------------------------------
function install_nodes() {
    for repo in "${NODES[@]}"; do
        local dir="${repo##*/}"
        local install_path="${COMFYUI_DIR}/custom_nodes/${dir}"
        local req="${install_path}/requirements.txt"

        if [[ -d "$install_path" ]]; then
            info "Updating node $repo"
            git -C "$install_path" pull || die "git pull $repo fehlgeschlagen"
        else
            info "Cloning node $repo"
            git clone --recursive "$repo" "$install_path" || die "git clone $repo fehlgeschlagen"
        fi

        [[ -f "$req" ]] && pip install --no-cache-dir -r "$req" \
            || die "pip install requirements for $repo fehlgeschlagen"
    done
}

# ----------------------------------------
# 4. Modelle herunterladen
# ----------------------------------------
function install_models() {
    local dest
    dest="${COMFYUI_DIR}/models/checkpoints"; mkdir -p "$dest"
    info "Lade Checkpoints herunter..."
    for url in "${CHECKPOINT_MODELS[@]}"; do
        provisioning_download "$url" "$dest"
    done
    # (weitere Modell-Kategorien analog)
}

# ----------------------------------------
# 5. FluxGym in eigenem venv
# ----------------------------------------
function setup_fluxgym_venv() {
    info "Erstelle FluxGym-Venv unter $FLUXGYM_VENV"
    python3 -m venv "$FLUXGYM_VENV" || die "venv Creation fehlgeschlagen"

    source "$FLUXGYM_VENV/bin/activate"
    git clone https://github.com/cocktailpeanut/fluxgym "$FLUXGYM_DIR" \
        || die "FluxGym-Repo clone fehlgeschlagen"
    git clone -b sd3 https://github.com/kohya-ss/sd-scripts "$FLUXGYM_DIR/sd-scripts" \
        || die "sd-scripts clone fehlgeschlagen"

    info "Installiere sd-scripts Requirements"
    pip install --no-cache-dir -r "$FLUXGYM_DIR/sd-scripts/requirements.txt" \
        || die "pip install sd-scripts fehlgeschlagen"
    info "Installiere FluxGym Requirements"
    pip install --no-cache-dir -r "$FLUXGYM_DIR/requirements.txt" \
        || die "pip install FluxGym fehlgeschlagen"
    deactivate
}

# ----------------------------------------
# 6. Dienste starten
# ----------------------------------------
function launch_services() {
    # ComfyUI
    info "Starte ComfyUI (Port 18188)"
    nohup /venv/main/bin/comfyui-command \
        --disable-auto-launch --port 18188 --enable-cors-header \
        &> "$WORKSPACE/comfyui.log" &
    disown

    # FluxGym
    info "Starte FluxGym (Port 7860)"
    source "$FLUXGYM_VENV/bin/activate"
    nohup python "$FLUXGYM_DIR/app.py" --host 0.0.0.0 --port 7860 \
        &> "$WORKSPACE/fluxgym.log" &
    disown
    deactivate

    # Kurzer Healthcheck
    sleep 5
    if curl --fail http://localhost:7860/health &> /dev/null; then
        info "FluxGym ist erreichbar"
    else
        die "FluxGym nicht erreichbar – siehe fluxgym.log"
    fi
}

# ----------------------------------------
# Haupt-Provisioning
# ----------------------------------------
function provisioning_start() {
    cat <<'EOF'

##############################################
#                                            #
#    Provisioning container (UI + Gym)       #
#                                            #
##############################################

EOF

    install_apt
    install_pip_comfyui
    install_nodes
    install_models
    setup_fluxgym_venv

    cat <<'EOF'

Provisioning abgeschlossen – starte Dienste...

EOF

    launch_services
}

# Starte Provisioning, falls nicht deaktiviert
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
