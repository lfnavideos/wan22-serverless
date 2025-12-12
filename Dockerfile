# Wan 2.2 I2V + LightX2V Serverless Worker
# Base: RunPod ComfyUI Worker
FROM runpod/worker-comfyui:5.6.0-base

# Update ComfyUI to latest version for compatibility
RUN cd /comfyui && \
    git fetch origin && \
    git reset --hard origin/master

# Install ComfyUI-WanVideoWrapper from git
RUN cd /comfyui/custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git && \
    cd ComfyUI-WanVideoWrapper && \
    pip install --no-cache-dir -r requirements.txt

# Install ComfyUI-VideoHelperSuite for video output
RUN cd /comfyui/custom_nodes && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    cd ComfyUI-VideoHelperSuite && \
    pip install --no-cache-dir -r requirements.txt

# Install ComfyUI-KJNodes for image resize
RUN cd /comfyui/custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    cd ComfyUI-KJNodes && \
    pip install --no-cache-dir -r requirements.txt

# Install additional dependencies
RUN pip install --no-cache-dir \
    imageio[ffmpeg] \
    imageio-ffmpeg \
    av \
    ffmpeg-python

# Set environment variables for model paths
ENV COMFY_MODEL_PATH=/runpod-volume/wan22_models

# Create model directories
RUN mkdir -p /comfyui/models/diffusion_models && \
    mkdir -p /comfyui/models/loras && \
    mkdir -p /comfyui/models/vae && \
    mkdir -p /comfyui/models/text_encoders && \
    mkdir -p /comfyui/models/clip

# Copy startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]
