require('dotenv').config();
const express = require('express');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');

const coinsRouter = require('./routes/coins');
const watchlistRouter = require('./routes/watchlist');
const signalsRouter = require('./routes/signals');
const categoriesRouter = require('./routes/categories');
const { startScheduler, THRESHOLD } = require('./services/scheduler');
const { getLatestScreening } = require('./services/screeningService');
const { socialConfigured } = require('./services/socialService');

const app = express();
const server = http.createServer(app);

const CORS_ORIGIN = process.env.CORS_ORIGIN || 'http://localhost:5173';
const io = new Server(server, { cors: { origin: CORS_ORIGIN } });

app.use(cors({ origin: CORS_ORIGIN }));
app.use(express.json());

app.get('/api/health', (req, res) => {
  const latest = getLatestScreening();
  res.json({
    success: true,
    status: 'ok',
    lastScreeningAt: latest.updatedAt,
    isRunning: latest.isRunning,
    signalThreshold: THRESHOLD,
    scanIntervalMinutes: parseInt(process.env.SCAN_INTERVAL_MINUTES || '5', 10),
    detailedCoinsLimit: parseInt(process.env.DETAILED_COINS_LIMIT || '60', 10),
    socialDataConfigured: socialConfigured,
    coingeckoApiKeyConfigured: Boolean(process.env.COINGECKO_API_KEY),
  });
});

app.use('/api/coins', coinsRouter);
app.use('/api/watchlist', watchlistRouter);
app.use('/api/signals', signalsRouter);
app.use('/api/categories', categoriesRouter);

app.use((req, res) => {
  res.status(404).json({ success: false, error: 'Not found' });
});

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error('[unhandled]', err);
  res.status(500).json({ success: false, error: 'Internal server error' });
});

io.on('connection', (socket) => {
  console.log(`[socket] client connected: ${socket.id}`);
  const latest = getLatestScreening();
  if (latest.updatedAt) {
    socket.emit('screening:update', {
      updatedAt: latest.updatedAt,
      count: latest.coins.length,
      topCoins: latest.coins.slice(0, 20),
    });
  }
  socket.on('disconnect', () => console.log(`[socket] client disconnected: ${socket.id}`));
});

const PORT = process.env.PORT || 5000;
server.listen(PORT, () => {
  console.log(`Altcoin screener backend listening on port ${PORT}`);
  startScheduler(io);
});
