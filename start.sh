#!/bin/bash
echo "========================================"
echo "[WAN22] INICIANDO WORKER v6.0"
echo "========================================"
echo "[WAN22] Data: $(date)"

# Diagnosticos basicos
echo ""
echo "[WAN22] === AMBIENTE ==="
echo "[WAN22] Python: $(python --version 2>&1)"
python -c "import torch; print(f'[WAN22] PyTorch: {torch.__version__}, CUDA: {torch.cuda.is_available()}')" 2>&1 || true

# GPU
echo ""
echo "[WAN22] === GPU ==="
nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv 2>&1 || true

# Volume e symlinks
echo ""
echo "[WAN22] === VOLUME ==="
if [ -d "/runpod-volume/wan22_models" ]; then
    echo "[WAN22] wan22_models encontrado!"
    for dir in diffusion_models loras vae text_encoders clip; do
        if [ -d "/runpod-volume/wan22_models/$dir" ]; then
            ln -sf /runpod-volume/wan22_models/$dir/* /comfyui/models/$dir/ 2>/dev/null || true
            echo "[WAN22] Symlink $dir: OK"
        fi
    done
else
    echo "[WAN22] AVISO: wan22_models NAO encontrado"
fi

# CLIP Vision
echo ""
echo "[WAN22] === CLIP VISION ==="
if [ -f "/comfyui/models/clip_vision/clip_vision_h.safetensors" ]; then
    echo "[WAN22] clip_vision_h.safetensors OK"
else
    echo "[WAN22] AVISO: clip_vision_h.safetensors NAO encontrado!"
fi

# Iniciar ComfyUI
echo ""
echo "[WAN22] === INICIANDO COMFYUI ==="
cd /comfyui
python main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch --disable-metadata &
COMFY_PID=$!
echo "[WAN22] ComfyUI PID: $COMFY_PID"

# Aguardar 15s (handler tem retry interno)
echo "[WAN22] Aguardando 15s para inicializacao..."
sleep 15

if ! kill -0 $COMFY_PID 2>/dev/null; then
    echo "[WAN22] ERRO: ComfyUI morreu!"
    exit 1
fi

echo ""
echo "[WAN22] === INICIANDO HANDLER ==="
cd /
exec python -u /handler.py
