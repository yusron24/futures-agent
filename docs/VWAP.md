# VWAP (Volume Weighted Average Price)

Indikator VWAP: garis harga rata-rata tertimbang volume + **3 band atas & 3 band
bawah** (deviasi standar tertimbang volume). Dipakai di chart dan sebagai
**konfluens/konfirmasi** sinyal (bukan satu-satunya sumber keputusan).

## Rumus

- Typical price: `tp = (high + low + close) / 3`
- VWAP: `Σ(tp·volume) / Σ(volume)`
- Deviasi (tertimbang volume): `std = sqrt(Σ(volume·(tp − vwap)²) / Σ volume)`
- Band ke-k: `vwap ± multₖ · std` (default `mult1/2/3 = 1/2/3`)

Bila `Σ volume = 0` (feed volume kosong/telat), otomatis fallback ke rata-rata
aritmetik `tp` dan std populasi — tidak pernah NaN/crash.

## Mode / anchoring

Dapat dipilih di **Pengaturan → VWAP**:

- **Rolling** (default): jendela bergulir `period` candle terakhir (default 20,
  dapat diatur 5–100). Selalu terdefinisi, stabil di semua timeframe, tanpa
  logika sesi.
- **Anchored harian (UTC)**: akumulasi reset tiap pergantian hari UTC (VWAP
  harian klasik).

## Modul

- `lib/indicators/vwap.dart`
  - `enum VwapMode { rolling, anchoredDaily }`
  - `class VwapConfig` — konfigurasi global (mode/period/mult/enabledForSignals)
    yang dibaca **chart & strategi** agar hasil konsisten. Diisi dari
    `SettingsRepository` via `AppState.applyVwapSettings()` (juga di isolate
    background). Punya default aman → dapat dipakai unit test tanpa setup.
  - `class VwapResult` — 7 deret (`vwap`, `upper1..3`, `lower1..3`) sepanjang
    input (NaN saat warmup) + helper `last`, `at(i)`, `isAligned`, `overExtension`.
  - `class Vwap` — `compute(candles, {mode, period, mult1..3})` dan
    `confluenceOf(candles, direction, price)` → `VwapConfluence`.
- `VwapConfluence.adjust(confidence, {bonus, penalty, overPenalty})` — sesuaikan
  keyakinan strategi: bonus bila searah VWAP, penalti bila melawan, penalti
  tambahan bila overextended (di luar band-3).

## Cara pakai

### Chart
Aktif otomatis bila `Settings.vwapEnabled` = true. `CandlestickChart` menerima
`showVwap: true` (dari `signal_detail_page.dart`) dan menggambar garis VWAP
(emas) + 6 band (putus-putus). VWAP dihitung pada **candles penuh** lalu dipotong
ke jendela tampil agar identik dengan yang dipakai strategi.

### Integrasi sinyal (per-strategi)
VWAP dipakai sebagai konfirmasi pada strategi yang cocok; strategi lain tidak
disentuh:

| Strategi | Peran VWAP |
|---|---|
| **Pullback EMA200** | **Filter keras**: BUY dibatalkan bila harga di bawah VWAP (walau di atas EMA200); SELL sebaliknya. |
| **Breakout Level+Volume** | Breakout searah VWAP → bonus confidence (akumulasi institusi); melawan → penalti besar. |
| **Double Bottom/Top** | Pola di sisi benar VWAP → bonus; berlawanan → penalti. |
| **Liquidity Swap** | VWAP sebagai magnet/target; ditampilkan sebagai referensi TP + penyesuaian confidence. |
| MACD Divergence, MA Crossover+ADX | **Tidak dipakai** (redundan dengan MA). |

Semua penyesuaian dibungkus `if (VwapConfig.enabledForSignals)` sehingga dapat
dimatikan (kembali ke perilaku sebelum VWAP). TP/SL final tetap diatur invariant
RR 1:2,5 di `SignalEngine`; VWAP hanya memengaruhi **confidence & filter**.

## Konsistensi chart ↔ engine ↔ backtest
Chart dan strategi memanggil `Vwap.compute` dengan `VwapConfig` yang **sama**
pada candles penuh, sehingga nilai VWAP identik di tampilan, evaluasi sinyal, dan
saat re-evaluasi historis.

## Test
`test/vwap_test.dart`: volume seragam = SMA typical price; volume berat menarik
VWAP; fallback volume nol; urutan band; reset anchored di batas hari UTC.
