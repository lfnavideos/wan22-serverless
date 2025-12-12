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

# 7. Copiar script de inicializacao
# Salvar o start.sh original primeiro
RUN if [ -f /start.sh ]; then mv /start.sh /start.sh.original; fi

# 8. Copiar nosso start.sh customizado
COPY start.sh /start.sh
RUN chmod +x /start.sh

# 9. Teste de import (sem GPU)
RUN python -c "import sys; sys.path.insert(0, '.'); from comfy.ldm.flux.math import apply_rope1; print('OK: apply_rope1')" || echo "AVISO: apply_rope1 falhou"

CMD ["/start.sh"]
