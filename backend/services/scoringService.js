const clamp = (value, min = 0, max = 100) => Math.max(min, Math.min(max, value));
const round = (n) => Math.round(n);

const BASE_WEIGHTS = {
  volumeSpike: 0.25,
  priceMomentum: 0.20,
  volatility: 0.10,
  rsi: 0.10,
  social: 0.10,
  onchain: 0.25,
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
 * On-chain sub-score, combining two bullish signals in equal parts:
 *  - exchange outflow spike: net % of supply leaving exchanges (negative
 *    `supplyOnExchangesChange24h` = coins moving to cold storage = bullish)
 *  - whale accumulation: more large (>$100k) withdrawals from exchanges
 *    than deposits into them = bullish
 * Returns null when on-chain data isn't real (dummy/unavailable), so the
 * caller can exclude it from scoring entirely rather than let placeholder
 * numbers influence a real score.
 */
function onchainSubScores(onchain) {
  if (!onchain || !onchain.available) return null;

  const exchangeOutflowScore = clamp(50 - (onchain.supplyOnExchangesChange24h ?? 0) * 15);
  const whaleNet = (onchain.whaleFromExchangeCount ?? 0) - (onchain.whaleToExchangeCount ?? 0);
  const whaleAccumulationScore = clamp(50 + whaleNet * 6);
  const combined = (exchangeOutflowScore + whaleAccumulationScore) / 2;

  return { exchangeOutflowScore, whaleAccumulationScore, combined };
}

/** When on-chain data is unavailable, its 25% weight is redistributed proportionally across the other metrics. */
function effectiveWeights(onchainAvailable) {
  if (onchainAvailable) return { ...BASE_WEIGHTS };

  const weights = { ...BASE_WEIGHTS };
  const freedWeight = weights.onchain;
  weights.onchain = 0;

  const otherKeys = ['volumeSpike', 'priceMomentum', 'volatility', 'rsi', 'social'];
  const otherTotal = otherKeys.reduce((sum, k) => sum + BASE_WEIGHTS[k], 0);
  otherKeys.forEach((k) => {
    weights[k] = BASE_WEIGHTS[k] + freedWeight * (BASE_WEIGHTS[k] / otherTotal);
  });
  return weights;
}

/**
 * Combines all sub-scores into the final 0-100 potential score using the
 * spec's weighting: volume spike 25%, price momentum 20%, volatility 10%,
 * RSI 10%, social 10%, on-chain 25%. If on-chain data isn't available for
 * a coin, its weight is redistributed proportionally across the rest.
 */
function computeScore(metrics) {
  const vs = volumeSpikeScore(metrics.volumeRatio);
  const pm = priceMomentumScore(metrics);
  const vol = volatilityScore(metrics.volatilityPct);
  const rsi = rsiScore(metrics.rsi);
  const social = socialScore(metrics.social);
  const onchainSub = onchainSubScores(metrics.onchain);
  const onchainAvailable = Boolean(onchainSub);
  const onchain = onchainAvailable ? onchainSub.combined : 0;

  const weights = effectiveWeights(onchainAvailable);

  const total =
    vs * weights.volumeSpike +
    pm * weights.priceMomentum +
    vol * weights.volatility +
    rsi * weights.rsi +
    social * weights.social +
    onchain * weights.onchain;

  return {
    total: round(clamp(total)),
    breakdown: {
      volumeSpike: round(vs),
      priceMomentum: round(pm),
      volatility: round(vol),
      rsi: round(rsi),
      social: round(social),
      onchain: onchainAvailable ? round(onchain) : null,
      onchainExchangeOutflow: onchainAvailable ? round(onchainSub.exchangeOutflowScore) : null,
      onchainWhaleAccumulation: onchainAvailable ? round(onchainSub.whaleAccumulationScore) : null,
    },
    weights,
  };
}

module.exports = { computeScore, BASE_WEIGHTS };
