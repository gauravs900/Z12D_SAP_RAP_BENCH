# The $12 Server Challenge — SAP RAP OData V4

An enterprise-grade, high-performance implementation of the **Twelve Dollar Server Challenge** built natively on the **SAP RESTful Application Programming Model (RAP)** with **OData V4**, deployed on the SAP ABAP Platform with SAP HANA.

---

## 🌟 Highlights

- **Native ABAP RAP Architecture**: Managed Behavior Definition with Unmanaged Save, fully declarative CDS View Entities, and OData V4 exposure.
- **Late Numbering (`late numbering`)**: Monotonic primary key assignment serialized via table enqueue locks (`ENQUEUE_E_TABLE`), preventing race conditions and duplicate key dumps under extreme concurrency.
- **High-Concurrency Likes**: Custom bound action `likePost` decorated with `( lock: none )` to eliminate lock queue contention on viral posts.
- **Ultra-Fast Parallel Data Seeding**: `ZCL_12D_SEED_DATA_LOADER` leverages modern `CL_ABAP_PARALLEL` to generate and insert 50,000 users, 500,000 posts, and 2,000,000 likes in **~60 seconds** across parallel background work processes.
- **100% abapGit Ready**: Clean source tree compatible with abapGit for one-click import into any SAP BTP ABAP Environment or S/4HANA ABAP system.
- **Automated Verification**: Complete ABAP Unit test suite (`ZCL_12D_UNIT_TESTS`), API test harness (`test/test.sh`) with golden file comparison, and k6 load benchmark (`bench/load.js`).

---

## 📁 Repository Structure

```text
Z12D_SAP_RAP_BENCH/
├── .abapgit.xml                    # abapGit configuration (Starting folder: /src/)
├── SPEC.md                         # API specification & OData V4 contract
├── LICENSE                         # MIT License
├── .gitignore                      # Git ignore rules
├── src/                            # Native SAP ABAP source files & XML metadata
│   ├── z12d_users.tabl.xml         # DDIC Transparent Table: Users
│   ├── z12d_posts.tabl.xml         # DDIC Transparent Table: Posts
│   ├── z12d_likes.tabl.xml         # DDIC Transparent Table: Likes
│   ├── zi_12d_user.ddls.asddls     # CDS View: Basic User Entity
│   ├── zi_12d_like.ddls.asddls     # CDS View: Basic Like Entity
│   ├── zi_12d_post_likecount.ddls.asddls # CDS View: Aggregate Like Count
│   ├── zi_12d_post.ddls.asddls     # CDS View: Root Post Interface View
│   ├── zc_12d_post.ddls.asddls     # CDS View: Consumption / Projection View
│   ├── zi_12d_post.bdef.asbdef     # RAP Behavior Definition (Interface)
│   ├── zc_12d_post.bdef.asbdef     # RAP Behavior Definition (Consumption)
│   ├── zbp_i_12d_post.clas.abap    # Behavior Pool Implementation Class
│   ├── z12d_feed_srvd.srvd.srvdsrv # Service Definition
│   ├── z12d_feed_srvb_o4.srvb.xml  # Service Binding (OData V4 Web API)
│   ├── zcl_12d_seed_data_loader.clas.abap # Parallel Seed Data Generator (CL_ABAP_PARALLEL)
│   └── zcl_12d_unit_tests.clas.abap       # ABAP Unit Tests
├── test/
│   ├── test.sh                     # Automated API test suite (curl + python3)
│   └── golden/                     # Golden response snapshots for parity validation
│       ├── feed.json
│       ├── post-1.json
│       ├── post-250000.json
│       └── post-500000.json
└── bench/
    └── load.js                     # k6 scenario with automated CSRF recovery
```

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

### 3. Generate Seed Data in Parallel (~60 seconds)

The challenge dataset requires **50,000 users**, **500,000 posts**, and **2,000,000 likes**.

To generate and insert this entire dataset in approximately 60 seconds:
1. Open class `ZCL_12D_SEED_DATA_LOADER` in ADT.
2. Press <kbd>F9</kbd> (**Run as ABAP Application (Console)**).
3. The loader uses `CL_ABAP_PARALLEL` to dispatch 8 parallel child worker tasks:
   - Chunked batch database inserts (`INSERT z12d_posts FROM TABLE ... ACCEPTING DUPLICATE KEYS`).
   - Deterministic user/post generation matching the golden test data.

