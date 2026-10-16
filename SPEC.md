# API Specification: SAP RAP OData V4

This document defines the API specification and runtime contract for the **Twelve Dollar Server Challenge** implementation built on the **SAP RESTful Application Programming Model (RAP)** with **OData V4**.

The test suite (`test/test.sh`) validates all endpoints and schemas defined here.

---

## 1. Architecture Overview

In this implementation, the feed service runs natively inside the SAP ABAP Platform / SAP HANA kernel via the ABAP RESTful Application Programming Model (RAP).

| Component | Technology | Role |
|---|---|---|
| **Service Model** | ABAP RAP (Managed with Unmanaged Save & Late Numbering) | Business logic, validation, CRUD operations |
| **Protocol** | OData V4 (SAP Gateway JSON) | High-performance RESTful protocol |
| **Data Model** | ABAP Core Data Services (CDS View Entities) | High-speed analytical joins and aggregate projection |
| **Database** | SAP HANA (Columnar Store DDIC Transparent Tables) | In-memory relational storage (`Z12D_USERS`, `Z12D_POSTS`, `Z12D_LIKES`) |
| **Authentication** | HTTP Basic Auth / OAuth 2.0 / SAP Cookie Sessions | Standard enterprise security with kernel-level CSRF protection |

---

## 2. Runtime Contract & Service Endpoints

### Base URL & Service Binding

- **Service Path**: `/sap/opu/odata4/sap/z12d_feed_srvb_o4/srvd_a2x/sap/z12d_feed_srvd/0001`
- **Default Port**: `50000` (HTTP) or `50001` (HTTPS)
- **Required Query Parameter**: `sap-client=001` (or passed via `sap-client` header)
- **Required Headers for Mutating Requests**:
  - `Accept: application/json`
  - `Content-Type: application/json`
  - `x-csrf-token: <valid-token>` (obtained via `GET` request with `x-csrf-token: fetch`)

---

## 3. Data Representation

### Post Entity (`PostType`)

```json
{
  "@odata.context": "$metadata#Post/$entity",
  "Id": 500001,
  "UserId": 1,
  "Body": "Hello world from SAP RAP!",
  "CreatedAt": "2026-10-16T12:00:00.0000000Z",
  "Author": "alice_001",
  "LikeCount": 42
}
```

- **`Id`** (`INT8` / `INT4`): Unique positive integer identifier of the post.
- **`UserId`** (`INT8`): ID of the authoring user in `Z12D_USERS`.
- **`Body`** (`SSTRING500`): Content of the post (1 to 500 characters).
- **`CreatedAt`** (`TIMESTAMPL`): ISO 8601 UTC timestamp with microsecond/nanosecond precision (`YYYY-MM-DDTHH:MM:SS.FFFFFFFZ`).
- **`Author`** (`CHAR50`): Projected from associated `Z12D_USERS.username`.
- **`LikeCount`** (`INT4`): Dynamically aggregated `COUNT(*)` from `Z12D_LIKES` via CDS View `ZI_12D_POST_LIKECOUNT`.

---

## 4. Endpoints & Operations

### 1. Feed: Get Newest Posts
- **HTTP Method**: `GET`
- **Endpoint**: `/Post?$top=20&$orderby=CreatedAt desc,Id desc`
- **Equivalent**: `GET /feed`
- **Response**: `200 OK`
- **Body**:
  ```json
  {
    "@odata.context": "$metadata#Post",
    "value": [
      {
        "Id": 500000,
        "UserId": 2341,
        "Body": "Latest post...",
        "CreatedAt": "2026-10-16T12:00:00.0000000Z",
        "Author": "charlie",
        "LikeCount": 15
      }
    ]
  }
  ```

### 2. Single Post: Get Post by ID
- **HTTP Method**: `GET`
- **Endpoint**: `/Post(:id)` (e.g. `/Post(250000)`)
- **Equivalent**: `GET /posts/:id`
- **Response**: `200 OK`
- **Body**:
  ```json
  {
    "@odata.context": "$metadata#Post/$entity",
    "Id": 250000,
    "UserId": 1024,
    "Body": "Post content...",
    "CreatedAt": "2026-05-10T14:30:15.1230000Z",
    "Author": "bob_42",
    "LikeCount": 8
  }
  ```

### 3. Create Post
- **HTTP Method**: `POST`
- **Endpoint**: `/Post`
- **Equivalent**: `POST /posts`
- **Headers**: `x-csrf-token: <token>`, `Content-Type: application/json`
- **Request Body**:
  ```json
  {
    "UserId": 1,
    "Body": "This is a new post from the benchmark."
  }
  ```
- **Response**: `201 Created`
- **Behavior**:
  - Validates body length (1–500 chars).
  - Automatically captures server timestamp into `CreatedAt`.
  - In Late Numbering (`adjust_numbers`), queries `SELECT MAX(id)` with table enqueue lock `ENQUEUE_E_TABLE` on `Z12D_POSTS` to guarantee atomic sequence numbers without race conditions under concurrency.

### 4. Like Post (RAP Bound Action)
- **HTTP Method**: `POST`
- **Endpoint**: `/Post(:id)/com.sap.gateway.srvd_a2x.z12d_feed_srvd.v0001.likePost`
- **Equivalent**: `POST /posts/:id/like`
- **Headers**: `x-csrf-token: <token>`, `Content-Type: application/json`
- **Request Body**:
  ```json
  {
    "UserId": 100
  }
  ```
- **Response**: `200 OK`
- **Response Body**:
  ```json
  {
    "@odata.context": "$metadata#com.sap.gateway.srvd_a2x.z12d_feed_srvd.v0001.likePost",
    "liked": true,
    "already_liked": false,
    "post_id": 500000
  }
  ```
- **Behavior**:
  - Decorated with `action ( lock: none ) likePost` in RAP Behavior Definition to eliminate lock queue contention on hot posts.
  - Checks if `(user_id, post_id)` exists in `Z12D_LIKES`. If found, returns `already_liked = true`. If not, executes `INSERT z12d_likes` and returns `already_liked = false`.

### 5. Health Check & Metadata
- **HTTP Method**: `GET`
- **Endpoint**: `/$metadata` or `/Post?$top=1`
- **Equivalent**: `GET /health`
- **Response**: `200 OK`

---

## 5. Security & Concurrency Considerations

1. **Kernel CSRF Handling**:
   - In SAP Gateway OData V4, CSRF protection is enforced by the SAP kernel. Clients must fetch a token via `GET` (`x-csrf-token: fetch`) and pass the session cookie along with the token in subsequent `POST` operations.
   - Benchmark clients (`bench/load.js`) implement automatic session refresh and token re-fetching upon encountering `403 CSRF_Token_Missing`.

2. **Late Numbering Serialization**:
   - Primary key assignment is deferred until the save phase (`adjust_numbers`).
   - Concurrency is managed via SAP Lock Concept (`ENQUEUE_E_TABLE` / `DEQUEUE_E_TABLE`), ensuring consecutive monotonic IDs without duplicate key dump exceptions.

