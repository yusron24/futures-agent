const cron = require('node-cron');
const db = require('../db/database');
const { triggerScreening } = require('./screeningService');
const { prewarmRsiTimeframes } = require('./rsiScreenerService');
const { notifyCoinSignal } = require('./notificationService');
const { getSettings } = require('../db/settingsStore');

let cronTask = null;
let ioRef = null;

async function runCycle() {
  const { signalScoreThreshold } = getSettings();
  console.log(`[scheduler] running screening cycle (threshold=${signalScoreThreshold})...`);
  try {
    await triggerScreening({
      threshold: signalScoreThreshold,
      force: true,
      onDone: (result, newSignals) => {
        ioRef.emit('screening:update', {
          updatedAt: result.updatedAt,
          count: result.coins.length,
          topCoins: result.coins.slice(0, 20),
        });

        if (newSignals.length) {
          ioRef.emit('signals:new', newSignals);

          const watchlist = db.prepare('SELECT coin_id, alert_threshold FROM watchlist').all();
          const watchlistMap = new Map(watchlist.map((w) => [w.coin_id, w.alert_threshold]));
          const watchlistHits = newSignals.filter(
            (s) => watchlistMap.has(s.id) && s.score >= (watchlistMap.get(s.id) ?? signalScoreThreshold)
          );
          if (watchlistHits.length) {
            ioRef.emit('watchlist:alert', watchlistHits);
          }

          // Telegram/Discord: notify for every watchlist hit, plus every
          // other new signal (a general "potensi pergerakan besar"
          // detection) - deduped so a coin that's both only sends once.
          const watchlistIds = new Set(watchlistHits.map((s) => s.id));
          const toNotify = [
            ...watchlistHits.map((s) => ({ coin: s, reason: 'watchlist' })),
            ...newSignals.filter((s) => !watchlistIds.has(s.id)).map((s) => ({ coin: s, reason: 'signal' })),
          ];
          for (const { coin, reason } of toNotify) {
            notifyCoinSignal(coin, { reason }).catch((err) =>
              console.error(`[scheduler] notification failed for ${coin.id}:`, err.message)
            );
          }
        }
      },
    });
    console.log('[scheduler] screening cycle complete');

    // Keep the non-daily RSI screener timeframes warm in the background,
    // so switching timeframe on the frontend hits cached data instead of
    // waiting on a full universe sweep.
    prewarmRsiTimeframes().catch((err) =>
      console.error('[scheduler] rsi prewarm failed:', err.message)
    );
  } catch (err) {
    console.error('[scheduler] screening cycle failed:', err.message);
  }
}

/** (Re)schedules the cron job using the current scanIntervalMinutes setting. */
function scheduleCron() {
  if (cronTask) cronTask.stop();
  const { scanIntervalMinutes } = getSettings();
  cronTask = cron.schedule(`*/${scanIntervalMinutes} * * * *`, runCycle);
  console.log(`[scheduler] cron scheduled every ${scanIntervalMinutes} minute(s)`);
}

function startScheduler(io) {
  ioRef = io;
  setTimeout(runCycle, 3000);
  scheduleCron();
  return { runCycle };
}

/** Called by the settings route after scanIntervalMinutes changes, so the new interval takes effect without a restart. */
function restartScheduler() {
  if (!ioRef) return;
  scheduleCron();
}

module.exports = { startScheduler, restartScheduler, runCycle };
