# Wan 2.2 I2V + LightX2V Serverless Worker
# Base: RunPod ComfyUI Worker
FROM runpod/worker-comfyui:5.6.0-base

# Install ComfyUI-WanVideoWrapper and dependencies
RUN cd /comfyui/custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git && \
    cd ComfyUI-WanVideoWrapper && \
    pip install -r requirements.txt

# Install ComfyUI-VideoHelperSuite for video output
RUN cd /comfyui/custom_nodes && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    cd ComfyUI-VideoHelperSuite && \
    pip install -r requirements.txt

# Install additional dependencies
RUN pip install --no-cache-dir \
    imageio[ffmpeg] \
    imageio-ffmpeg \
    av

# Set environment variables for model paths
ENV COMFY_MODEL_PATH=/runpod-volume/wan22_models

# Create symlinks for models (will be linked to volume at runtime)
RUN mkdir -p /comfyui/models/diffusion_models && \
    mkdir -p /comfyui/models/loras && \
    mkdir -p /comfyui/models/vae && \
    mkdir -p /comfyui/models/text_encoders && \
    mkdir -p /comfyui/models/clip

# Copy startup script that creates symlinks
COPY start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]
