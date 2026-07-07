const cron = require('node-cron');
const db = require('../db/database');
const { triggerScreening } = require('./screeningService');

const THRESHOLD = parseFloat(process.env.SIGNAL_SCORE_THRESHOLD || '75');
const INTERVAL_MIN = parseInt(process.env.SCAN_INTERVAL_MINUTES || '5', 10);

function startScheduler(io) {
  const runCycle = async () => {
    console.log(`[scheduler] running screening cycle (threshold=${THRESHOLD})...`);
    try {
      await triggerScreening({
        threshold: THRESHOLD,
        force: true,
        onDone: (result, newSignals) => {
          io.emit('screening:update', {
            updatedAt: result.updatedAt,
            count: result.coins.length,
            topCoins: result.coins.slice(0, 20),
          });

          if (newSignals.length) {
            io.emit('signals:new', newSignals);

            const watchlist = db.prepare('SELECT coin_id, alert_threshold FROM watchlist').all();
            const watchlistMap = new Map(watchlist.map((w) => [w.coin_id, w.alert_threshold]));
            const watchlistHits = newSignals.filter(
              (s) => watchlistMap.has(s.id) && s.score >= (watchlistMap.get(s.id) ?? THRESHOLD)
            );
            if (watchlistHits.length) {
              io.emit('watchlist:alert', watchlistHits);
            }
          }
        },
      });
      console.log('[scheduler] screening cycle complete');
    } catch (err) {
      console.error('[scheduler] screening cycle failed:', err.message);
    }
  };

  // Run once shortly after boot, then every N minutes via cron.
  setTimeout(runCycle, 3000);
  cron.schedule(`*/${INTERVAL_MIN} * * * *`, runCycle);

  return { runCycle };
}

module.exports = { startScheduler, THRESHOLD };
