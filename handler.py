# -*- coding: utf-8 -*-
"""
Custom Handler for Wan 2.2 + LightX2V
Extends base handler to support video outputs
"""

import os
import time
import json
import base64
import glob
import runpod
from runpod.serverless.utils import rp_upload

# Import from base worker-comfyui
import sys
sys.path.insert(0, '/src')
try:
    from handler import ComfyUI, process_output_images
except ImportError:
    # Fallback for local testing
    pass

COMFY_OUTPUT_PATH = os.environ.get('COMFY_OUTPUT_PATH', '/comfyui/output')

def get_video_files(output_path, start_time):
    """Scan output folder for video files created after start_time"""
    video_extensions = ['.mp4', '.webm', '.mov', '.avi', '.mkv', '.gif']
    videos = []

    for ext in video_extensions:
        pattern = os.path.join(output_path, f'*{ext}')
        for filepath in glob.glob(pattern):
            if os.path.getmtime(filepath) > start_time:
                videos.append(filepath)

    # Also check subdirectories
    for ext in video_extensions:
        pattern = os.path.join(output_path, '**', f'*{ext}')
        for filepath in glob.glob(pattern, recursive=True):
            if os.path.getmtime(filepath) > start_time:
                if filepath not in videos:
                    videos.append(filepath)

    return sorted(videos, key=os.path.getmtime)


def upload_video(filepath, job_id):
    """Upload video to S3 or return as base64"""
    bucket_endpoint = os.environ.get('BUCKET_ENDPOINT_URL')

    if bucket_endpoint:
        # Use S3 upload
        try:
            filename = os.path.basename(filepath)
            s3_url = rp_upload.upload_file_to_bucket(
                file_path=filepath,
                bucket_name='',  # Extracted from endpoint URL
                prefix=job_id
            )
            return {'type': 's3_url', 'filename': filename, 'data': s3_url}
        except Exception as e:
            print(f"[HANDLER] S3 upload failed: {e}, falling back to base64")

    # Fallback to base64
    with open(filepath, 'rb') as f:
        video_data = f.read()

    # Check size limit (20MB for runsync)
    if len(video_data) > 15 * 1024 * 1024:
        return {'type': 'error', 'filename': os.path.basename(filepath),
                'data': f'Video too large ({len(video_data)/1024/1024:.1f}MB). Configure S3 upload.'}

    return {
        'type': 'base64',
        'filename': os.path.basename(filepath),
        'data': base64.b64encode(video_data).decode('utf-8')
    }


def handler(event):
    """
    Main handler function
    """
    job_id = event.get('id', 'unknown')
    job_input = event.get('input', {})

    print(f"[HANDLER] Job {job_id} started")

    # Record start time for video detection
    start_time = time.time()

    # Try to use the base ComfyUI handler
    try:
        # Check for workflow in input
        workflow = job_input.get('workflow')
        if not workflow:
            return {'error': 'No workflow provided'}

        # Import and use base handler components
        from comfy_runner import ComfyRunner
        runner = ComfyRunner()

        # Process images if present
        images = job_input.get('images', [])
        if images:
            for img in images:
                name = img.get('name', 'INPUT_IMAGE')
                img_data = img.get('image', '')
                if img_data:
                    # Decode and save image
                    img_bytes = base64.b64decode(img_data)
                    img_path = f'/comfyui/input/{name}.png'
                    os.makedirs(os.path.dirname(img_path), exist_ok=True)
                    with open(img_path, 'wb') as f:
                        f.write(img_bytes)
                    print(f"[HANDLER] Saved input image: {img_path}")

        # Run workflow
        result = runner.run_workflow(workflow)

        # Wait a moment for file system
        time.sleep(1)

        # Get video files
        videos = get_video_files(COMFY_OUTPUT_PATH, start_time)
        print(f"[HANDLER] Found {len(videos)} video files")

        # Process videos
        video_outputs = []
        for video_path in videos:
            video_output = upload_video(video_path, job_id)
            video_outputs.append(video_output)
            print(f"[HANDLER] Processed video: {video_path}")

        # Combine with images from base handler
        output = {
            'status': 'success',
            'images': result.get('images', []) if result else [],
            'videos': video_outputs
        }

        # For backward compatibility, add video as 'video' key too
        if video_outputs:
            output['video'] = video_outputs[0].get('data')

        return output

    except ImportError as e:
        print(f"[HANDLER] Import error: {e}")
        # If base handler not available, use simplified version
        return handler_simple(event, start_time, job_id)
    except Exception as e:
        import traceback
        print(f"[HANDLER] Error: {e}")
        print(traceback.format_exc())
        return {'error': str(e), 'status': 'FAILED'}


def handler_simple(event, start_time, job_id):
    """
    Simplified handler that works with the base worker-comfyui
    Just adds video scanning to the output
    """
    import requests

    job_input = event.get('input', {})
    workflow = job_input.get('workflow')
    images = job_input.get('images', [])

    # Save input images
    for img in images:
        name = img.get('name', 'INPUT_IMAGE')
        img_data = img.get('image', '')
        if img_data:
            img_bytes = base64.b64decode(img_data)
            img_path = f'/comfyui/input/{name}.png'
            os.makedirs(os.path.dirname(img_path), exist_ok=True)
            with open(img_path, 'wb') as f:
                f.write(img_bytes)

    # Queue workflow via ComfyUI API
    comfy_url = os.environ.get('COMFY_API_URL', 'http://127.0.0.1:8188')

    # Queue prompt
    response = requests.post(f'{comfy_url}/prompt', json={'prompt': workflow}, timeout=30)
    if response.status_code != 200:
        return {'error': f'Failed to queue workflow: {response.text}', 'status': 'FAILED'}

    prompt_id = response.json().get('prompt_id')
    print(f"[HANDLER] Queued prompt: {prompt_id}")

    # Wait for completion
    max_wait = 600
    waited = 0
    while waited < max_wait:
        time.sleep(5)
        waited += 5

        # Check history
        hist = requests.get(f'{comfy_url}/history/{prompt_id}', timeout=30).json()
        if prompt_id in hist:
            outputs = hist[prompt_id].get('outputs', {})
            status = hist[prompt_id].get('status', {})

            if status.get('status_str') == 'error':
                return {
                    'error': status.get('messages', 'Unknown error'),
                    'status': 'FAILED'
                }

            if outputs:
                break

        print(f"[HANDLER] Waiting... ({waited}s)")

    # Get video files
    time.sleep(1)
    videos = get_video_files(COMFY_OUTPUT_PATH, start_time)
    print(f"[HANDLER] Found {len(videos)} video files")

    # Process videos
    video_outputs = []
    for video_path in videos:
        video_output = upload_video(video_path, job_id)
        video_outputs.append(video_output)

    output = {
        'status': 'success',
        'images': [],
        'videos': video_outputs
    }

    if video_outputs:
        output['video'] = video_outputs[0].get('data')

    return output


# RunPod serverless entry point
runpod.serverless.start({'handler': handler})
