/**
 * Maps `items` through async `fn` with at most `concurrency` calls in
 * flight at once, preserving input order in the returned array. Used to
 * pipeline Binance requests: the global rate limiter still spaces request
 * *starts*, but network round-trips overlap instead of adding up
 * serially (which is what made full-universe sweeps take a minute).
 */
async function mapWithConcurrency(items, concurrency, fn) {
  const results = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.max(1, Math.min(concurrency, items.length)) }, async () => {
    // eslint-disable-next-line no-constant-condition
    while (true) {
      const i = next;
      next += 1;
      if (i >= items.length) return;
      results[i] = await fn(items[i], i);
    }
  });
  await Promise.all(workers);
  return results;
}

module.exports = { mapWithConcurrency };
