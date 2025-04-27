#!/bin/bash

# Activate the ComfyUI venv
source /venv/main/bin/activate

# Set up workspace paths
WORKSPACE="/workspace"
COMFYUI_DIR="${WORKSPACE}/ComfyUI"
FLUXGYM_DIR="${WORKSPACE}/FluxGym"

# Packages are installed after nodes so we can fix them...
APT_PACKAGES=(
    #"package-1"
    #"package-2"
)

PIP_PACKAGES=(
    #"package-1"
    #"package-2"
    #"voluptuous"
    #"xformers==0.0.20rc2"
)

NODES=(
    #"https://github.com/ltdrdata/ComfyUI-Manager"
    #"https://github.com/cubiq/ComfyUI_essentials"
)

WORKFLOWS=(

)

CHECKPOINT_MODELS=(
    "https://civitai.com/api/download/models/798204?type=Model&format=SafeTensor&size=full&fp=fp16"
)

UNET_MODELS=(
)

LORA_MODELS=(
)

VAE_MODELS=(
)

ESRGAN_MODELS=(
)

CONTROLNET_MODELS=(
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_get_nodes
    provisioning_get_pip_packages

    # Pull in all the ComfyUI models
    provisioning_get_files \
        "${COMFYUI_DIR}/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/unet" \
        "${UNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/lora" \
        "${LORA_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/esrgan" \
        "${ESRGAN_MODELS[@]}"

    # Now install FluxGym into the same venv
    provisioning_install_fluxgym

    provisioning_print_end

    # Finally, launch both services
    provisioning_launch_services
}

function provisioning_get_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
        sudo apt update
        sudo apt install -y "${APT_PACKAGES[@]}"
    fi
}

function provisioning_get_pip_packages() {
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        install_path="${COMFYUI_DIR}/custom_nodes/${dir}"
        requirements="${install_path}/requirements.txt"
        if [[ -d $install_path ]]; then
            printf "Updating node: %s...\n" "${repo}"
            (cd "$install_path" && git pull)
        else
            printf "Cloning node: %s...\n" "${repo}"
            git clone "$repo" "$install_path" --recursive
        fi
        [[ -f $requirements ]] && pip install --no-cache-dir -r "$requirements"
    done
}

function provisioning_get_files() {
    if [[ -z "$2" ]]; then return; fi
    local dest_dir="$1"; shift
    mkdir -p "$dest_dir"
    printf "Downloading %d model(s) to %s...\n" "$#" "$dest_dir"
    for url in "$@"; do
        printf "  -> %s\n" "$url"
        provisioning_download "$url" "$dest_dir"
    done
}

function provisioning_print_header() {
    cat <<'EOF'

##############################################
#                                            #
#       Provisioning container (UI + Gym)    #
#                                            #
#      This will take a minute or two        #
#                                            #
# Your container will launch both services   #
#                                            #
##############################################

EOF
}

function provisioning_print_end() {
    echo
    echo "Provisioning complete — starting ComfyUI & FluxGym..."
    echo
}

# Download helper (respects HF_TOKEN / CIVITAI_TOKEN if set)
function provisioning_download() {
    url="$1"; dest="$2"
    auth_header=()
    if [[ -n "$HF_TOKEN" && "$url" =~ huggingface\.co ]]; then
        auth_header=(-H "Authorization: Bearer $HF_TOKEN")
    elif [[ -n "$CIVITAI_TOKEN" && "$url" =~ civitai\.com ]]; then
        auth_header=(-H "Authorization: Bearer $CIVITAI_TOKEN")
    fi
    wget -q --show-progress --content-disposition "${auth_header[@]}" -P "$dest" "$url"
}

#
# FLUXGYM installation into the same /venv/main venv
#
function provisioning_install_fluxgym() {
    echo "=== Installing FluxGym into ComfyUI venv ==="
    # Clone the FluxGym repo
    git clone https://github.com/cocktailpeanut/fluxgym "$FLUXGYM_DIR"
    # fluxgym depends on Kohya sd-scripts
    git clone -b sd3 https://github.com/kohya-ss/sd-scripts "$FLUXGYM_DIR/sd-scripts"

    # We're already in /venv/main, so just pip install into that venv:
    pip install --no-cache-dir -r "$FLUXGYM_DIR/sd-scripts/requirements.txt"
    pip install --no-cache-dir -r "$FLUXGYM_DIR/requirements.txt"

    echo "=== FluxGym installed at $FLUXGYM_DIR ==="
}

#
# Launch both UIs without blocking the provisioning script
#
function provisioning_launch_services() {
    echo ">>> Launching ComfyUI on port 18188"
    comfyui-command --disable-auto-launch --port 18188 --enable-cors-header &

    echo ">>> Launching FluxGym on port 7860"
    cd "$FLUXGYM_DIR"
    # venv is already active
    python app.py --host 0.0.0.0 --port 7860 > fluxgym.log 2>&1 &

    # return to workspace root
    cd "$WORKSPACE"
}

# start provisioning if not disabled
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
