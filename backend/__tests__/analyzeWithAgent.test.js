const nock = require('nock');
const { analyzeWithAgent } = require('../server');
const { buildCandles } = require('../test-utils/candles');

const BINANCE = 'https://fapi.binance.com';
const AI_HOST = 'https://ai.dinoiki.com';
const SYMBOL = 'BTCUSDT';

function mockMarketData() {
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
}

function mockAiResponse(content) {
  nock(AI_HOST)
    .post('/v1/chat/completions')
    .reply(200, { choices: [{ message: { content } }] });
}

beforeEach(() => {
  nock.cleanAll();
});

afterAll(() => {
  nock.restore();
});

describe('analyzeWithAgent', () => {
  test('forces WAIT when the reward:risk ratio is below 2', async () => {
    mockMarketData();
    mockAiResponse(JSON.stringify({
      action: 'LONG', entry: 100, stopLoss: 99, takeProfit: 101, confidence: 95, reasoning: 'x', rr: '1:1',
    }));

    const result = await analyzeWithAgent(SYMBOL);
    expect(result.action).toBe('WAIT');
  });

  test('forces WAIT when confidence is below 90', async () => {
    mockMarketData();
    mockAiResponse(JSON.stringify({
      action: 'SHORT', entry: 100, stopLoss: 110, takeProfit: 70, confidence: 80, reasoning: 'y', rr: '1:3',
    }));

    const result = await analyzeWithAgent(SYMBOL);
    expect(result.action).toBe('WAIT');
  });

  test('keeps a LONG/SHORT decision when rr >= 2 and confidence >= 90', async () => {
    mockMarketData();
    mockAiResponse(JSON.stringify({
      action: 'LONG', entry: 100, stopLoss: 90, takeProfit: 130, confidence: 95, reasoning: 'z', rr: '1:3',
    }));

    const result = await analyzeWithAgent(SYMBOL);
    expect(result.action).toBe('LONG');
    expect(result.confidence).toBe(95);
  });

  test('degrades to WAIT/0 confidence when the AI response is not valid JSON', async () => {
    mockMarketData();
    mockAiResponse('this is not json');

    const result = await analyzeWithAgent(SYMBOL);
    expect(result).toEqual({ action: 'WAIT', confidence: 0 });
  });

  test('returns null when candle data cannot be fetched', async () => {
    nock(BINANCE)
      .get('/fapi/v1/klines')
      .query({ symbol: SYMBOL, interval: '1h', limit: '500' })
      .reply(500);

    const result = await analyzeWithAgent(SYMBOL);
    expect(result).toBeNull();
  });
});
