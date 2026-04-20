import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  vus: 30,
  duration: '5m'
};

export default function () {
  const payload = JSON.stringify({ payload: `job-${__VU}-${__ITER}` });
  http.post('http://api.platform.local/enqueue', payload, {
    headers: { 'Content-Type': 'application/json' },
  });
  sleep(0.1);
}
