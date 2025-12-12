#!/bin/bash
set -e

echo "========================================"
echo "[WAN22] INICIANDO WORKER v3.0"
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

# Testar imports criticos
echo ""
echo "[WAN22] === TESTANDO IMPORTS ==="
python -c "
import sys
sys.path.insert(0, '/comfyui')
errors = []

try:
    from comfy.ldm.flux.math import apply_rope1
    print('[WAN22] OK: apply_rope1')
except Exception as e:
    errors.append(f'apply_rope1: {e}')
    print(f'[WAN22] ERRO: apply_rope1 - {e}')

try:
    import comfy.model_management
    print('[WAN22] OK: comfy.model_management')
except Exception as e:
    errors.append(f'model_management: {e}')
    print(f'[WAN22] ERRO: comfy.model_management - {e}')

if errors:
    print('[WAN22] ERROS CRITICOS ENCONTRADOS!')
    sys.exit(1)
else:
    print('[WAN22] Todos os imports OK!')
" 2>&1

# Verificar volume
echo ""
echo "[WAN22] === VOLUME ==="
if [ -d "/runpod-volume" ]; then
    echo "[WAN22] /runpod-volume existe"
    ls -la /runpod-volume/ 2>&1 | head -10

    if [ -d "/runpod-volume/wan22_models" ]; then
        echo "[WAN22] wan22_models encontrado!"
        echo "[WAN22] Criando symlinks..."

        # Criar symlinks
        for dir in diffusion_models loras vae text_encoders clip; do
            if [ -d "/runpod-volume/wan22_models/$dir" ]; then
                ln -sf /runpod-volume/wan22_models/$dir/* /comfyui/models/$dir/ 2>/dev/null || true
                echo "[WAN22] Symlink $dir: OK"
            fi
        done

        # Symlink clip para clip_vision tambem (CLIPVisionLoader usa clip_vision)
        if [ -d "/runpod-volume/wan22_models/clip" ]; then
            ln -sf /runpod-volume/wan22_models/clip/* /comfyui/models/clip_vision/ 2>/dev/null || true
            echo "[WAN22] Symlink clip_vision: OK"
        fi

        # Download CLIP Vision model if not present
        CLIP_MODEL="/comfyui/models/clip_vision/clip_vision_h.safetensors"
        if [ ! -f "$CLIP_MODEL" ]; then
            echo "[WAN22] Downloading clip_vision_h.safetensors..."
            wget -q -O "$CLIP_MODEL" "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/clip_vision_h.safetensors" 2>&1 || \
            curl -sL -o "$CLIP_MODEL" "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/clip_vision_h.safetensors" 2>&1 || \
            echo "[WAN22] AVISO: Falha ao baixar clip_vision_h"
            if [ -f "$CLIP_MODEL" ]; then
                echo "[WAN22] clip_vision_h.safetensors baixado!"
                ls -lh "$CLIP_MODEL"
            fi
        else
            echo "[WAN22] clip_vision_h.safetensors ja existe"
        fi

        echo "[WAN22] === MODELOS DISPONIVEIS ==="
        ls -la /comfyui/models/diffusion_models/ 2>&1 | head -5
        ls -la /comfyui/models/loras/ 2>&1 | head -5
    else
        echo "[WAN22] AVISO: wan22_models NAO encontrado no volume"
        find /runpod-volume -type d -maxdepth 2 2>/dev/null || true
    fi
else
    echo "[WAN22] AVISO: /runpod-volume NAO existe"
fi

# Configurar ambiente
export LD_PRELOAD="$(ldconfig -p | grep -Po 'libtcmalloc.so.\d' | head -n 1)" 2>/dev/null || true

# Iniciar ComfyUI
echo ""
echo "[WAN22] === INICIANDO COMFYUI ==="
cd /comfyui

# Rodar ComfyUI em foreground por 5 segundos para capturar erros iniciais
timeout 10 python main.py --disable-auto-launch --disable-metadata --log-level DEBUG 2>&1 | head -100 &
COMFY_PID=$!
sleep 5

# Agora rodar em background de verdade
pkill -f "python main.py" 2>/dev/null || true
sleep 2

python main.py --disable-auto-launch --disable-metadata --log-level DEBUG &
COMFY_PID=$!
echo "[WAN22] ComfyUI PID: $COMFY_PID"

# Aguardar ComfyUI
echo "[WAN22] Aguardando ComfyUI (max 120s)..."
for i in $(seq 1 120); do
    if ! kill -0 $COMFY_PID 2>/dev/null; then
        echo "[WAN22] ERRO: ComfyUI morreu!"
        wait $COMFY_PID
        EXIT_CODE=$?
        echo "[WAN22] Exit code: $EXIT_CODE"
        exit 1
    fi

    if curl -s http://127.0.0.1:8188 > /dev/null 2>&1; then
        echo "[WAN22] ComfyUI ONLINE apos ${i}s!"
        break
    fi

    if [ $((i % 15)) -eq 0 ]; then
        echo "[WAN22] Ainda aguardando... (${i}s)"
    fi
    sleep 1
done

# Verificar final
if ! curl -s http://127.0.0.1:8188 > /dev/null 2>&1; then
    echo "[WAN22] ERRO: ComfyUI nao iniciou apos 120s!"
    echo "[WAN22] Verificando processo..."
    ps aux | grep -E "python|comfy" | head -10
    exit 1
fi

echo ""
echo "[WAN22] === INICIANDO HANDLER ==="
cd /
exec python -u /handler.py
