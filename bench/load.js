/**
 * SAP RAP OData V4 Load Test Script for k6
 * Converted from bench/load.js for Standard SAP RAP Architecture
 *
 * Simulates virtual users (VUs) browsing the RAP feed, reading posts,
 * liking posts via RAP Actions (with UserId parameter), and creating new posts.
 *
 * Target Endpoint:
 *   http://vhcala4hci:50000/sap/opu/odata4/sap/z12d_feed_srvb_o4/srvd_a2x/sap/z12d_feed_srvd/0001
 *
 * Usage:
 *   k6 run -e SAP_USER=<user> -e SAP_PASSWORD=<pass> bench/load.js
 *   k6 run -e BASE_URL=http://vhcala4hci:50000 -e SAP_CLIENT=001 -e SAP_USER=<user> -e SAP_PASSWORD=<pass> -e VUS=250 -e DURATION=5m bench/load.js
 *   k6 run -e SAP_TOKEN=<bearer-token> -e VUS=500 bench/load.js
 *
 * Environment Variables:
 *   BASE_URL      SAP system URL (default: http://vhcala4hci:50000)
 *   ODATA_PATH    OData V4 service path (default: /sap/opu/odata4/sap/z12d_feed_srvb_o4/srvd_a2x/sap/z12d_feed_srvd/0001)
 *   SAP_CLIENT    SAP Client (default: 001)
 *   ACTION_NAME   RAP bound action name (default: com.sap.gateway.srvd.z12d_feed_srvd.v0001.likePost)
 *   SAP_USER      SAP User for Basic Auth
 *   SAP_PASSWORD  SAP Password for Basic Auth
 *   SAP_TOKEN     Bearer Token (OAuth 2.0 / IAS) if not using Basic Auth
 *   VUS           Concurrent Virtual Users (default: 100)
 *   DURATION      Hold duration (default: 5m)
 *   RAMP_UP       Ramp up time (default: 60s)
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import encoding from 'k6/encoding';

// --- Configuration -----------------------------------------------------------
const BASE_URL = (__ENV.BASE_URL || 'http://vhcala4hci:50000').replace(/\/+$/, '');
const ODATA_PATH = (__ENV.ODATA_PATH || '/sap/opu/odata4/sap/z12d_feed_srvb_o4/srvd_a2x/sap/z12d_feed_srvd/0001').replace(/^\/+/, '');
const SERVICE_URL = `${BASE_URL}/${ODATA_PATH}`;
const SAP_CLIENT = __ENV.SAP_CLIENT || '001';
const ACTION_NAME = __ENV.ACTION_NAME || 'com.sap.gateway.srvd_a2x.z12d_feed_srvd.v0001.likePost';

const SAP_USER = __ENV.SAP_USER || '';
const SAP_PASSWORD = __ENV.SAP_PASSWORD || '';
const SAP_TOKEN = __ENV.SAP_TOKEN || '';

const VUS = Number(__ENV.VUS || 100);
const LIKE_PROB = Number(__ENV.LIKE_PROB !== undefined ? __ENV.LIKE_PROB : 0.15);
const POST_PROB = Number(__ENV.POST_PROB !== undefined ? __ENV.POST_PROB : 0.02);

export const options = {
  scenarios: {
    users: {
      executor: 'ramping-vus',
      stages: [
        { duration: __ENV.RAMP_UP || '60s', target: VUS },
        { duration: __ENV.DURATION || '5m', target: VUS },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.01'],
  },
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

const between = (lo, hi) => lo + Math.random() * (hi - lo);

function getAuthHeader() {
  if (SAP_TOKEN) {
    return `Bearer ${SAP_TOKEN}`;
  }
  if (SAP_USER && SAP_PASSWORD) {
    return `Basic ${encoding.b64encode(`${SAP_USER}:${SAP_PASSWORD}`)}`;
  }
  return '';
}

// Per-VU CSRF token storage
let csrfToken = '';

export default function () {
  const authHeader = getAuthHeader();
  const commonHeaders = {
    'Accept': 'application/json',
  };
  if (authHeader) {
    commonHeaders['Authorization'] = authHeader;
  }
  if (SAP_CLIENT) {
    commonHeaders['sap-client'] = SAP_CLIENT;
  }

  const clientParam = SAP_CLIENT ? `sap-client=${SAP_CLIENT}` : '';

  // Spread out VUs that start in the same tick
  if (__ITER === 0) {
    sleep(between(0, 5));
  }

  // 1. GET /Post (Feed - 20 newest posts)
  // Request x-csrf-token: fetch so SAP returns a fresh CSRF token for subsequent state modifications
  const feedHeaders = {
    ...commonHeaders,
    'x-csrf-token': 'fetch',
  };

  const feedQuery = `$top=20&$orderby=CreatedAt%20desc,Id%20desc${clientParam ? '&' + clientParam : ''}`;
  const feedUrl = `${SERVICE_URL}/Post?${feedQuery}`;
  const feedRes = http.get(feedUrl, { headers: feedHeaders, tags: { name: 'GET /Post (Feed)' } });

  const feedOk = check(feedRes, {
    'feed 200': (r) => r.status === 200,
  });

  if (!feedOk) {
    sleep(between(3, 7));
    return;
  }

  // Update CSRF token if returned by SAP Gateway
  const returnedToken = feedRes.headers['X-Csrf-Token'] || feedRes.headers['x-csrf-token'];
  if (returnedToken && returnedToken !== 'Required') {
    csrfToken = returnedToken;
  }

  // Parse OData V4 response (array is located in 'value' field)
  const posts = feedRes.json('value');
  if (!posts || posts.length === 0) {
    sleep(between(3, 7));
    return;
  }

  const post = posts[Math.floor(Math.random() * posts.length)];
  sleep(between(3, 7));

  // 2. GET /Post(:id) (Read single post)
  const postUrl = `${SERVICE_URL}/Post(${post.Id})${clientParam ? '?' + clientParam : ''}`;
  const postRes = http.get(postUrl, { headers: commonHeaders, tags: { name: 'GET /Post(:id)' } });
  check(postRes, {
    'post 200': (r) => r.status === 200,
  });

  sleep(between(3, 8));

  // Headers for state-changing requests (POST)
  const postHeaders = {
    ...commonHeaders,
    'Content-Type': 'application/json',
  };
  if (csrfToken) {
    postHeaders['x-csrf-token'] = csrfToken;
  }

  // Determine simulated user ID for this VU (cycling through 1..50000 seed users)
  const currentUserId = Number(__ENV.USER_ID || ((__VU - 1) % 50000) + 1);

  // Helper to execute POST with automatic CSRF re-fetch & retry on HTTP 403
  function postWithCsrfRetry(url, payload, headers, tag) {
    if (!headers['x-csrf-token'] && !csrfToken) {
      const initUrl = `${SERVICE_URL}/Post?$top=1${clientParam ? '&' + clientParam : ''}`;
      const initRes = http.get(initUrl, {
        headers: { ...commonHeaders, 'x-csrf-token': 'fetch' },
        tags: { name: 'GET /Post (CSRF Init)' },
      });
      const initTok = initRes.headers['X-Csrf-Token'] || initRes.headers['x-csrf-token'];
      if (initTok && initTok !== 'Required') {
        csrfToken = initTok;
        headers['x-csrf-token'] = initTok;
      }
    }
    let res = http.post(url, payload, { headers, tags: { name: tag } });
    if (res.status === 403 && (res.body.includes('CSRF') || res.headers['x-csrf-token'] === 'Required' || res.headers['X-Csrf-Token'] === 'Required')) {
      const refreshUrl = `${SERVICE_URL}/Post?$top=1${clientParam ? '&' + clientParam : ''}`;
      const refreshRes = http.get(refreshUrl, {
        headers: { ...commonHeaders, 'x-csrf-token': 'fetch' },
        tags: { name: 'GET /Post (CSRF Refresh)' },
      });
      const newToken = refreshRes.headers['X-Csrf-Token'] || refreshRes.headers['x-csrf-token'];
      if (newToken && newToken !== 'Required') {
        csrfToken = newToken;
        const retryHeaders = { ...headers, 'x-csrf-token': newToken };
        res = http.post(url, payload, { headers: retryHeaders, tags: { name: tag } });
      }
    }
    return res;
  }

  // 3. POST /Post(:id)/likePost (RAP Bound Action - 15% probability)
  // Passes UserId parameter in JSON payload so the database reflects which user liked the post
  if (Math.random() < LIKE_PROB) {
    const likeUrl = `${SERVICE_URL}/Post(${post.Id})/${ACTION_NAME}${clientParam ? '?' + clientParam : ''}`;
    const likePayload = JSON.stringify({
      UserId: currentUserId,
    });
    const likeRes = postWithCsrfRetry(likeUrl, likePayload, postHeaders, 'POST /Post(:id)/likePost');
    const likeOk = check(likeRes, {
      'like 200/201/204': (r) => r.status === 200 || r.status === 201 || r.status === 204,
    });
    if (!likeOk) {
      console.error(`[LIKE FAILED] Post ${post.Id} - HTTP ${likeRes.status}: ${likeRes.body}`);
    }
  }

  // 4. POST /Post (Create post - 2% probability)
  if (Math.random() < POST_PROB) {
    const createUrl = `${SERVICE_URL}/Post${clientParam ? '?' + clientParam : ''}`;
    const bodyContent = `User ${currentUserId} says hi at ${new Date().toISOString()} (VU ${__VU}, iter ${__ITER})`;
    const createPayload = JSON.stringify({
      UserId: currentUserId,
      Body: bodyContent,
    });

    const createRes = postWithCsrfRetry(createUrl, createPayload, postHeaders, 'POST /Post');
    const createOk = check(createRes, {
      'create 201': (r) => r.status === 201,
    });
    if (!createOk) {
      console.error(`[CREATE FAILED] HTTP ${createRes.status}: ${createRes.body}`);
    }
  }

  sleep(between(5, 15));
}
