const clamp = (value, min = 0, max = 100) => Math.max(min, Math.min(max, value));

const WEIGHTS = {
  volumeSpike: 0.30,
  priceMomentum: 0.25,
  volatility: 0.15,
  rsi: 0.15,
  social: 0.15,
};

/** volumeRatio = latest day volume / average of the prior days' volume. */
function volumeSpikeScore(volumeRatio) {
  if (volumeRatio == null) return 50; // neutral placeholder
  return clamp((volumeRatio - 1) * 50 + 50);
}

/** Combines 1h/24h/7d % change into a single 0-100 momentum score. */
function priceMomentumScore({ change1h = 0, change24h = 0, change7d = 0 }) {
  const raw = 50 + change24h * 2 + change1h * 3 + change7d * 0.5;
  return clamp(raw);
}

function volatilityScore(volatilityPct) {
  if (volatilityPct == null) return 0;
  return clamp(volatilityPct * 5);
}

/** RSI far from the neutral 50 midpoint (either overbought or oversold) scores higher. */
function rsiScore(rsi) {
  if (rsi == null) return 50; // neutral placeholder when not computed
  return clamp(Math.abs(rsi - 50) * 2);
}

function socialScore(social) {
  if (!social || !social.available) return 50; // neutral placeholder
  return clamp(social.score);
}

/**
 * Combines all sub-scores into the final 0-100 potential score using the
 * spec's weighting: volume spike 30%, price momentum 25%, volatility 15%,
 * RSI 15%, social 15%.
 */
function computeScore(metrics) {
  const vs = volumeSpikeScore(metrics.volumeRatio);
  const pm = priceMomentumScore(metrics);
  const vol = volatilityScore(metrics.volatilityPct);
  const rsi = rsiScore(metrics.rsi);
  const social = socialScore(metrics.social);

  const total =
    vs * WEIGHTS.volumeSpike +
    pm * WEIGHTS.priceMomentum +
    vol * WEIGHTS.volatility +
    rsi * WEIGHTS.rsi +
    social * WEIGHTS.social;

  return {
    total: Math.round(clamp(total)),
    breakdown: {
      volumeSpikeScore: Math.round(vs),
      priceMomentumScore: Math.round(pm),
      volatilityScore: Math.round(vol),
      rsiScore: Math.round(rsi),
      socialScore: Math.round(social),
    },
  };
}

module.exports = { computeScore, WEIGHTS };
