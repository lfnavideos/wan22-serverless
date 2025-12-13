#!/bin/bash
# Nao usar set -e para evitar exit prematuro

echo "========================================"
echo "[WAN22] INICIANDO WORKER v5.1"
echo "========================================"
echo "[WAN22] Data: $(date)"

# Diagnosticos basicos
echo ""
echo "[WAN22] === AMBIENTE ==="
echo "[WAN22] Python: $(python --version 2>&1)"
echo "[WAN22] PWD: $(pwd)"
python -c "import torch; print(f'[WAN22] PyTorch: {torch.__version__}, CUDA: {torch.cuda.is_available()}')" 2>&1 || echo "[WAN22] ERRO: PyTorch nao disponivel"

# Verificar GPU
echo ""
echo "[WAN22] === GPU ==="
nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv 2>&1 || echo "[WAN22] nvidia-smi nao disponivel"

# Verificar volume e criar symlinks
echo ""
echo "[WAN22] === VOLUME ==="
if [ -d "/runpod-volume" ]; then
    echo "[WAN22] /runpod-volume existe"
    ls -la /runpod-volume/ 2>&1 | head -5

    if [ -d "/runpod-volume/wan22_models" ]; then
        echo "[WAN22] wan22_models encontrado!"
        echo "[WAN22] Criando symlinks..."

        for dir in diffusion_models loras vae text_encoders clip; do
            if [ -d "/runpod-volume/wan22_models/$dir" ]; then
                ln -sf /runpod-volume/wan22_models/$dir/* /comfyui/models/$dir/ 2>/dev/null || true
                echo "[WAN22] Symlink $dir: OK"
            fi
        done
    else
        echo "[WAN22] AVISO: wan22_models NAO encontrado"
    fi
else
    echo "[WAN22] AVISO: /runpod-volume NAO existe"
fi

# Verificar CLIP Vision (ja deve estar na imagem Docker)
echo ""
echo "[WAN22] === CLIP VISION ==="
CLIP_MODEL="/comfyui/models/clip_vision/clip_vision_h.safetensors"
if [ -f "$CLIP_MODEL" ] && [ -s "$CLIP_MODEL" ]; then
    echo "[WAN22] clip_vision_h.safetensors OK (pre-instalado na imagem)"
    ls -lh "$CLIP_MODEL"
else
    echo "[WAN22] AVISO: clip_vision_h.safetensors NAO encontrado!"
    ls -la /comfyui/models/clip_vision/ 2>&1 || true
fi

# Iniciar ComfyUI
echo ""
echo "[WAN22] === INICIANDO COMFYUI ==="
cd /comfyui

python main.py --disable-auto-launch --disable-metadata &
COMFY_PID=$!
echo "[WAN22] ComfyUI PID: $COMFY_PID"

# Aguardar ComfyUI - AUMENTADO para 300s (5 min) porque modelos sao grandes
echo "[WAN22] Aguardando ComfyUI (max 300s - modelos grandes)..."
COMFY_READY=0
for i in $(seq 1 300); do
    if ! kill -0 $COMFY_PID 2>/dev/null; then
        echo "[WAN22] ERRO: ComfyUI morreu!"
        exit 1
    fi

    # Tentar conectar com timeout curto
    if curl -s --connect-timeout 2 --max-time 5 http://127.0.0.1:8188 > /dev/null 2>&1; then
        echo "[WAN22] ComfyUI ONLINE apos ${i}s!"
        COMFY_READY=1
        break
    fi

    if [ $((i % 30)) -eq 0 ]; then
        echo "[WAN22] Ainda aguardando... (${i}s)"
        # Verificar uso de memoria
        nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader 2>/dev/null || true
    fi
    sleep 1
done

# Se nao conseguiu conectar mas processo ainda existe, tentar iniciar handler mesmo assim
if [ $COMFY_READY -eq 0 ]; then
    if kill -0 $COMFY_PID 2>/dev/null; then
        echo "[WAN22] AVISO: Curl falhou mas ComfyUI esta rodando. Tentando iniciar handler..."
    else
        echo "[WAN22] ERRO: ComfyUI nao iniciou e processo morreu!"
        exit 1
    fi
fi

echo ""
echo "[WAN22] === INICIANDO HANDLER ==="
cd /
exec python -u /handler.py
