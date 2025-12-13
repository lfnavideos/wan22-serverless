# -*- coding: utf-8 -*-
"""
Custom Handler for Wan 2.2 + LightX2V
Supports video outputs from ComfyUI VHS_VideoCombine node
"""

import os
import time
import json
import base64
import glob
import requests
import runpod

COMFY_OUTPUT_PATH = os.environ.get('COMFY_OUTPUT_PATH', '/comfyui/output')
COMFY_API_URL = os.environ.get('COMFY_API_URL', 'http://127.0.0.1:8188')


def wait_for_comfyui(timeout=120):
    """Wait for ComfyUI to be ready"""
    start = time.time()
    while time.time() - start < timeout:
        try:
            r = requests.get(f'{COMFY_API_URL}/system_stats', timeout=5)
            if r.status_code == 200:
                print(f"[HANDLER] ComfyUI ready after {int(time.time()-start)}s")
                return True
        except:
            pass
        time.sleep(2)
    return False


def get_video_files(output_path, start_time):
    """Scan output folder for video files created after start_time"""
    video_extensions = ['.mp4', '.webm', '.mov', '.avi', '.mkv', '.gif']
    videos = []

    for ext in video_extensions:
        pattern = os.path.join(output_path, f'*{ext}')
        for filepath in glob.glob(pattern):
            try:
                if os.path.getmtime(filepath) > start_time:
                    videos.append(filepath)
            except:
                pass

    # Also check subdirectories
    for ext in video_extensions:
        pattern = os.path.join(output_path, '**', f'*{ext}')
        for filepath in glob.glob(pattern, recursive=True):
            try:
                if os.path.getmtime(filepath) > start_time:
                    if filepath not in videos:
                        videos.append(filepath)
            except:
                pass

    return sorted(videos, key=lambda x: os.path.getmtime(x))


def upload_video(filepath, job_id):
    """Return video as base64"""
    try:
        with open(filepath, 'rb') as f:
            video_data = f.read()

        # Check size limit (15MB to be safe)
        if len(video_data) > 15 * 1024 * 1024:
            return {
                'type': 'error',
                'filename': os.path.basename(filepath),
                'data': f'Video too large ({len(video_data)/1024/1024:.1f}MB)'
            }

        return {
            'type': 'base64',
            'filename': os.path.basename(filepath),
            'data': base64.b64encode(video_data).decode('utf-8')
        }
    except Exception as e:
        return {'type': 'error', 'filename': os.path.basename(filepath), 'data': str(e)}


def handler(event):
    """Main handler function"""
    job_id = event.get('id', 'unknown')
    job_input = event.get('input', {})

    print(f"[HANDLER] Job {job_id} started")

    # Record start time for video detection
    start_time = time.time()

    # Get workflow
    workflow = job_input.get('workflow')
    if not workflow:
        return {'error': 'No workflow provided', 'status': 'FAILED'}

    images = job_input.get('images', [])

    # Wait for ComfyUI to be ready
    if not wait_for_comfyui(timeout=120):
        return {'error': 'ComfyUI not ready after 120s', 'status': 'FAILED'}

    # Save input images
    for img in images:
        name = img.get('name', 'INPUT_IMAGE')
        img_data = img.get('image', '')
        if img_data:
            try:
                img_bytes = base64.b64decode(img_data)
                img_path = f'/comfyui/input/{name}.png'
                os.makedirs(os.path.dirname(img_path), exist_ok=True)
                with open(img_path, 'wb') as f:
                    f.write(img_bytes)
                print(f"[HANDLER] Saved: {img_path}")
            except Exception as e:
                print(f"[HANDLER] Error saving image: {e}")

    # Queue workflow via ComfyUI API
    try:
        response = requests.post(
            f'{COMFY_API_URL}/prompt',
            json={'prompt': workflow},
            timeout=30
        )
        if response.status_code != 200:
            return {
                'error': f'Failed to queue workflow: {response.text}',
                'status': 'FAILED'
            }
        prompt_id = response.json().get('prompt_id')
        print(f"[HANDLER] Queued: {prompt_id}")
    except Exception as e:
        return {'error': f'Failed to connect to ComfyUI: {e}', 'status': 'FAILED'}

    # Wait for completion
    max_wait = 600
    waited = 0
    completed = False

    while waited < max_wait:
        time.sleep(5)
        waited += 5

        try:
            hist = requests.get(
                f'{COMFY_API_URL}/history/{prompt_id}',
                timeout=30
            ).json()

            if prompt_id in hist:
                status_info = hist[prompt_id].get('status', {})
                status_str = status_info.get('status_str', '')

                if status_str == 'error':
                    messages = status_info.get('messages', [])
                    error_msg = str(messages) if messages else 'Unknown error'
                    return {'error': error_msg, 'status': 'FAILED'}

                if hist[prompt_id].get('outputs'):
                    completed = True
                    print(f"[HANDLER] Completed in {waited}s")
                    break
        except Exception as e:
            print(f"[HANDLER] Error checking status: {e}")

        if waited % 30 == 0:
            print(f"[HANDLER] Waiting... ({waited}s)")

    if not completed:
        return {'error': f'Timeout after {max_wait}s', 'status': 'FAILED'}

    # Wait for file system
    time.sleep(2)

    # Get video files
    videos = get_video_files(COMFY_OUTPUT_PATH, start_time)
    print(f"[HANDLER] Found {len(videos)} video(s)")

    # Process videos
    video_outputs = []
    for video_path in videos:
        video_output = upload_video(video_path, job_id)
        video_outputs.append(video_output)
        print(f"[HANDLER] Processed: {video_path}")

    if not video_outputs:
        return {
            'error': 'Workflow completed but no video found',
            'status': 'FAILED',
            'details': f'Searched in {COMFY_OUTPUT_PATH}'
        }

    output = {
        'status': 'success',
        'images': [],
        'videos': video_outputs
    }

    # Add first video as 'video' for backward compatibility
    if video_outputs and video_outputs[0].get('type') == 'base64':
        output['video'] = video_outputs[0].get('data')

    return output


# RunPod serverless entry point
runpod.serverless.start({'handler': handler})
