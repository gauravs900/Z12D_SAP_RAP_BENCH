# Simple RAP benchmark — SAP RAP OData V4

This benchmark is inspired by **Twelve Dollar Server Challenge** https://github.com/arjaythedev/twelve-dollar-server-challenge built natively on the **SAP RESTful Application Programming Model (RAP)** with **OData V4**, deployed on the SAP ABAP Platform with SAP HANA.

[`SPEC.md`](SPEC.md) This document defines the API specification and runtime contract

---

## 🚀 Getting Started

### 1. Import via abapGit

1. In **ABAP Development Tools (ADT)** or SAP GUI with **abapGit**:
   - Clone or import this repository into package `Z12D_BENCH`.
2. Activate all objects in the package:
   - Tables: `Z12D_USERS`, `Z12D_POSTS`, `Z12D_LIKES`
   - Data Definitions: `ZI_12D_USER`, `ZI_12D_LIKE`, `ZI_12D_POST_LIKECOUNT`, `ZI_12D_POST`, `ZC_12D_POST`
   - Behavior Definitions: `ZI_12D_POST`, `ZC_12D_POST`
   - Classes: `ZBP_I_12D_POST`, `ZCL_12D_SEED_DATA_LOADER`, `ZCL_12D_UNIT_TESTS`
   - Service Definition: `Z12D_FEED_SRVD`
   - Service Binding: `Z12D_FEED_SRVB_O4`

### 2. Publish the Service Binding

1. Open `Z12D_FEED_SRVB_O4.srvb` in ADT.
2. Click **Publish**.
3. Note the published Service URL:
   ```text
   /sap/opu/odata4/sap/z12d_feed_srvb_o4/srvd_a2x/sap/z12d_feed_srvd/0001
   ```

### 3. Generate Seed Data

The benchmark dataset requires **50,000 users**, **500,000 posts**, and **2,000,000 likes**.

To generate and insert this entire dataset:
1. Open class `ZCL_12D_SEED_DATA_LOADER` in ADT.
2. Press <kbd>F9</kbd> (**Run as ABAP Application (Console)**).

---

## 🧪 Running Tests

### Automated API Test Suite
Run the automated black-box test suite against the live HTTP endpoint using `bash test/test.sh`:

```bash
bash test/test.sh http://vhcala4hci:50000 001 username "password"
```

The test suite validates:
- Metadata service availability (`GET $metadata`).
- Exact golden match for feed ordering (`GET /Post?$top=20&$orderby=CreatedAt desc,Id desc`).
- Exact golden match for posts `1`, `250000`, and `500000`.
- 404 response on non-existent IDs.
- Post creation via `POST /Post` (Late Numbering sequence verification).
- Feed ordering update with the new post at the top.
- Idempotent liking via bound action `likePost`.
- Like count increment verification.
- Post deletion and feed restoration.

---

## ⚡ Benchmarking with k6

Run high-concurrency benchmarks simulating real-world reading, liking, and post creation for 5 minutes.

```bash
k6 run \
  -e BASE_URL="http://vhcala4hci:50000" \
  -e SAP_CLIENT="001" \
  -e SAP_USER="username" \
  -e SAP_PASSWORD="password" \
  -e VUS=500 \
  -e DURATION="5m" \
  -e RAMP_UP="60s" \
  bench/load.js
```

High-Concurrency Run with Bearer Token (e.g. 1,000 VUs)
```bash
k6 run \
  -e BASE_URL="http://vhcala4hci:50000" \
  -e SAP_CLIENT="001" \
  -e SAP_TOKEN="<jwt-bearer-token>" \
  -e VUS=1000 \
  -e DURATION="5m" \
  bench/load.js
```

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

