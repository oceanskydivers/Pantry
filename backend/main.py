"""
Pantry Recipe Importer — Cloud Run backend
Accepts a social media URL (TikTok, Instagram, YouTube, etc.),
fetches both the caption and audio in parallel, then asks Gemini
to merge them into the best possible recipe.
"""

import os
import json
import tempfile
import subprocess
import logging
import re
import atexit
import concurrent.futures

import google.generativeai as genai
from google.cloud import secretmanager
from flask import Flask, request, jsonify

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

app = Flask(__name__)

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "pantry-bfc3d")

genai.configure(api_key=GEMINI_API_KEY)
model = genai.GenerativeModel("gemini-2.5-flash")

SOCIAL_DOMAINS = {"tiktok.com", "instagram.com", "youtube.com", "youtu.be", "reels"}

_COOKIES_FILE = None


def load_cookies():
    global _COOKIES_FILE
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{PROJECT_ID}/secrets/yt-dlp-cookies/versions/latest"
        response = client.access_secret_version(request={"name": name})
        cookie_data = response.payload.data.decode("utf-8")
        tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tmp.write(cookie_data)
        tmp.flush()
        tmp.close()
        _COOKIES_FILE = tmp.name
        log.info("Cookies loaded from Secret Manager -> %s", _COOKIES_FILE)
    except Exception as e:
        log.warning("Could not load cookies from Secret Manager: %s", e)
        _COOKIES_FILE = None


def cleanup_cookies():
    if _COOKIES_FILE and os.path.exists(_COOKIES_FILE):
        os.unlink(_COOKIES_FILE)


atexit.register(cleanup_cookies)
load_cookies()


def is_social_url(url: str) -> bool:
    return any(domain in url for domain in SOCIAL_DOMAINS)


def base_yt_dlp_cmd() -> list:
    cmd = ["yt-dlp", "--no-playlist"]
    if _COOKIES_FILE:
        cmd += ["--cookies", _COOKIES_FILE]
    return cmd


def fetch_caption(url: str) -> str | None:
    """Fetch post caption/description without downloading video."""
    cmd = base_yt_dlp_cmd() + [
        "--skip-download",
        "--print", "%(description)s",
        url,
    ]
    log.info("Fetching caption for %s", url)
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        log.warning("Caption fetch failed: %s", result.stderr.strip())
        return None
    caption = result.stdout.strip()
    if not caption or caption == "NA":
        return None
    log.info("Caption fetched (%d chars)", len(caption))
    return caption


def download_audio(url: str, out_dir: str) -> str:
    """Download audio track only."""
    out_template = os.path.join(out_dir, "audio.%(ext)s")
    cmd = base_yt_dlp_cmd() + [
        "--extract-audio",
        "--audio-format", "mp3",
        "--audio-quality", "5",
        "--max-filesize", "50m",
        "--output", out_template,
        url,
    ]
    log.info("Downloading audio for %s", url)
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        raise RuntimeError(f"yt-dlp failed: {result.stderr.strip()}")
    for fname in os.listdir(out_dir):
        if fname.startswith("audio."):
            return os.path.join(out_dir, fname)
    raise RuntimeError("yt-dlp completed but no audio file found.")


MERGE_PROMPT = """
You are a recipe extraction assistant. You have two sources from the same cooking video:

SOURCE 1 - Caption/Description (written text, often has accurate ingredient measurements):
{caption}

SOURCE 2 - Audio Transcription (spoken words, often has detailed cooking instructions):
{audio_text}

Combine both sources to produce the most complete and accurate recipe possible.
- Prefer caption measurements for ingredients (they tend to be more precise)
- Prefer audio content for instructions (more detail is spoken than written)
- If a field is only in one source, use that source
- Return ONLY a JSON object with this exact structure:

{{
  "name": "Recipe name",
  "servings": 4,
  "ingredients": [
    {{"name": "flour", "amount": 2.0, "unit": "cups"}},
    {{"name": "salt", "amount": 1.0, "unit": "tsp"}}
  ],
  "instructions": [
    "Step one description",
    "Step two description"
  ],
  "notes": "Any extra tips or notes"
}}

Rules:
- If neither source contains a recipe, return {{"error": "No recipe found in this content"}}
- Amount should be a number (0 if unspecified)
- Unit should be a standard cooking unit or empty string if none
- Do not include any text outside the JSON object
"""

SINGLE_SOURCE_PROMPT = """
You are a recipe extraction assistant. The following is content from a cooking video.

Extract the recipe and return ONLY a JSON object with this exact structure:
{{
  "name": "Recipe name",
  "servings": 4,
  "ingredients": [
    {{"name": "flour", "amount": 2.0, "unit": "cups"}},
    {{"name": "salt", "amount": 1.0, "unit": "tsp"}}
  ],
  "instructions": [
    "Step one description",
    "Step two description"
  ],
  "notes": "Any extra tips or notes"
}}

Rules:
- If no recipe is present, return {{"error": "No recipe found in this content"}}
- Amount should be a number (0 if unspecified)
- Unit should be a standard cooking unit or empty string if none
- Do not include any text outside the JSON object

Content:
{content}
"""


