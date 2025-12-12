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

# Iniciar o handler do RunPod
echo "[WAN22] Iniciando handler..."
exec python -u /handler.py
