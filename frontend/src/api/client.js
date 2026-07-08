import axios from 'axios';

export const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:5000';

const client = axios.create({ baseURL: API_URL, timeout: 20000 });

export async function getScreening(params = {}) {
  const { data } = await client.get('/api/coins/screening', { params });
  return data;
}

export async function getCoinDetail(id) {
  const { data } = await client.get(`/api/coins/${id}`);
  return data;
}

export async function getWatchlist() {
  const { data } = await client.get('/api/watchlist');
  return data.watchlist;
}

export async function addToWatchlist(coin) {
  const { data } = await client.post('/api/watchlist', {
    coinId: coin.id,
    symbol: coin.symbol,
    name: coin.name,
    alertThreshold: coin.alertThreshold ?? 75,
  });
  return data;
}

export async function removeFromWatchlist(coinId) {
  const { data } = await client.delete(`/api/watchlist/${coinId}`);
  return data;
}

export async function getSignalHistory(params = {}) {
  const { data } = await client.get('/api/signals', { params });
  return data.signals;
}

export async function getCategories() {
  const { data } = await client.get('/api/categories');
  return data.categories;
}

export async function getHealth() {
  const { data } = await client.get('/api/health');
  return data;
}

export async function getSettings() {
  const { data } = await client.get('/api/settings');
  return data.settings;
}

export async function updateSettings(partial) {
  const { data } = await client.put('/api/settings', partial);
  return data;
}

export async function testNotification() {
  const { data } = await client.post('/api/settings/test-notification');
  return data;
}

export default client;
