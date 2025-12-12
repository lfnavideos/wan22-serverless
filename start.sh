#!/bin/bash

echo "[WAN22] ============================================"
echo "[WAN22] Iniciando worker..."
echo "[WAN22] ============================================"

# Diagnósticos iniciais
echo "[WAN22] === DIAGNOSTICOS ==="
echo "[WAN22] Python version:"
python --version 2>&1
echo "[WAN22] PyTorch version:"
python -c "import torch; print(f'PyTorch {torch.__version__}, CUDA: {torch.cuda.is_available()}')" 2>&1
echo "[WAN22] ComfyUI path:"
ls -la /comfyui/ 2>&1 | head -5

# Testar imports críticos
echo "[WAN22] === TESTANDO IMPORTS ==="
python -c "
import sys
sys.path.insert(0, '/comfyui')
try:
    from comfy.ldm.flux.math import apply_rope1
    print('[WAN22] OK: apply_rope1 encontrado')
except Exception as e:
    print(f'[WAN22] ERRO apply_rope1: {e}')

try:
    import comfy.model_management
    print('[WAN22] OK: comfy.model_management')
except Exception as e:
    print(f'[WAN22] ERRO model_management: {e}')
" 2>&1

# Verificar volume
echo "[WAN22] === VERIFICANDO VOLUME ==="
echo "[WAN22] Conteudo /runpod-volume:"
ls -la /runpod-volume/ 2>&1 || echo "[WAN22] /runpod-volume nao existe"

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
    echo "[WAN22] Listando /runpod-volume para debug:"
    find /runpod-volume -type d -maxdepth 3 2>/dev/null || echo "Nenhum conteudo"
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

echo "[WAN22] === INICIANDO COMFYUI ==="

# Criar arquivo de log
COMFY_LOG="/tmp/comfyui.log"
touch $COMFY_LOG

# Start ComfyUI in the background, capturando output
if [ "${SERVE_API_LOCALLY}" == "true" ]; then
    python /comfyui/main.py --disable-auto-launch --disable-metadata --listen --log-level "${COMFY_LOG_LEVEL}" > $COMFY_LOG 2>&1 &
else
    python /comfyui/main.py --disable-auto-launch --disable-metadata --log-level "${COMFY_LOG_LEVEL}" > $COMFY_LOG 2>&1 &
fi

COMFY_PID=$!
echo "[WAN22] ComfyUI iniciado com PID: $COMFY_PID"

# Aguardar ComfyUI iniciar
echo "[WAN22] Aguardando ComfyUI ficar online..."
for i in {1..90}; do
    # Verificar se processo ainda existe
    if ! kill -0 $COMFY_PID 2>/dev/null; then
        echo "[WAN22] ERRO: Processo ComfyUI morreu!"
        echo "[WAN22] === ULTIMAS 50 LINHAS DO LOG ==="
        tail -50 $COMFY_LOG
        exit 1
    fi

    if curl -s http://127.0.0.1:8188 > /dev/null 2>&1; then
        echo "[WAN22] ComfyUI esta online! (tentativa $i, ~${i}s)"
        break
    fi

    # Mostrar progresso do log
    if [ $((i % 10)) -eq 0 ]; then
        echo "[WAN22] Aguardando... ($i/90) - Ultimas linhas do log:"
        tail -3 $COMFY_LOG
    fi
    sleep 1
done

# Verificar se ComfyUI está realmente rodando
if ! curl -s http://127.0.0.1:8188 > /dev/null 2>&1; then
    echo "[WAN22] ============================================"
    echo "[WAN22] ERRO: ComfyUI nao iniciou apos 90 segundos!"
    echo "[WAN22] ============================================"
    echo "[WAN22] === LOG COMPLETO ==="
    cat $COMFY_LOG
    echo "[WAN22] === PROCESSOS PYTHON ==="
    ps aux | grep python
    echo "[WAN22] === MEMORIA ==="
    free -h
    echo "[WAN22] === GPU ==="
    nvidia-smi 2>&1 || echo "nvidia-smi nao disponivel"
    exit 1
fi

echo "[WAN22] Iniciando RunPod Handler..."

# Start the RunPod Handler
if [ "${SERVE_API_LOCALLY}" == "true" ]; then
    python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    python -u /handler.py
fi
