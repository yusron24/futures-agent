const nock = require('nock');
const { getTopVolumeSymbols, fetchCandles, fetchDerivatives, cache } = require('../server');
const { buildCandles } = require('../test-utils/candles');

const BINANCE = 'https://fapi.binance.com';

beforeEach(() => {
  cache.flushAll();
  nock.cleanAll();
});

afterAll(() => {
  nock.restore();
});

describe('getTopVolumeSymbols', () => {
  test('returns the top USDT pairs sorted by quote volume', async () => {
    nock(BINANCE)
      .get('/fapi/v1/ticker/24hr')
      .reply(200, [
        { symbol: 'BTCUSDT', quoteVolume: '1000' },
        { symbol: 'ETHUSDT', quoteVolume: '5000' },
        { symbol: 'BTCUSD', quoteVolume: '9999999' }, // not a USDT pair, must be excluded
        { symbol: 'SOLUSDT', quoteVolume: '2000' },
      ]);

    const symbols = await getTopVolumeSymbols();
    expect(symbols).toEqual(['ETHUSDT', 'SOLUSDT', 'BTCUSDT']);
  });

  test('falls back to a default symbol list when the request fails', async () => {
    nock(BINANCE).get('/fapi/v1/ticker/24hr').reply(500);

    const symbols = await getTopVolumeSymbols();
    expect(symbols).toEqual(['BTCUSDT', 'ETHUSDT', 'SOLUSDT']);
  });

  test('serves subsequent calls from cache without hitting the network again', async () => {
    const scope = nock(BINANCE)
      .get('/fapi/v1/ticker/24hr')
      .reply(200, [{ symbol: 'BTCUSDT', quoteVolume: '1000' }]);

    await getTopVolumeSymbols();
    await getTopVolumeSymbols();

    expect(scope.isDone()).toBe(true);
    expect(nock.pendingMocks()).toEqual([]);
  });
});

describe('fetchCandles', () => {
  test('returns kline data on success', async () => {
    const candles = buildCandles(500);
    nock(BINANCE)
      .get('/fapi/v1/klines')
      .query({ symbol: 'BTCUSDT', interval: '1h', limit: '500' })
      .reply(200, candles);

    const result = await fetchCandles('BTCUSDT');
    expect(result).toHaveLength(500);
  });

  test('returns null when the request fails', async () => {
    nock(BINANCE).get('/fapi/v1/klines').query(true).reply(500);

    const result = await fetchCandles('BTCUSDT');
    expect(result).toBeNull();
  });
});

describe('fetchDerivatives', () => {
  test('returns parsed open interest, funding rate and long/short ratio', async () => {
    nock(BINANCE)
      .get('/fapi/v1/openInterest')
      .query({ symbol: 'BTCUSDT' })
      .reply(200, { sumOpenInterestValue: '12345.6' })
      .get('/fapi/v1/fundingInfo')
      .query({ symbol: 'BTCUSDT' })
      .reply(200, [{ fundingRate: '0.0001' }])
      .get('/fapi/v1/globalLongShortAccountRatio')
      .query({ symbol: 'BTCUSDT', period: '1h', limit: '1' })
      .reply(200, [{ longShortRatio: '1.8' }]);

    const result = await fetchDerivatives('BTCUSDT');
    expect(result).toEqual({ oi: 12345.6, funding: 0.0001, lsRatio: 1.8 });
  });

  test('returns safe defaults when any of the calls fails', async () => {
    nock(BINANCE)
      .get('/fapi/v1/openInterest')
      .query({ symbol: 'BTCUSDT' })
      .reply(500)
      .get('/fapi/v1/fundingInfo')
      .query({ symbol: 'BTCUSDT' })
      .reply(200, [{ fundingRate: '0.0001' }])
      .get('/fapi/v1/globalLongShortAccountRatio')
      .query({ symbol: 'BTCUSDT', period: '1h', limit: '1' })
      .reply(200, [{ longShortRatio: '1.8' }]);

    const result = await fetchDerivatives('BTCUSDT');
    expect(result).toEqual({ oi: 0, funding: 0, lsRatio: 1 });
  });
});
