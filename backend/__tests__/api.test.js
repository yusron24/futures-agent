const request = require('supertest');
const nock = require('nock');
const { app } = require('../server');
const { buildCandles } = require('../test-utils/candles');

const BINANCE = 'https://fapi.binance.com';
const AI_HOST = 'https://ai.dinoiki.com';
const SYMBOL = 'ETHUSDT';

beforeEach(() => {
  nock.cleanAll();
});

afterAll(() => {
  nock.restore();
});

describe('GET /api/v1/signals', () => {
  test('returns the current (empty) in-memory scan state', async () => {
    const res = await request(app).get('/api/v1/signals');

    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      success: true,
      signals: [],
      total: 0,
      scanning: false,
    });
  });
});

describe('GET /api/v1/signal/:symbol', () => {
  test('returns a WAIT signal when the AI decides not to trade', async () => {
    nock(BINANCE)
      .get('/fapi/v1/klines')
      .query({ symbol: SYMBOL, interval: '1h', limit: '500' })
      .reply(200, buildCandles(500))
      .get('/fapi/v1/openInterest')
      .query({ symbol: SYMBOL })
      .reply(200, { sumOpenInterestValue: '1000' })
      .get('/fapi/v1/fundingInfo')
      .query({ symbol: SYMBOL })
      .reply(200, [{ fundingRate: '0.0001' }])
      .get('/fapi/v1/globalLongShortAccountRatio')
      .query({ symbol: SYMBOL, period: '1h', limit: '1' })
      .reply(200, [{ longShortRatio: '1.2' }])
      .get('/fapi/v1/ticker/24hr')
      .query({ symbol: SYMBOL })
      .reply(200, { lastPrice: '100' });

    nock(AI_HOST)
      .post('/v1/chat/completions')
      .reply(200, {
        choices: [{ message: { content: JSON.stringify({ action: 'WAIT', confidence: 0 }) } }],
      });

    const res = await request(app).get(`/api/v1/signal/${SYMBOL}`);

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ success: true, signal: { action: 'WAIT', confidence: 0 } });
  });

  test('returns a null signal when candle data is unavailable', async () => {
    nock(BINANCE)
      .get('/fapi/v1/klines')
      .query({ symbol: SYMBOL, interval: '1h', limit: '500' })
      .reply(500);

    const res = await request(app).get(`/api/v1/signal/${SYMBOL}`);

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ success: true, signal: null });
  });
});
