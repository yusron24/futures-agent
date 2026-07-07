import { useEffect } from 'react';
import { getSocket } from '../api/socket';

/**
 * Listens for `watchlist:alert` events pushed from the backend scheduler and
 * fires a browser notification when a watchlisted coin crosses its score
 * threshold. Mount once near the app root.
 */
export default function NotificationManager() {
  useEffect(() => {
    if ('Notification' in window && Notification.permission === 'default') {
      Notification.requestPermission();
    }

    const socket = getSocket();
    const handleAlert = (hits) => {
      hits.forEach((hit) => {
        const title = `🚀 ${hit.symbol} skor ${hit.score}!`;
        const body = `${hit.name} berpotensi pergerakan besar (harga $${hit.price}).`;
        if ('Notification' in window && Notification.permission === 'granted') {
          new Notification(title, { body });
        } else {
          console.info(`[watchlist alert] ${title} - ${body}`);
        }
      });
    };

    socket.on('watchlist:alert', handleAlert);
    return () => socket.off('watchlist:alert', handleAlert);
  }, []);

  return null;
}
