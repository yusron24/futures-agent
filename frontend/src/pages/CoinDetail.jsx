import { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import PriceChart from '../components/PriceChart';
import ScoreBadge, { BigMoveBadge } from '../components/ScoreBadge';
import { CardSkeleton } from '../components/Skeleton';
import CoinAvatar from '../components/CoinAvatar';
import { getCoinDetail, addToWatchlist, removeFromWatchlist, getWatchlist } from '../api/client';
import { formatPrice, formatPercent, formatUsdCompact, changeColor } from '../utils/format';

const WEIGHT_ITEMS = [
  { key: 'volumeSpike', label: 'Volume Spike' },
  { key: 'priceMomentum', label: 'Momentum' },
  { key: 'volatility', label: 'Volatilitas' },
  { key: 'rsi', label: 'RSI' },
  { key: 'social', label: 'Sosial' },
  { key: 'onchain', label: 'On-Chain' },
];

export default function CoinDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [inWatchlist, setInWatchlist] = useState(false);

  useEffect(() => {
    setLoading(true);
    setError(null);
    getCoinDetail(id)
      .then(setData)
      .catch((err) => setError(err.response?.data?.error || 'Gagal memuat detail koin.'))
      .finally(() => setLoading(false));

    getWatchlist()
      .then((list) => setInWatchlist(list.some((w) => w.coin_id === id)))
      .catch(() => {});
  }, [id]);

  const toggleWatchlist = async () => {
    if (!data) return;
    try {
      if (inWatchlist) {
        await removeFromWatchlist(id);
        setInWatchlist(false);
      } else {
        await addToWatchlist({ id, symbol: data.coin.symbol, name: data.coin.name });
        setInWatchlist(true);
      }
    } catch (err) {
      console.error(err);
    }
  };

  if (loading) {
    return (
      <div className="bg-terminal-panel border border-terminal-border rounded-lg">
        <CardSkeleton />
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="px-4 py-3 rounded bg-terminal-red/10 border border-terminal-red/30 text-terminal-red text-sm">
        {error || 'Koin tidak ditemukan.'}
      </div>
    );
  }

  const { coin, chart, screening, onchain } = data;

  return (
    <div>
      <button onClick={() => navigate(-1)} className="text-xs text-terminal-muted hover:text-terminal-text mb-4">
        ← Kembali
      </button>

      <div className="flex flex-wrap items-start justify-between gap-4 mb-6">
        <div className="flex items-center gap-3">
          <CoinAvatar symbol={coin.symbol} size="lg" />
          <div>
            <h1 className="text-xl font-bold text-terminal-text">
              {coin.symbol} <span className="text-terminal-muted font-normal text-sm">{coin.id}</span>
              {coin.isNew && (
                <span className="ml-2 align-middle text-[10px] px-1.5 py-0.5 rounded bg-terminal-accent/15 text-terminal-accent border border-terminal-accent/30">
                  NEW
                </span>
              )}
            </h1>
            <div className="text-2xl font-mono mt-1">{formatPrice(coin.price)}</div>
          </div>
        </div>

        <div className="flex items-center gap-3">
          {screening && screening.score >= 75 && <BigMoveBadge />}
          {screening && <ScoreBadge score={screening.score} size="lg" />}
          <button
            onClick={toggleWatchlist}
            className={`px-3 py-2 rounded border text-sm font-semibold transition-colors ${
              inWatchlist
                ? 'bg-terminal-amber/15 text-terminal-amber border-terminal-amber/40'
                : 'bg-terminal-accent/10 text-terminal-accent border-terminal-accent/30 hover:bg-terminal-accent/20'
            }`}
          >
            {inWatchlist ? '★ Di Watchlist' : '☆ Tambah Watchlist'}
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div className="lg:col-span-2 bg-terminal-panel border border-terminal-border rounded-lg p-4">
          <div className="text-sm text-terminal-muted mb-2">Chart Harga 7 Hari</div>
          <PriceChart prices={chart.prices} />
        </div>

        <div className="bg-terminal-panel border border-terminal-border rounded-lg p-4 space-y-3">
          <div className="text-sm text-terminal-muted mb-1">Metrik</div>
          <MetricRow label="Perubahan 24h" value={formatPercent(coin.change24h)} color={changeColor(coin.change24h)} />
          <MetricRow label="Perubahan 7d" value={formatPercent(coin.change7d)} color={changeColor(coin.change7d)} />
          <MetricRow label="High 24h" value={formatPrice(coin.high24h)} />
          <MetricRow label="Low 24h" value={formatPrice(coin.low24h)} />
          <MetricRow label="Volume 24h (USDT)" value={formatUsdCompact(coin.volume24h)} />
          <MetricRow label="Rank Volume" value={screening ? `#${screening.volumeRank ?? '-'}` : '-'} />
          {screening && (
            <>
              <hr className="border-terminal-border" />
              <MetricRow label="RSI (14)" value={screening.rsi != null ? screening.rsi.toFixed(1) : 'n/a'} />
              <MetricRow
                label="MACD Histogram"
                value={screening.macdHistogram != null ? screening.macdHistogram.toFixed(4) : 'n/a'}
              />
              <MetricRow label="Volume Spike" value={screening.volumeRatio != null ? `${screening.volumeRatio.toFixed(2)}x` : 'n/a'} />
              <MetricRow label="Volatilitas 24h" value={`${screening.volatilityPct?.toFixed(2)}%`} />
              <MetricRow
                label="Sosial"
                value={
                  screening.socialAvailable
                    ? `${screening.social.score.toFixed(0)}/100`
                    : 'n/a (belum ada API key)'
                }
              />
            </>
          )}
        </div>
      </div>

      <div className="mt-4 bg-terminal-panel border border-terminal-border rounded-lg p-4">
        <div className="flex items-center gap-2 mb-3">
          <span className="text-sm text-terminal-muted">Metrik On-Chain</span>
          {onchain && (
            <span
              className={`text-[10px] px-1.5 py-0.5 rounded border ${
                onchain.source === 'live'
                  ? 'bg-terminal-green/15 text-terminal-green border-terminal-green/40'
                  : 'bg-terminal-muted/10 text-terminal-muted border-terminal-muted/30'
              }`}
            >
              {onchain.source === 'live' ? 'LIVE' : 'DUMMY (contoh)'}
            </span>
          )}
          {onchain?.isProxy && (
            <span className="text-[10px] text-terminal-muted">proxy dari {onchain.proxySource}</span>
          )}
        </div>
        {!onchain ? (
          <div className="text-xs text-terminal-muted">Data on-chain tidak tersedia.</div>
        ) : (
          <>
            {onchain.source !== 'live' && (
              <p className="text-[11px] text-terminal-muted mb-3">
                Belum ada API key CryptoQuant/Whale Alert dikonfigurasi — angka di bawah adalah data contoh
                (struktur sama seperti data asli) dan <b>tidak</b> ikut memengaruhi skor. Atur di halaman Pengaturan.
              </p>
            )}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              <OnchainStat label="Exchange Inflow 24h" value={formatUsdCompact(onchain.exchangeInflow24hUsd)} />
              <OnchainStat label="Exchange Outflow 24h" value={formatUsdCompact(onchain.exchangeOutflow24hUsd)} />
              <OnchainStat
                label="Net Flow 24h"
                value={formatUsdCompact(onchain.netFlow24hUsd)}
                color={onchain.netFlow24hUsd < 0 ? 'text-terminal-green' : 'text-terminal-red'}
              />
              <OnchainStat
                label="Supply di Exchange"
                value={`${onchain.supplyOnExchangesPct?.toFixed(2) ?? '-'}%`}
              />
              <OnchainStat
                label="Perubahan Supply 24h"
                value={formatPercent(onchain.supplyOnExchangesChange24h)}
                color={changeColor(-onchain.supplyOnExchangesChange24h)}
              />
              <OnchainStat
                label={`Whale Tx ${onchain.whaleWindowMinutes ? `(${onchain.whaleWindowMinutes}m)` : '(contoh)'}`}
                value={onchain.whaleTxCountRecent}
              />
              <OnchainStat label="Whale → Exchange" value={onchain.whaleToExchangeCount} color="text-terminal-red" />
              <OnchainStat label="Whale ← Exchange" value={onchain.whaleFromExchangeCount} color="text-terminal-green" />
            </div>
          </>
        )}
      </div>

      {screening && (
        <div className="mt-4 bg-terminal-panel border border-terminal-border rounded-lg p-4">
          <div className="text-sm text-terminal-muted mb-2">Rincian Skor Potensi</div>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 text-center">
            {WEIGHT_ITEMS.map(({ key, label }) => {
              const value = screening.scoreBreakdown?.[key];
              const weightPct = screening.scoreWeights ? Math.round(screening.scoreWeights[key] * 100) : null;
              return (
                <ScoreItem
                  key={key}
                  label={`${label}${weightPct != null ? ` (${weightPct}%)` : ''}`}
                  value={value != null ? value : 'n/a'}
                />
              );
            })}
          </div>
          {screening.scoreBreakdown?.onchain == null && (
            <p className="text-[11px] text-terminal-muted mt-3">
              Bobot On-Chain dialihkan proporsional ke metrik lain karena data on-chain live belum tersedia untuk koin ini.
            </p>
          )}
        </div>
      )}
    </div>
  );
}

function MetricRow({ label, value, color = 'text-terminal-text' }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="text-terminal-muted">{label}</span>
      <span className={`font-mono ${color}`}>{value}</span>
    </div>
  );
}

function ScoreItem({ label, value }) {
  return (
    <div className="bg-terminal-bg border border-terminal-border rounded p-3">
      <div className="text-lg font-bold text-terminal-accent">{value}</div>
      <div className="text-[10px] text-terminal-muted mt-1">{label}</div>
    </div>
  );
}

function OnchainStat({ label, value, color = 'text-terminal-text' }) {
  return (
    <div className="bg-terminal-bg border border-terminal-border rounded p-3">
      <div className={`text-sm font-mono font-semibold ${color}`}>{value}</div>
      <div className="text-[10px] text-terminal-muted mt-1">{label}</div>
    </div>
  );
}
