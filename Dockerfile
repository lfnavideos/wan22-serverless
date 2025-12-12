# Wan 2.2 I2V + LightX2V Serverless Worker
# Base: RunPod ComfyUI Worker
FROM runpod/worker-comfyui:5.6.0-base

# Install ComfyUI-WanVideoWrapper using comfy-node-install (recommended method)
RUN comfy-node-install comfyui-wanvideowrapper

# Install ComfyUI-VideoHelperSuite for video output
RUN comfy-node-install comfyui-videohelper

# Install ComfyUI-KJNodes for image resize
RUN comfy-node-install comfyui-kjnodes

# Install additional dependencies that may be missing
RUN pip install --no-cache-dir \
    imageio[ffmpeg] \
    imageio-ffmpeg \
    av \
    ffmpeg-python

# Set environment variables for model paths
ENV COMFY_MODEL_PATH=/runpod-volume/wan22_models

# Create model directories if they don't exist
RUN mkdir -p /comfyui/models/diffusion_models && \
    mkdir -p /comfyui/models/loras && \
    mkdir -p /comfyui/models/vae && \
    mkdir -p /comfyui/models/text_encoders && \
    mkdir -p /comfyui/models/clip

# Copy startup script that creates symlinks
COPY start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]
