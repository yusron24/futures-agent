import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import axios from 'axios';
import App from './App';

jest.mock('axios');

const mockSignals = [
  { symbol: 'ETHUSDT', signal: 'LONG', confidence: 92, entry: 100, stopLoss: 95, takeProfit: 110, score: 5, volumeRatio: 1.2, timeframe: '1h' },
  { symbol: 'BTCUSDT', signal: 'SHORT', confidence: 97, entry: 200, stopLoss: 210, takeProfit: 180, score: 8, volumeRatio: 2.1, timeframe: '1h' },
];

beforeEach(() => {
  jest.clearAllMocks();
});

test('renders header and shows empty state when there are no signals', async () => {
  axios.get.mockResolvedValue({ data: { signals: [], lastScan: null } });

  render(<App />);

  expect(screen.getByText(/FUTURES AI/i)).toBeInTheDocument();
  expect(await screen.findByText(/No signals found/i)).toBeInTheDocument();
});

test('fetches signals on mount and sorts them by confidence descending', async () => {
  axios.get.mockResolvedValue({ data: { signals: mockSignals, lastScan: new Date().toISOString() } });

  render(<App />);

  const rows = await screen.findAllByText(/USDT$/);
  expect(rows[0]).toHaveTextContent('BTCUSDT');
  expect(rows[1]).toHaveTextContent('ETHUSDT');
});

test('clicking a signal fetches and shows its detail', async () => {
  axios.get.mockImplementation((url) => {
    if (url.includes('/api/v1/signal/')) {
      return Promise.resolve({ data: { signal: { ...mockSignals[1] } } });
    }
    return Promise.resolve({ data: { signals: mockSignals, lastScan: null } });
  });

  render(<App />);

  const btcRow = await screen.findByText('BTCUSDT');
  fireEvent.click(btcRow);

  await waitFor(() => {
    expect(screen.getByText('CONFIDENCE')).toBeInTheDocument();
  });
  expect(screen.getByText('97%')).toBeInTheDocument();
});

test('clicking a timeframe button triggers a scan and disables buttons while scanning', async () => {
  axios.get.mockResolvedValue({ data: { signals: [], lastScan: null } });
  let resolveScan;
  axios.post.mockImplementation(() => new Promise((resolve) => { resolveScan = resolve; }));

  render(<App />);
  await screen.findByText(/No signals found/i);

  const btn4h = screen.getByText('4h');
  fireEvent.click(btn4h);

  await waitFor(() => expect(btn4h).toBeDisabled());
  expect(screen.getByText(/Scanning/i)).toBeInTheDocument();

  resolveScan({ data: {} });
  await waitFor(() => expect(btn4h).not.toBeDisabled());
});