def parse_gemini_response(raw: str) -> dict:
    raw = raw.strip()
    raw = re.sub(r"^```(?:json)?\s*", "", raw)
    raw = re.sub(r"\s*```$", "", raw)
    return json.loads(raw)


def extract_recipe_merged(caption: str, audio_path: str) -> dict:
    """Upload audio to Gemini along with caption and ask it to merge both."""
    log.info("Merging caption + audio via Gemini")
    audio_file = genai.upload_file(audio_path, mime_type="audio/mpeg")

    prompt = f"""
You are a recipe extraction assistant. You have two sources from the same cooking video:

SOURCE 1 - Caption/Description (written text, often has accurate ingredient measurements):
{caption}

SOURCE 2 - The audio from the video (spoken words, often has detailed cooking instructions):
(see attached audio file)

Combine both sources to produce the most complete and accurate recipe possible.
- Prefer caption measurements for ingredients (they tend to be more precise)
- Prefer audio content for instructions (more detail is spoken than written)
- If a field is only in one source, use that source
- Return ONLY a JSON object with this exact structure:

{{
  "name": "Recipe name",
  "servings": 4,
  "ingredients": [
    {{"name": "flour", "amount": 2.0, "unit": "cups"}},
    {{"name": "salt", "amount": 1.0, "unit": "tsp"}}
  ],
  "instructions": [
    "Step one description",
    "Step two description"
  ],
  "notes": "Any extra tips or notes"
}}

Rules:
- If neither source contains a recipe, return {{"error": "No recipe found in this content"}}
- Amount should be a number (0 if unspecified)
- Unit should be a standard cooking unit or empty string if none
- Do not include any text outside the JSON object
"""

    response = model.generate_content(
        [prompt, audio_file],
        generation_config=genai.GenerationConfig(
            response_mime_type="application/json"
        )
    )
    return parse_gemini_response(response.text)


def extract_recipe_from_audio_only(audio_path: str) -> dict:
    """Extract recipe from audio only (no caption available)."""
    log.info("Extracting recipe from audio only")
    audio_file = genai.upload_file(audio_path, mime_type="audio/mpeg")
    prompt = SINGLE_SOURCE_PROMPT.format(content="(see attached audio file)")
    response = model.generate_content(
        [prompt, audio_file],
        generation_config=genai.GenerationConfig(
            response_mime_type="application/json"
        )
    )
    return parse_gemini_response(response.text)


def extract_recipe_from_text(text: str) -> dict:
    """Extract recipe from text only."""
    prompt = SINGLE_SOURCE_PROMPT.format(content=text)
    response = model.generate_content(
        [prompt],
        generation_config=genai.GenerationConfig(
            response_mime_type="application/json"
        )
    )
    return parse_gemini_response(response.text)


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "cookies_loaded": _COOKIES_FILE is not None})


@app.route("/import", methods=["POST"])
def import_recipe():
    """
    POST /import
    Body: { "url": "https://www.tiktok.com/..." }
    Returns: ImportedRecipe JSON or { "error": "..." }
    """
    body = request.get_json(silent=True) or {}
    url = (body.get("url") or "").strip()

    if not url:
        return jsonify({"error": "Missing 'url' in request body."}), 400
    if not GEMINI_API_KEY:
        return jsonify({"error": "Server not configured: missing GEMINI_API_KEY."}), 500

    try:
        if is_social_url(url):
            with tempfile.TemporaryDirectory() as tmp:
                # Fetch caption and download audio in parallel
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
                    caption_future = executor.submit(fetch_caption, url)
                    audio_future = executor.submit(download_audio, url, tmp)

                    caption = caption_future.result()
                    try:
                        audio_path = audio_future.result()
                    except RuntimeError as e:
                        # Audio failed — fall back to caption only
                        log.warning("Audio download failed, using caption only: %s", e)
                        audio_path = None

                if audio_path and caption:
                    log.info("Both caption and audio available — merging")
                    recipe = extract_recipe_merged(caption, audio_path)
                elif audio_path:
                    log.info("Audio only")
                    recipe = extract_recipe_from_audio_only(audio_path)
                elif caption:
                    log.info("Caption only")
                    recipe = extract_recipe_from_text(caption)
                else:
                    return jsonify({"error": "Could not retrieve content from this URL."}), 502
        else:
            recipe = extract_recipe_from_text(url)

        if "error" in recipe:
            return jsonify({"error": recipe["error"]}), 422

        return jsonify(recipe)

    except subprocess.TimeoutExpired:
        return jsonify({"error": "Download timed out. The video may be too long."}), 408
    except RuntimeError as e:
        log.exception("yt-dlp error")
        return jsonify({"error": str(e)}), 502
    except json.JSONDecodeError:
        log.exception("Failed to parse Gemini response as JSON")
        return jsonify({"error": "Could not parse recipe from video."}), 500
    except Exception as e:
        log.exception("Unexpected error")
        return jsonify({"error": f"Unexpected error: {str(e)}"}), 500


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
