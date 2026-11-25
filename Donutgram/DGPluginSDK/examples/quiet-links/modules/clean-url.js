export function cleanTrackingURL(text) {
  if (typeof text !== "string" || text.length > 8192 || !/^https?:\/\/[^\s/?#]+(?:[/?#]|$)/i.test(text) || /[\u0000-\u0020\u007f]/u.test(text)) return null;
  const hashIndex = text.indexOf("#");
  const fragment = hashIndex < 0 ? "" : text.slice(hashIndex);
  const base = hashIndex < 0 ? text : text.slice(0, hashIndex);
  const queryIndex = base.indexOf("?");
  if (queryIndex < 0) return text;
  const retained = base.slice(queryIndex + 1).split("&").filter((part) => {
    const encodedKey = part.split("=", 1)[0];
    let key;
    try { key = decodeURIComponent(encodedKey.replace(/\+/g, " ")); }
    catch { return true; }
    return !/^utm_/i.test(key);
  });
  return base.slice(0, queryIndex) + (retained.length ? "?" + retained.join("&") : "") + fragment;
}
