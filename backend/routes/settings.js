const express = require('express');
const { getSettings, updateSettings } = require('../db/settingsStore');
const { isSocialConfigured } = require('../services/socialService');

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

  return router;
};
