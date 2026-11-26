import { check } from 'k6';
import http from 'k6/http';
import { Trend } from 'k6/metrics';

const baseUrl = __ENV.ECOTRACK_BASE_URL || 'http://127.0.0.1:58000';
const token = __ENV.ECOTRACK_ACCESS_TOKEN;
const mapLatency = new Trend('map_latency', true);
const stepsLatency = new Trend('steps_latency', true);
const statsLatency = new Trend('stats_latency', true);
export const options = {
  scenarios: {
    mixed_mvp_workload: {
      executor: 'ramping-vus',
      startVUs: 5,
      stages: [
        { duration: '15s', target: 30 },
        { duration: '45s', target: 30 },
        { duration: '10s', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<120', 'p(50)<50'],
    http_req_failed: ['rate==0'],
    checks: ['rate==1'],
  },
};

export default function () {
  if (!token) {
    check(http.get(baseUrl + '/readyz'), { 'ready 200': (reply) => reply.status === 200 });
    return;
  }
  const headers = { Authorization: `Bearer ${token}` };
  const map = http.get(
    baseUrl + '/api/v1/map/waste-points'
      + '?min_lat=55.70&min_lon=37.50&max_lat=55.80&max_lon=37.70&zoom=14&fractions=plastic',
    { headers },
  );
  check(map, { 'map 200': (reply) => reply.status === 200 });
  mapLatency.add(map.timings.duration);
  const todayMoscow = new Date(Date.now() + 180 * 60_000).toISOString().slice(0, 10);
  const steps = http.put(
    baseUrl + '/api/v1/activity/steps/daily',
    JSON.stringify({ activity_date: todayMoscow, timezone_offset_minutes: 180, raw_sensor_steps: 6400 }),
    { headers: { ...headers, 'Content-Type': 'application/json', 'Idempotency-Key': crypto.randomUUID() } },
  );
  check(steps, { 'steps 200': (reply) => reply.status === 200 });
  stepsLatency.add(steps.timings.duration);
  const stats = http.get(baseUrl + '/api/v1/stats/emissions?period=days', { headers });
  check(stats, { 'stats 200': (reply) => reply.status === 200 });
  statsLatency.add(stats.timings.duration);
}
