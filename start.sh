#!/bin/bash
echo "========================================"
echo "[WAN22] WORKER v7.0 - FAST START"
echo "========================================"

# Symlinks do volume
if [ -d "/runpod-volume/wan22_models" ]; then
    for dir in diffusion_models loras vae text_encoders clip; do
        ln -sf /runpod-volume/wan22_models/$dir/* /comfyui/models/$dir/ 2>/dev/null || true
    done
    echo "[WAN22] Symlinks OK"
fi

# Iniciar ComfyUI em background
cd /comfyui
python main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch --disable-metadata &
echo "[WAN22] ComfyUI iniciado em background"

# Iniciar handler IMEDIATAMENTE (ele tem retry interno)
echo "[WAN22] Iniciando handler..."
cd /
exec python -u /handler.py
