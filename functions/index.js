const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();

const db = getFirestore();

// TODO: Replace with actual App Store ID once the app is published
const APP_STORE_URL = "https://apps.apple.com/app/id6475992011";

const i18n = {
  en: {
    lang: "en",
    sharedViaPantry: "Shared via Pantry",
    openInPantry: "Open in Pantry",
    downloadCta: "Don't have Pantry? Download it free on the App Store.",
    recipeNotFound: "Recipe Not Found",
    badLink: "This link doesn't look right. Try opening it from the Pantry app.",
    deletedRecipe: "This recipe may have been deleted or is no longer shared.",
    description: (count, servings) =>
      `${count} ingredient${count !== 1 ? "s" : ""} · Serves ${Math.round(servings)}`,
    fallbackName: "Shared Recipe",
    serverError: "Something went wrong. Please try again.",
  },
  ar: {
    lang: "ar",
    dir: "rtl",
    sharedViaPantry: "مشارَك عبر Pantry",
    openInPantry: "فتح في Pantry",
    downloadCta: "ليس لديك Pantry؟ حمّله مجانًا من App Store.",
    recipeNotFound: "الوصفة غير موجودة",
    badLink: "يبدو أن هذا الرابط غير صحيح. حاول فتحه من تطبيق Pantry.",
    deletedRecipe: "ربما تم حذف هذه الوصفة أو لم تعد مشتركة.",
    description: (count, servings) =>
      `${count} مكوّن · ${Math.round(servings)} حصة`,
    fallbackName: "وصفة مشتركة",
    serverError: "حدث خطأ ما. يُرجى المحاولة مرة أخرى.",
  },
  bn: {
    lang: "bn",
    sharedViaPantry: "Pantry-এর মাধ্যমে শেয়ার করা হয়েছে",
    openInPantry: "Pantry-তে খুলুন",
    downloadCta: "Pantry নেই? App Store থেকে বিনামূল্যে ডাউনলোড করুন।",
    recipeNotFound: "রেসিপি পাওয়া যায়নি",
    badLink: "এই লিঙ্কটি সঠিক মনে হচ্ছে না। Pantry অ্যাপ থেকে খোলার চেষ্টা করুন।",
    deletedRecipe: "এই রেসিপিটি মুছে ফেলা হয়েছে বা আর শেয়ার করা হচ্ছে না।",
    description: (count, servings) =>
      `${count}টি উপকরণ · ${Math.round(servings)} জনের জন্য`,
    fallbackName: "শেয়ার করা রেসিপি",
    serverError: "কিছু একটা ভুল হয়েছে। আবার চেষ্টা করুন।",
  },
  de: {
    lang: "de",
    sharedViaPantry: "Geteilt über Pantry",
    openInPantry: "In Pantry öffnen",
    downloadCta: "Noch kein Pantry? Kostenlos im App Store herunterladen.",
    recipeNotFound: "Rezept nicht gefunden",
    badLink: "Dieser Link sieht nicht richtig aus. Versuche, ihn über die Pantry-App zu öffnen.",
    deletedRecipe: "Dieses Rezept wurde möglicherweise gelöscht oder wird nicht mehr geteilt.",
    description: (count, servings) =>
      `${count} Zutat${count !== 1 ? "en" : ""} · Für ${Math.round(servings)} Personen`,
    fallbackName: "Geteiltes Rezept",
    serverError: "Etwas ist schiefgelaufen. Bitte versuche es erneut.",
  },
  es: {
    lang: "es",
    sharedViaPantry: "Compartido desde Pantry",
    openInPantry: "Abrir en Pantry",
    downloadCta: "¿No tienes Pantry? Descárgala gratis en la App Store.",
    recipeNotFound: "Receta no encontrada",
    badLink: "Este enlace no parece correcto. Intenta abrirlo desde la app Pantry.",
    deletedRecipe: "Es posible que esta receta haya sido eliminada o ya no esté compartida.",
    description: (count, servings) =>
      `${count} ingrediente${count !== 1 ? "s" : ""} · Para ${Math.round(servings)} personas`,
    fallbackName: "Receta compartida",
    serverError: "Algo salió mal. Por favor, inténtalo de nuevo.",
  },
  fr: {
    lang: "fr",
    sharedViaPantry: "Partagé via Pantry",
    openInPantry: "Ouvrir dans Pantry",
    downloadCta: "Pas encore Pantry ? Téléchargez-le gratuitement sur l'App Store.",
    recipeNotFound: "Recette introuvable",
    badLink: "Ce lien ne semble pas correct. Essayez de l'ouvrir depuis l'application Pantry.",
    deletedRecipe: "Cette recette a peut-être été supprimée ou n'est plus partagée.",
    description: (count, servings) =>
      `${count} ingrédient${count !== 1 ? "s" : ""} · Pour ${Math.round(servings)} personne${Math.round(servings) !== 1 ? "s" : ""}`,
    fallbackName: "Recette partagée",
    serverError: "Une erreur s'est produite. Veuillez réessayer.",
  },
  hi: {
    lang: "hi",
    sharedViaPantry: "Pantry के ज़रिए साझा किया गया",
    openInPantry: "Pantry में खोलें",
    downloadCta: "Pantry नहीं है? App Store पर मुफ़्त डाउनलोड करें।",
    recipeNotFound: "रेसिपी नहीं मिली",
    badLink: "यह लिंक सही नहीं लग रहा। Pantry ऐप से खोलकर देखें।",
    deletedRecipe: "यह रेसिपी शायद हटा दी गई हो या अब साझा नहीं है।",
    description: (count, servings) =>
      `${count} सामग्री · ${Math.round(servings)} लोगों के लिए`,
    fallbackName: "साझा रेसिपी",
    serverError: "कुछ गलत हो गया। कृपया पुनः प्रयास करें।",
  },
  id: {
    lang: "id",
    sharedViaPantry: "Dibagikan lewat Pantry",
    openInPantry: "Buka di Pantry",
    downloadCta: "Belum punya Pantry? Unduh gratis di App Store.",
    recipeNotFound: "Resep Tidak Ditemukan",
    badLink: "Tautan ini tampaknya tidak benar. Coba buka dari aplikasi Pantry.",
    deletedRecipe: "Resep ini mungkin telah dihapus atau tidak lagi dibagikan.",
    description: (count, servings) =>
      `${count} bahan · Untuk ${Math.round(servings)} porsi`,
    fallbackName: "Resep Bersama",
    serverError: "Terjadi kesalahan. Silakan coba lagi.",
  },
  it: {
    lang: "it",
    sharedViaPantry: "Condiviso via Pantry",
    openInPantry: "Apri in Pantry",
    downloadCta: "Non hai Pantry? Scaricala gratis sull'App Store.",
    recipeNotFound: "Ricetta non trovata",
    badLink: "Questo link non sembra corretto. Prova ad aprirlo dall'app Pantry.",
    deletedRecipe: "Questa ricetta potrebbe essere stata eliminata o non è più condivisa.",
    description: (count, servings) =>
      `${count === 1 ? "ingrediente" : "ingredienti"} · Per ${Math.round(servings)} person${Math.round(servings) !== 1 ? "e" : "a"}`,
    fallbackName: "Ricetta condivisa",
    serverError: "Qualcosa è andato storto. Riprova.",
  },
  ja: {
    lang: "ja",
    sharedViaPantry: "Pantryでシェア",
    openInPantry: "Pantryで開く",
    downloadCta: "Pantryをお持ちでない方はApp Storeで無料ダウンロード",
    recipeNotFound: "レシピが見つかりません",
    badLink: "このリンクは正しくないようです。Pantryアプリから開いてみてください。",
    deletedRecipe: "このレシピは削除されたか、共有が終了した可能性があります。",
    description: (count, servings) =>
      `食材${count}種 · ${Math.round(servings)}人前`,
    fallbackName: "共有レシピ",
    serverError: "エラーが発生しました。もう一度お試しください。",
  },
  ko: {
    lang: "ko",
    sharedViaPantry: "Pantry로 공유됨",
    openInPantry: "Pantry에서 열기",
    downloadCta: "Pantry가 없으신가요? App Store에서 무료로 다운로드하세요.",
    recipeNotFound: "레시피를 찾을 수 없음",
    badLink: "링크가 올바르지 않습니다. Pantry 앱에서 열어보세요.",
    deletedRecipe: "이 레시피는 삭제되었거나 더 이상 공유되지 않을 수 있습니다.",
    description: (count, servings) =>
      `재료 ${count}가지 · ${Math.round(servings)}인분`,
    fallbackName: "공유된 레시피",
    serverError: "오류가 발생했습니다. 다시 시도해 주세요.",
  },
  "pt-BR": {
    lang: "pt-BR",
    sharedViaPantry: "Compartilhado via Pantry",
    openInPantry: "Abrir no Pantry",
    downloadCta: "Não tem o Pantry? Baixe gratuitamente na App Store.",
    recipeNotFound: "Receita não encontrada",
    badLink: "Este link não parece correto. Tente abri-lo pelo aplicativo Pantry.",
    deletedRecipe: "Esta receita pode ter sido excluída ou não está mais sendo compartilhada.",
    description: (count, servings) =>
      `${count} ingrediente${count !== 1 ? "s" : ""} · Para ${Math.round(servings)} pessoa${Math.round(servings) !== 1 ? "s" : ""}`,
    fallbackName: "Receita compartilhada",
    serverError: "Algo deu errado. Por favor, tente novamente.",
  },
  ru: {
    lang: "ru",
    sharedViaPantry: "Поделились через Pantry",
    openInPantry: "Открыть в Pantry",
    downloadCta: "Нет Pantry? Скачайте бесплатно в App Store.",
    recipeNotFound: "Рецепт не найден",
    badLink: "Эта ссылка выглядит неверной. Попробуйте открыть её из приложения Pantry.",
    deletedRecipe: "Этот рецепт мог быть удалён или больше не является общедоступным.",
    description: (count, servings) =>
      `${count} ингредиентов · ${Math.round(servings)} порций`,
    fallbackName: "Общий рецепт",
    serverError: "Что-то пошло не так. Пожалуйста, попробуйте ещё раз.",
  },
  tr: {
    lang: "tr",
    sharedViaPantry: "Pantry ile paylaşıldı",
    openInPantry: "Pantry'de aç",
    downloadCta: "Pantry yok mu? App Store'dan ücretsiz indirin.",
    recipeNotFound: "Tarif bulunamadı",
    badLink: "Bu bağlantı doğru görünmüyor. Pantry uygulamasından açmayı deneyin.",
    deletedRecipe: "Bu tarif silinmiş veya artık paylaşılmıyor olabilir.",
    description: (count, servings) =>
      `${count} malzeme · ${Math.round(servings)} kişilik`,
    fallbackName: "Paylaşılan tarif",
    serverError: "Bir şeyler yanlış gitti. Lütfen tekrar deneyin.",
  },
  "zh-Hans": {
    lang: "zh-Hans",
    sharedViaPantry: "通过 Pantry 分享",
    openInPantry: "在 Pantry 中打开",
    downloadCta: "没有 Pantry？在 App Store 免费下载。",
    recipeNotFound: "未找到食谱",
    badLink: "此链接似乎有误。请从 Pantry 应用中打开。",
    deletedRecipe: "此食谱可能已被删除或不再共享。",
    description: (count, servings) =>
      `${count} 种食材 · ${Math.round(servings)} 人份`,
    fallbackName: "共享食谱",
    serverError: "出了点问题。请再试一次。",
  },
  "zh-Hant": {
    lang: "zh-Hant",
    sharedViaPantry: "透過 Pantry 分享",
    openInPantry: "在 Pantry 中開啟",
    downloadCta: "沒有 Pantry？在 App Store 免費下載。",
    recipeNotFound: "找不到食譜",
    badLink: "此連結似乎有誤。請從 Pantry 應用程式中開啟。",
    deletedRecipe: "此食譜可能已被刪除或不再分享。",
    description: (count, servings) =>
      `${count} 種食材 · ${Math.round(servings)} 人份`,
    fallbackName: "共享食譜",
    serverError: "發生了一些問題。請再試一次。",
  },
};

