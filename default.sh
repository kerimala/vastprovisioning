#!/bin/bash

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# Packages are installed after nodes so we can fix them...
APT_PACKAGES=(
    #"package-1"
    #"package-2"
)

PIP_PACKAGES=(
    #"package-1"
    #"package-2"
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
    provisioning_install_fluxgym   # <— install FluxGym
    provisioning_print_end
    provisioning_launch_services  # <— start both ComfyUI & FluxGym
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
        sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
        pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                (cd "$path" && git pull)
                [[ -e $requirements ]] && pip install --no-cache-dir -r "$requirements"
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            [[ -e $requirements ]] && pip install --no-cache-dir -r "${requirements}"
        fi
    done
}

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n"
    printf "#     Provisioning container (ComfyUI+Gym)    #\n"
    printf "##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete: starting ComfyUI & FluxGym...\n\n"
}

# … (other helper functions for tokens, download, etc.) …

# --- FLUXGYM INSTALLATION & LAUNCH ---

function provisioning_install_fluxgym() {
    echo "=== Installing FluxGym ==="
    FLUXGYM_DIR="${COMFYUI_DIR}/fluxgym"

    # Clone FluxGym & sd-scripts
    git clone https://github.com/cocktailpeanut/fluxgym "${FLUXGYM_DIR}"
    git clone -b sd3 https://github.com/kohya-ss/sd-scripts "${FLUXGYM_DIR}/sd-scripts"

    # Create venv and install
    cd "${FLUXGYM_DIR}"
    python3 -m venv env
    source env/bin/activate

    pip install --no-cache-dir -r sd-scripts/requirements.txt
    pip install --no-cache-dir -r requirements.txt
    # nightly PyTorch for CUDA 12.1
    pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

    deactivate
    echo "=== FluxGym installed at ${FLUXGYM_DIR} ==="
}

function provisioning_launch_services() {
    echo "=== Launching ComfyUI on port 18188 ==="
    # Launch ComfyUI without blocking
    comfyui-command --disable-auto-launch --port 18188 --enable-cors-header &

    echo "=== Launching FluxGym on port 7860 ==="
    FLUXGYM_DIR="${COMFYUI_DIR}/fluxgym"
    cd "${FLUXGYM_DIR}"
    source env/bin/activate
    nohup python app.py --host 0.0.0.0 --port 7860 > fluxgym.log 2>&1 &
    deactivate
}

# entry point
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