---

## 🧪 Running Tests

### ABAP Unit Tests (ADT)
Run native ABAP unit tests to test CRUD behavior, validations, and like operations inside the kernel:
1. Open `ZCL_12D_UNIT_TESTS` in ADT.
2. Press <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>F10</kbd> (**Run ABAP Unit Test**).

### Automated API Test Suite
Run the automated black-box test suite against the live HTTP endpoint using `bash test/test.sh`:

```bash
bash test/test.sh <url> <client> <user> <password>
```

#### Example
```bash
bash test/test.sh http://vhcala4hci:50000 001 username "password"
```

All 4 arguments (`<url>`, `<client>`, `<user>`, `<password>`) are strictly required.


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

Run high-concurrency benchmarks simulating real-world reading, liking, and post creation directly with `k6 run bench/load.js`.

### Configuration Options

All benchmark parameters can be configured using `-e KEY=VALUE`:

| Variable | Description | Default |
|---|---|---|
| `BASE_URL` | SAP System Host & Port | `http://vhcala4hci:50000` |
| `SAP_CLIENT` | SAP Client | `001` |
| `SAP_USER` | SAP Username (Basic Auth) | `username` |
| `SAP_PASSWORD` | SAP Password (Basic Auth) | `password` |
| `SAP_TOKEN` | Bearer Token (OAuth 2.0 / IAS) | `""` |
| `VUS` | Concurrent Virtual Users | `100` |
| `DURATION` | Steady-state load duration | `5m` |
| `RAMP_UP` | Ramp-up duration to target VUs | `60s` |
| `ODATA_PATH` | OData V4 service binding path | `/sap/opu/odata4/sap/z12d_feed_srvb_o4/srvd_a2x/sap/z12d_feed_srvd/0001` |
| `ACTION_NAME` | RAP bound action name for likes | `com.sap.gateway.srvd_a2x.z12d_feed_srvd.v0001.likePost` |

---

### Command Examples

#### 1. Quick Start (Default Host, Client, and 100 VUs)
```bash
k6 run \
  -e SAP_USER=username \
  -e SAP_PASSWORD="password" \
  bench/load.js
```

#### 2. Full Customized Run (URL, Client, User, Pass, VUs, and Duration)
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

#### 3. High-Concurrency Run with Bearer Token (e.g. 1,000 VUs)
```bash
k6 run \
  -e BASE_URL="http://vhcala4hci:50000" \
  -e SAP_CLIENT="001" \
  -e SAP_TOKEN="<jwt-bearer-token>" \
  -e VUS=1000 \
  -e DURATION="5m" \
  bench/load.js
```

---

### Automatic CSRF Negotiation
In SAP Gateway OData V4, CSRF protection is hardcoded in the kernel. When scaling to high concurrency (e.g. 1,000+ VUs), Gateway sessions periodically cycle. `bench/load.js` includes an automatic retry handler (`postWithCsrfRetry`) that detects `403 CSRF_Token_Missing`, silently fetches a fresh token, and replays the request without dropping transactions.

---

## ⚙️ Architecture & Concurrency Optimizations

1. **Analytical Pushdown via CDS View Entities**:
   - `ZI_12D_POST_LIKECOUNT` aggregates likes per post with `COUNT(*)` at the SAP HANA database layer, completely eliminating N+1 queries.
2. **Lock Optimization on High-Traffic Posts**:
   - Marking `action ( lock: none ) likePost` in `ZI_12D_POST` prevents exclusive locks on popular posts, enabling thousands of concurrent users to like the same post simultaneously.
3. **Late Numbering Serialization**:
   - In `adjust_numbers`, sequence generation runs under `ENQUEUE_E_TABLE` on table `Z12D_POSTS` with `_wait = abap_true`, preventing key collisions and gaps during concurrent post submissions.
4. **Fast Parallel Data Seeding**:
   - Distributes insertion workloads across all dialog work processes with `CL_ABAP_PARALLEL`, populating 2.5 million rows in ~60 seconds.

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

