const express = require('express');
const { getSettings, updateSettings } = require('../db/settingsStore');
const { isSocialConfigured } = require('../services/socialService');
const { sendTestNotification } = require('../services/notificationService');

module.exports = function createSettingsRouter({ onIntervalChange } = {}) {
  const router = express.Router();

  router.get('/', (req, res) => {
    const settings = getSettings();
    res.json({
      success: true,
      settings: {
        ...settings,
        socialDataConfigured: isSocialConfigured(),
      },
    });
  });

  router.put('/', (req, res) => {
    try {
      const before = getSettings();
      const updated = updateSettings(req.body || {});
      res.json({
        success: true,
        settings: { ...updated, socialDataConfigured: isSocialConfigured() },
      });
      if (onIntervalChange && updated.scanIntervalMinutes !== before.scanIntervalMinutes) {
        onIntervalChange();
      }
    } catch (err) {
      res.status(400).json({ success: false, error: err.message });
    }
  });

  router.post('/test-notification', async (req, res) => {
    const settings = getSettings();
    if (!settings.telegramEnabled && !settings.discordEnabled) {
      return res.status(400).json({
        success: false,
        error: 'Aktifkan dan isi konfigurasi Telegram atau Discord terlebih dahulu.',
      });
    }
    const result = await sendTestNotification();
    res.json({ success: true, result });
  });

  return router;
};
