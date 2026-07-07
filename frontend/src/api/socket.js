import { io } from 'socket.io-client';
import { API_URL } from './client';

let socket = null;

export function getSocket() {
  if (!socket) {
    socket = io(API_URL, { autoConnect: true, reconnection: true });
  }
  return socket;
}
