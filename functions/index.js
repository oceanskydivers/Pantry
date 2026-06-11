const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();

const db = getFirestore();

// TODO: Replace with actual App Store ID once the app is published
const APP_STORE_URL = "https://apps.apple.com/app/id6475992011";

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function renderPage({ title, description, imageUrl, recipeId }) {
  const safeTitle = escapeHtml(title);
  const safeDesc = escapeHtml(description);
  const canonicalUrl = `https://pantrymanager.app/recipe/${recipeId}`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${safeTitle} — Pantry</title>

  <!-- Open Graph / iMessage / Facebook -->
  <meta property="og:type" content="article" />
  <meta property="og:title" content="${safeTitle}" />
  <meta property="og:description" content="${safeDesc}" />
  <meta property="og:url" content="${canonicalUrl}" />
  <meta property="og:site_name" content="Pantry" />
  ${imageUrl ? `<meta property="og:image" content="${imageUrl}" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />` : ""}

  <!-- Twitter Card -->
  <meta name="twitter:card" content="${imageUrl ? "summary_large_image" : "summary"}" />
  <meta name="twitter:title" content="${safeTitle}" />
  <meta name="twitter:description" content="${safeDesc}" />
  ${imageUrl ? `<meta name="twitter:image" content="${imageUrl}" />` : ""}

  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      background: linear-gradient(160deg, #f0f4ff 0%, #e8f5ee 100%);
      padding: 20px;
    }
    .card {
      background: white;
      border-radius: 24px;
      padding: 0;
      max-width: 420px;
      width: 100%;
      box-shadow: 0 8px 40px rgba(0, 0, 0, 0.10);
      overflow: hidden;
      text-align: center;
    }
    .recipe-img {
      width: 100%;
      height: 240px;
      object-fit: cover;
      display: block;
    }
    .content {
      padding: 28px 28px 32px;
    }
    .label {
      font-size: 0.75rem;
      font-weight: 600;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: #86AC78;
      margin-bottom: 8px;
    }
    h1 {
      font-size: 1.5rem;
      font-weight: 700;
      color: #1d1d1f;
      margin-bottom: 8px;
      line-height: 1.3;
    }
    .meta {
      color: #6e6e73;
      font-size: 0.95rem;
      margin-bottom: 28px;
    }
    .btn {
      display: block;
      background: #86AC78;
      color: white;
      text-decoration: none;
      padding: 16px 24px;
      border-radius: 14px;
      font-weight: 600;
      font-size: 1rem;
      transition: background 0.15s;
    }
    .btn:hover { background: #2d9448; }
    .sub {
      margin-top: 14px;
      color: #aeaeb2;
      font-size: 0.8rem;
    }
    .no-img-icon {
      font-size: 3rem;
      padding: 32px 0 0;
    }
  </style>
</head>
<body>
  <div class="card">
    ${imageUrl
      ? `<img class="recipe-img" src="${imageUrl}" alt="${safeTitle}" />`
      : `<div class="no-img-icon">🍽️</div>`
    }
    <div class="content">
      <p class="label">Shared via Pantry</p>
      <h1>${safeTitle}</h1>
      <p class="meta">${safeDesc}</p>
      <a class="btn" href="${APP_STORE_URL}">Open in Pantry</a>
      <p class="sub">Don't have Pantry? Download it free on the App Store.</p>
    </div>
  </div>
</body>
</html>`;
}

exports.recipeShare = onRequest({ region: "us-central1" }, async (req, res) => {
  // Path is /recipe/{uuid} — extract the last segment
  const parts = req.path.split("/").filter(Boolean);
  const recipeId = parts[parts.length - 1];

  // Validate UUID format
  if (!recipeId || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(recipeId)) {
    return res.status(404).send(renderPage({
      title: "Recipe Not Found",
      description: "This link doesn't look right. Try opening it from the Pantry app.",
      imageUrl: null,
      recipeId: "",
    }));
  }

  try {
    const doc = await db.collection("sharedRecipes").doc(recipeId).get();

    if (!doc.exists) {
      return res.status(404).send(renderPage({
        title: "Recipe Not Found",
        description: "This recipe may have been deleted or is no longer shared.",
        imageUrl: null,
        recipeId,
      }));
    }

    const data = doc.data();
    const name = data.name || "Shared Recipe";
    const servings = data.servings || 4;
    const count = data.ingredientCount || 0;
    const description = `${count} ingredient${count !== 1 ? "s" : ""} · Serves ${Math.round(servings)}`;
    const imageUrl = data.imagePublicUrl || null;

    res.set("Cache-Control", "public, max-age=300, s-maxage=300");
    return res.send(renderPage({ title: name, description, imageUrl, recipeId }));
  } catch (err) {
    console.error("recipeShare error:", err);
    return res.status(500).send("Something went wrong. Please try again.");
  }
});
