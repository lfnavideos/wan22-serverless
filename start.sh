#!/bin/bash

echo "[WAN22] Iniciando worker..."

# Criar symlinks para modelos no volume
if [ -d "/runpod-volume/wan22_models" ]; then
    echo "[WAN22] Criando symlinks para modelos..."

    # Diffusion models
    ln -sf /runpod-volume/wan22_models/diffusion_models/* /comfyui/models/diffusion_models/ 2>/dev/null

    # LoRAs
    ln -sf /runpod-volume/wan22_models/loras/* /comfyui/models/loras/ 2>/dev/null

    # VAE
    ln -sf /runpod-volume/wan22_models/vae/* /comfyui/models/vae/ 2>/dev/null

    # Text encoders
    ln -sf /runpod-volume/wan22_models/text_encoders/* /comfyui/models/text_encoders/ 2>/dev/null

    # CLIP
    ln -sf /runpod-volume/wan22_models/clip/* /comfyui/models/clip/ 2>/dev/null

    echo "[WAN22] Symlinks criados!"
    ls -la /comfyui/models/diffusion_models/
    ls -la /comfyui/models/loras/
else
    echo "[WAN22] AVISO: Volume nao encontrado em /runpod-volume/wan22_models"
fi

# ====== INICIO DO SCRIPT ORIGINAL DO WORKER-COMFYUI ======

# Find libtcmalloc and set LD_PRELOAD for memory optimization
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Set ComfyUI Manager to offline mode (se o script existir)
if [ -f /scripts/comfy-manager-set-mode.sh ]; then
    bash /scripts/comfy-manager-set-mode.sh offline
fi

# Get log level from environment or default to DEBUG
COMFY_LOG_LEVEL="${COMFY_LOG_LEVEL:-DEBUG}"

echo "[WAN22] Iniciando ComfyUI..."

# Start ComfyUI in the background
if [ "${SERVE_API_LOCALLY}" == "true" ]; then
    python /comfyui/main.py --disable-auto-launch --disable-metadata --listen --log-level "${COMFY_LOG_LEVEL}" &
else
    python /comfyui/main.py --disable-auto-launch --disable-metadata --log-level "${COMFY_LOG_LEVEL}" &
fi

# NOVO: Aguardar ComfyUI iniciar antes de chamar o handler
echo "[WAN22] Aguardando ComfyUI iniciar..."
for i in {1..60}; do
    if curl -s http://127.0.0.1:8188 > /dev/null 2>&1; then
        echo "[WAN22] ComfyUI esta online! (tentativa $i)"
        break
    fi
    echo "[WAN22] Aguardando... ($i/60)"
    sleep 2
done

# Verificar se ComfyUI está realmente rodando
if ! curl -s http://127.0.0.1:8188 > /dev/null 2>&1; then
    echo "[WAN22] ERRO: ComfyUI nao iniciou apos 120 segundos!"
    echo "[WAN22] Verificando logs de erro..."
    # Mostra os últimos processos python
    ps aux | grep python
    exit 1
fi

echo "[WAN22] Iniciando RunPod Handler..."

# Start the RunPod Handler
if [ "${SERVE_API_LOCALLY}" == "true" ]; then
    python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    python -u /handler.py
fi
