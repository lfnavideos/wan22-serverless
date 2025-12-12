# Wan 2.2 I2V + LightX2V Serverless Worker
# Base: RunPod ComfyUI Worker
FROM runpod/worker-comfyui:5.6.0-base

# Update ComfyUI to latest version for compatibility with custom nodes
RUN cd /comfyui && \
    git fetch origin && \
    git checkout master && \
    git pull origin master && \
    pip install --no-cache-dir -r requirements.txt

# Install WanVideoWrapper dependencies FIRST
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
    imageio[ffmpeg] \
    imageio-ffmpeg \
    av \
    ffmpeg-python

# Install ComfyUI-WanVideoWrapper
RUN cd /comfyui/custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git

# Install ComfyUI-VideoHelperSuite for video output
RUN cd /comfyui/custom_nodes && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    cd ComfyUI-VideoHelperSuite && \
    pip install --no-cache-dir -r requirements.txt || true

# Install ComfyUI-KJNodes for image resize
RUN cd /comfyui/custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    cd ComfyUI-KJNodes && \
    pip install --no-cache-dir -r requirements.txt || true

# Set environment variables for model paths
ENV COMFY_MODEL_PATH=/runpod-volume/wan22_models

# Create model directories
RUN mkdir -p /comfyui/models/diffusion_models && \
    mkdir -p /comfyui/models/loras && \
    mkdir -p /comfyui/models/vae && \
    mkdir -p /comfyui/models/text_encoders && \
    mkdir -p /comfyui/models/clip && \
    mkdir -p /comfyui/models/clip_vision

# Copy startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]