// Parse Accept-Language header and return the best-matching supported locale.
function resolveLocale(acceptLanguage) {
  if (!acceptLanguage) return "en";

  const langs = acceptLanguage
    .split(",")
    .map((entry) => {
      const [tag, q] = entry.trim().split(";q=");
      return { tag: tag.trim().toLowerCase(), q: q ? parseFloat(q) : 1.0 };
    })
    .sort((a, b) => b.q - a.q);

  // Simple prefix → locale key map for non-Chinese languages
  const prefixMap = { ar: "ar", bn: "bn", de: "de", en: "en", es: "es", fr: "fr", hi: "hi", id: "id", it: "it", ja: "ja", ko: "ko", ru: "ru", tr: "tr" };

  for (const { tag } of langs) {
    // Traditional Chinese regions (must come before generic zh check)
    if (["zh-tw", "zh-hk", "zh-mo", "zh-hant"].includes(tag)) return "zh-Hant";
    // Simplified Chinese regions
    if (["zh-cn", "zh-sg", "zh-hans"].includes(tag)) return "zh-Hans";
    if (tag.startsWith("zh")) {
      const region = tag.split("-")[1];
      return (region && ["tw", "hk", "mo"].includes(region)) ? "zh-Hant" : "zh-Hans";
    }
    // All Portuguese variants → pt-BR
    if (tag.startsWith("pt")) return "pt-BR";
    // Remaining languages by prefix
    const prefix = tag.split("-")[0];
    if (prefixMap[prefix]) return prefixMap[prefix];
  }

  return "en";
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function renderPage({ title, description, imageUrl, recipeId, t }) {
  const safeTitle = escapeHtml(title);
  const safeDesc = escapeHtml(description);
  const canonicalUrl = `https://pantrymanager.app/recipe/${recipeId}`;
  const dirAttr = t.dir === "rtl" ? ' dir="rtl"' : "";

  return `<!DOCTYPE html>
<html lang="${t.lang}"${dirAttr}>
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
      <p class="label">${escapeHtml(t.sharedViaPantry)}</p>
      <h1>${safeTitle}</h1>
      <p class="meta">${safeDesc}</p>
      <a class="btn" href="${APP_STORE_URL}">${escapeHtml(t.openInPantry)}</a>
      <p class="sub">${escapeHtml(t.downloadCta)}</p>
    </div>
  </div>
</body>
</html>`;
}

exports.recipeShare = onRequest({ region: "us-central1" }, async (req, res) => {
  // Path is /recipe/{uuid} — extract the last segment
  const parts = req.path.split("/").filter(Boolean);
  const recipeId = parts[parts.length - 1];
  const t = i18n[resolveLocale(req.headers["accept-language"])];

  // Validate UUID format
  if (!recipeId || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(recipeId)) {
    return res.status(404).send(renderPage({
      title: t.recipeNotFound,
      description: t.badLink,
      imageUrl: null,
      recipeId: "",
      t,
    }));
  }

  try {
    const doc = await db.collection("sharedRecipes").doc(recipeId).get();

    if (!doc.exists) {
      return res.status(404).send(renderPage({
        title: t.recipeNotFound,
        description: t.deletedRecipe,
        imageUrl: null,
        recipeId,
        t,
      }));
    }

    const data = doc.data();
    const name = data.name || t.fallbackName;
    const servings = data.servings || 4;
    const count = data.ingredientCount || 0;
    const description = t.description(count, servings);
    const imageUrl = data.imagePublicUrl || null;

    res.set("Cache-Control", "public, max-age=300, s-maxage=300");
    return res.send(renderPage({ title: name, description, imageUrl, recipeId, t }));
  } catch (err) {
    console.error("recipeShare error:", err);
    return res.status(500).send(t.serverError);
  }
});
