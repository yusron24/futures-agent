const axios = require('axios');
const { getSettings } = require('../db/settingsStore');

function formatPrice(price) {
  if (price == null) return '-';
  if (price >= 1) return `$${price.toLocaleString('en-US', { maximumFractionDigits: 2 })}`;
  return `$${price.toPrecision(4)}`;
}

function formatPercent(value) {
  if (value == null) return '-';
  const sign = value > 0 ? '+' : '';
  return `${sign}${value.toFixed(2)}%`;
}

function buildDetailUrl(coinId, frontendUrl) {
  const base = (frontendUrl || 'http://localhost:5173').replace(/\/+$/, '');
  return `${base}/coin/${coinId}`;
}

function buildTelegramText(coin, reasonLabel, detailUrl) {
  return [
    `${reasonLabel}`,
    `*${coin.symbol}* (${coin.name})`,
    `Skor Potensi: *${coin.score}/100*`,
    `Harga: ${formatPrice(coin.price)}`,
    `Perubahan 24h: ${formatPercent(coin.change24h)}`,
    `Volume Spike: ${coin.volumeRatio != null ? `${coin.volumeRatio.toFixed(2)}x` : 'n/a'}`,
    `RSI: ${coin.rsi != null ? coin.rsi.toFixed(1) : 'n/a'}`,
    `🔗 ${detailUrl}`,
  ].join('\n');
}

function buildDiscordPayload(coin, reasonLabel, detailUrl) {
  return {
    content: reasonLabel,
    embeds: [
      {
        title: `${coin.symbol} — ${coin.name}`,
        url: detailUrl,
        color: 0x00e676,
        description: `Skor Potensi: **${coin.score}/100**`,
        fields: [
          { name: 'Harga', value: formatPrice(coin.price), inline: true },
          { name: 'Perubahan 24h', value: formatPercent(coin.change24h), inline: true },
          { name: 'Volume Spike', value: coin.volumeRatio != null ? `${coin.volumeRatio.toFixed(2)}x` : 'n/a', inline: true },
          { name: 'RSI', value: coin.rsi != null ? coin.rsi.toFixed(1) : 'n/a', inline: true },
        ],
        timestamp: new Date().toISOString(),
      },
    ],
  };
}

/** Sends a plain-text message via a Telegram bot. No-op (skipped) if disabled/not configured. */
async function sendTelegramMessage(text) {
  const { telegramEnabled, telegramBotToken, telegramChatId } = getSettings();
  if (!telegramEnabled || !telegramBotToken || !telegramChatId) {
    return { skipped: true, reason: 'not configured or disabled' };
  }
  try {
    await axios.post(
      `https://api.telegram.org/bot${telegramBotToken}/sendMessage`,
      { chat_id: telegramChatId, text, parse_mode: 'Markdown', disable_web_page_preview: false },
      { timeout: 8000 }
    );
    return { success: true };
  } catch (err) {
    const reason = err.response?.data?.description || err.message;
    console.error(`[notification] Telegram send failed: ${reason}`);
    return { success: false, error: reason };
  }
}

/** Sends an embed message via a Discord webhook. No-op (skipped) if disabled/not configured. */
async function sendDiscordMessage(payload) {
  const { discordEnabled, discordWebhookUrl } = getSettings();
  if (!discordEnabled || !discordWebhookUrl) {
    return { skipped: true, reason: 'not configured or disabled' };
  }
  try {
    await axios.post(discordWebhookUrl, payload, { timeout: 8000 });
    return { success: true };
  } catch (err) {
    const reason = err.response?.data?.message || err.message;
    console.error(`[notification] Discord send failed: ${reason}`);
    return { success: false, error: reason };
  }
}

/**
 * Notifies Telegram/Discord (whichever are enabled+configured) about a
 * coin that crossed the score threshold. `reason` is 'watchlist' when
 * triggered by a watchlisted coin, or 'signal' for a general "potensi
 * pergerakan besar" detection. Never throws - failures are logged and
 * returned per-channel so callers can carry on regardless.
 */
async function notifyCoinSignal(coin, { reason = 'signal' } = {}) {
  const { frontendUrl } = getSettings();
  const detailUrl = buildDetailUrl(coin.id, frontendUrl);
  const reasonLabel = reason === 'watchlist' ? '⭐ Watchlist Alert' : '🚀 Sinyal Potensi Pergerakan Besar';

  const [telegram, discord] = await Promise.all([
    sendTelegramMessage(buildTelegramText(coin, reasonLabel, detailUrl)),
    sendDiscordMessage(buildDiscordPayload(coin, reasonLabel, detailUrl)),
  ]);

  return { telegram, discord };
}

/** Sends a test message to whichever channels are enabled+configured, for the Settings page "Test" button. */
async function sendTestNotification() {
  const testCoin = {
    id: 'bitcoin',
    symbol: 'TEST',
    name: 'Notifikasi Uji Coba',
    score: 88,
    price: 12345.67,
    change24h: 6.4,
    volumeRatio: 2.3,
    rsi: 71.2,
  };
  return notifyCoinSignal(testCoin, { reason: 'signal' });
}

module.exports = { notifyCoinSignal, sendTestNotification, sendTelegramMessage, sendDiscordMessage };
