# Pantry Recipe Importer — Backend Deployment

Firebase project: `pantry-bfc3d`

## Prerequisites

1. [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installed
2. Logged in: `gcloud auth login`
3. Project set: `gcloud config set project pantry-bfc3d`
4. Cloud Run and Cloud Build APIs enabled (one-time):
   ```
   gcloud services enable run.googleapis.com cloudbuild.googleapis.com
   ```

## Deploy

From the `backend/` directory:

```bash
gcloud run deploy pantry-recipe-importer \
  --source . \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars GEMINI_API_KEY=YOUR_GEMINI_API_KEY_HERE \
  --memory 1Gi \
  --timeout 120
```

- `--allow-unauthenticated` lets the iOS app call it without Firebase Auth tokens. You can lock this down later.
- `--memory 1Gi` is needed for yt-dlp + ffmpeg to handle video buffers.
- `--timeout 120` gives the pipeline enough time to download + process.

After deploy, you'll get a URL like:
```
https://pantry-recipe-importer-xxxxxxxxxx-uc.a.run.app
```

Copy that URL — you'll need it in the iOS app.

## Test It

```bash
curl -X POST https://YOUR-CLOUD-RUN-URL/import \
  -H "Content-Type: application/json" \
  -d '{"url": "https://www.tiktok.com/@user/video/123456789"}'
```

## Update yt-dlp (when Instagram/TikTok break it)

Bump the version in `requirements.txt` and redeploy:
```bash
pip index versions yt-dlp   # check latest version
# update requirements.txt, then:
gcloud run deploy pantry-recipe-importer --source . --region us-central1
```

## Environment Variables

| Variable | Description |
|---|---|
| `GEMINI_API_KEY` | Your Gemini API key from Google AI Studio |
| `PORT` | Set automatically by Cloud Run (don't override) |
