#!/bin/bash
# Nao usar set -e para evitar exit prematuro

echo "========================================"
echo "[WAN22] INICIANDO WORKER v4.0"
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

        # Symlink clip para clip_vision tambem
        if [ -d "/runpod-volume/wan22_models/clip" ]; then
            ln -sf /runpod-volume/wan22_models/clip/* /comfyui/models/clip_vision/ 2>/dev/null || true
            echo "[WAN22] Symlink clip_vision: OK"
        fi
    else
        echo "[WAN22] AVISO: wan22_models NAO encontrado"
    fi
else
    echo "[WAN22] AVISO: /runpod-volume NAO existe"
fi

# Download CLIP Vision model se nao existir
echo ""
echo "[WAN22] === CLIP VISION ==="
CLIP_MODEL="/comfyui/models/clip_vision/clip_vision_h.safetensors"
mkdir -p /comfyui/models/clip_vision

if [ ! -f "$CLIP_MODEL" ] || [ ! -s "$CLIP_MODEL" ]; then
    echo "[WAN22] Baixando clip_vision_h.safetensors (~1.1GB)..."
    rm -f "$CLIP_MODEL" 2>/dev/null || true

    # Tentar wget
    if command -v wget >/dev/null 2>&1; then
        echo "[WAN22] Usando wget..."
        wget -q -O "$CLIP_MODEL" "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/clip_vision_h.safetensors"
        if [ -f "$CLIP_MODEL" ] && [ -s "$CLIP_MODEL" ]; then
            echo "[WAN22] wget OK!"
        else
            echo "[WAN22] wget falhou, tentando curl..."
            rm -f "$CLIP_MODEL" 2>/dev/null || true
        fi
    fi

    # Se wget falhou, tentar curl
    if [ ! -f "$CLIP_MODEL" ] || [ ! -s "$CLIP_MODEL" ]; then
        if command -v curl >/dev/null 2>&1; then
            echo "[WAN22] Usando curl..."
            curl -sL -o "$CLIP_MODEL" "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/clip_vision_h.safetensors"
        fi
    fi

    # Verificar resultado
    if [ -f "$CLIP_MODEL" ] && [ -s "$CLIP_MODEL" ]; then
        echo "[WAN22] clip_vision_h.safetensors baixado!"
        ls -lh "$CLIP_MODEL"
    else
        echo "[WAN22] ERRO: Falha ao baixar clip_vision_h.safetensors"
    fi
else
    echo "[WAN22] clip_vision_h.safetensors ja existe"
    ls -lh "$CLIP_MODEL"
fi

echo "[WAN22] Conteudo clip_vision:"
ls -la /comfyui/models/clip_vision/ 2>&1 | head -5

# Iniciar ComfyUI
echo ""
echo "[WAN22] === INICIANDO COMFYUI ==="
cd /comfyui

python main.py --disable-auto-launch --disable-metadata &
COMFY_PID=$!
echo "[WAN22] ComfyUI PID: $COMFY_PID"

# Aguardar ComfyUI
echo "[WAN22] Aguardando ComfyUI (max 180s)..."
for i in $(seq 1 180); do
    if ! kill -0 $COMFY_PID 2>/dev/null; then
        echo "[WAN22] ERRO: ComfyUI morreu!"
        exit 1
    fi

    if curl -s http://127.0.0.1:8188 > /dev/null 2>&1; then
        echo "[WAN22] ComfyUI ONLINE apos ${i}s!"
        break
    fi

    if [ $((i % 30)) -eq 0 ]; then
        echo "[WAN22] Ainda aguardando... (${i}s)"
    fi
    sleep 1
done

# Verificar se ComfyUI iniciou
if ! curl -s http://127.0.0.1:8188 > /dev/null 2>&1; then
    echo "[WAN22] ERRO: ComfyUI nao iniciou!"
    exit 1
fi

echo ""
echo "[WAN22] === INICIANDO HANDLER ==="
cd /
exec python -u /handler.py
