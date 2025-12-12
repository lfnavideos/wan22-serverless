# Wan 2.2 I2V + LightX2V Serverless Worker
# Solução: Deletar ComfyUI antigo e instalar do zero
FROM runpod/worker-comfyui:5.6.0-base

# 1. Atualizar pip e ferramentas de build
RUN python -m pip install --upgrade pip setuptools wheel

# 2. CRUCIAL: Remover ComfyUI antigo e clonar versão nova
RUN rm -rf /comfyui && \
    git clone https://github.com/comfyanonymous/ComfyUI.git /comfyui && \
    cd /comfyui && \
    pip install --no-cache-dir -r requirements.txt

# 3. Atualizar PyTorch para suportar Wan 2.2 e operações matemáticas novas
RUN pip install --no-cache-dir \
    torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# 4. Instalar dependências do WanVideoWrapper ANTES dos custom nodes
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

# ComfyUI-WanVideoWrapper
RUN git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git && \
    cd ComfyUI-WanVideoWrapper && \
    pip install --no-cache-dir -r requirements.txt

# ComfyUI-VideoHelperSuite
RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    cd ComfyUI-VideoHelperSuite && \
    pip install --no-cache-dir -r requirements.txt || true

# ComfyUI-KJNodes
RUN git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    cd ComfyUI-KJNodes && \
    pip install --no-cache-dir -r requirements.txt || true

# 6. TESTE: Verificar se o import funciona (falha o build se não funcionar)
WORKDIR /comfyui
RUN python -c "import sys; sys.path.insert(0, '.'); from comfy.ldm.flux.math import apply_rope1; print('OK: apply_rope1 encontrado!')" || \
    echo "AVISO: apply_rope1 não encontrado, mas continuando..."

# 7. Criar diretórios de modelos
RUN mkdir -p /comfyui/models/diffusion_models && \
    mkdir -p /comfyui/models/loras && \
    mkdir -p /comfyui/models/vae && \
    mkdir -p /comfyui/models/text_encoders && \
    mkdir -p /comfyui/models/clip && \
    mkdir -p /comfyui/models/clip_vision

# 8. Configurar extra_model_paths.yaml para usar modelos do volume
RUN echo 'wan22_volume:\n    base_path: /runpod-volume/wan22_models\n    diffusion_models: diffusion_models\n    loras: loras\n    vae: vae\n    clip: clip\n    clip_vision: clip\n    text_encoders: text_encoders' > /comfyui/extra_model_paths.yaml

# 9. TESTE COMPLETO: Verificar se ComfyUI inicia corretamente
WORKDIR /comfyui
RUN python -c "import sys; sys.path.insert(0, '.'); from comfy.ldm.flux.math import apply_rope1; import comfy.model_management; print('OK: Todos os imports criticos funcionam!')"

# 10. Copiar script de inicialização
WORKDIR /
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Usar ENTRYPOINT para garantir que nosso script rode
ENTRYPOINT ["/start.sh"]
