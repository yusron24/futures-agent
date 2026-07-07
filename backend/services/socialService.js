const axios = require('axios');

const LUNARCRUSH_KEY = process.env.LUNARCRUSH_API_KEY || process.env.SOCIAL_API_KEY || '';

/**
 * Social momentum for a coin symbol. Returns null when no API key is
 * configured so callers can fall back to a neutral placeholder score -
 * per spec this metric is "skipped but still has a placeholder slot".
 */
async function getSocialMomentum(symbol) {
  if (!LUNARCRUSH_KEY) return null;

  try {
    const res = await axios.get('https://lunarcrush.com/api4/public/coins/list/v1', {
      params: { symbol: symbol.toUpperCase() },
      headers: { Authorization: `Bearer ${LUNARCRUSH_KEY}` },
      timeout: 8000,
    });
    const coin = res.data?.data?.[0];
    if (!coin) return null;

    // galaxy_score (0-100) and social volume 24h change (%) are the two
    // signals LunarCrush exposes that map cleanly onto "social momentum".
    const galaxyScore = coin.galaxy_score ?? 50;
    const socialVolumeChange = coin.social_volume_24h_change_percent ?? 0;
    const score = Math.max(0, Math.min(100, galaxyScore * 0.6 + (50 + socialVolumeChange) * 0.4));

    return {
      available: true,
      score,
      galaxyScore,
      sentiment: coin.sentiment ?? null,
      socialVolumeChangePercent: socialVolumeChange,
    };
  } catch (err) {
    console.warn(`[social] LunarCrush lookup failed for ${symbol}: ${err.message}`);
    return null;
  }
}

module.exports = { getSocialMomentum, socialConfigured: Boolean(LUNARCRUSH_KEY) };
