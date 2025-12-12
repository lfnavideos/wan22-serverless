# Wan 2.2 I2V + LightX2V Serverless Worker
# Baseado em runpod/worker-comfyui com ComfyUI atualizado
FROM runpod/worker-comfyui:5.6.0-base

# 1. Atualizar pip
RUN python -m pip install --upgrade pip setuptools wheel

# 2. Remover ComfyUI antigo e clonar versao nova (com apply_rope1)
RUN rm -rf /comfyui && \
    git clone https://github.com/comfyanonymous/ComfyUI.git /comfyui && \
    cd /comfyui && \
    pip install --no-cache-dir -r requirements.txt

# 3. Atualizar PyTorch para CUDA 12.1
RUN pip install --no-cache-dir \
    torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# 4. Instalar dependencias do WanVideoWrapper
RUN pip install --no-cache-dir \
    ftfy \
    accelerate>=1.2.1 \
    einops \
    diffusers>=0.33.0 \
    peft>=0.17.0 \
    sentencepiece>=0.2.0 \
    protobuf \
    pyloudnorm \
    gguf>=0.17.1 \
    opencv-python \
    scipy \
    transformers \
    safetensors \
    xformers \
    imageio[ffmpeg] \
    imageio-ffmpeg \
    av \
    ffmpeg-python

# 5. Instalar Custom Nodes
WORKDIR /comfyui/custom_nodes

RUN git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git && \
    cd ComfyUI-WanVideoWrapper && \
    pip install --no-cache-dir -r requirements.txt

RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    cd ComfyUI-VideoHelperSuite && \
    pip install --no-cache-dir -r requirements.txt || true

RUN git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    cd ComfyUI-KJNodes && \
    pip install --no-cache-dir -r requirements.txt || true

# 6. Criar diretorios e symlinks para modelos do volume
# O volume sera montado em /runpod-volume
WORKDIR /comfyui
RUN mkdir -p models/diffusion_models models/loras models/vae models/text_encoders models/clip models/clip_vision

# 7. Criar script que faz symlinks e chama o handler original
RUN echo '#!/bin/bash\n\
echo "[WAN22] Iniciando..."\n\
\n\
# Criar symlinks se o volume existir\n\
if [ -d "/runpod-volume/wan22_models" ]; then\n\
    echo "[WAN22] Criando symlinks para modelos..."\n\
    ln -sf /runpod-volume/wan22_models/diffusion_models/* /comfyui/models/diffusion_models/ 2>/dev/null || true\n\
    ln -sf /runpod-volume/wan22_models/loras/* /comfyui/models/loras/ 2>/dev/null || true\n\
    ln -sf /runpod-volume/wan22_models/vae/* /comfyui/models/vae/ 2>/dev/null || true\n\
    ln -sf /runpod-volume/wan22_models/text_encoders/* /comfyui/models/text_encoders/ 2>/dev/null || true\n\
    ln -sf /runpod-volume/wan22_models/clip/* /comfyui/models/clip/ 2>/dev/null || true\n\
    ls -la /comfyui/models/diffusion_models/\n\
else\n\
    echo "[WAN22] AVISO: Volume nao encontrado"\n\
fi\n\
\n\
# Executar o script original da imagem base\n\
exec /start.sh.original "$@"\n\
' > /start.sh.new && chmod +x /start.sh.new

# 8. Salvar o start.sh original e usar o nosso
RUN if [ -f /start.sh ]; then mv /start.sh /start.sh.original; fi
RUN mv /start.sh.new /start.sh

# 9. Teste de import (sem GPU)
RUN python -c "import sys; sys.path.insert(0, '.'); from comfy.ldm.flux.math import apply_rope1; print('OK: apply_rope1')" || echo "AVISO: apply_rope1 falhou"

CMD ["/start.sh"]
