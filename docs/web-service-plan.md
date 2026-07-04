# Web Service Plan — Adding Dynamic Features to S3 Static Site

## Context

We have a static website hosted on AWS S3. The goal is to add JavaScript-driven features
(e.g. saving favorites) by calling lightweight web services backed by the existing PostgreSQL database.

---

## Architecture

```
S3 (static site) → JS fetch() → API Gateway → Lambda (Node.js) → PostgreSQL
```

### Components

| Component | Choice | Notes |
|---|---|---|
| Static hosting | AWS S3 | Already in place |
| API endpoints | AWS API Gateway (HTTP API) | HTTP API is cheaper/simpler than REST API |
| Backend logic | AWS Lambda (Node.js) | Serverless, scales to zero, pay per execution |
| Database | Existing PostgreSQL | Already available — no reason to switch |

---

## Key Decisions

### Why API Gateway HTTP API (not REST API)?
- Cheaper per request
- Simpler CORS configuration
- Sufficient for straightforward CRUD endpoints

### Why Lambda (not a persistent server)?
- No servers to manage
- Scales to zero when not used
- Free tier covers millions of requests/month — effectively $0 at small scale

### Why keep PostgreSQL (not DynamoDB)?
- Already have an existing PostgreSQL database with data
- No reason to introduce a second DB technology
- SQL is a better fit if the data has any relational structure

### Lambda + PostgreSQL — Connection Pooling
Lambda spins up/down per request, which can exhaust Postgres connection limits under load.

**Options:**
- **Short-lived connections** (`pg` package: open, query, close per Lambda invocation) —
  simplest, fine for low traffic
- **RDS Proxy** — AWS managed connection pooler, ~$15–20/month, only worth it at scale

**Recommendation:** Start with short-lived connections. Add RDS Proxy only if connection
exhaustion becomes a real problem.

---

## Network / VPC Note

If the PostgreSQL database is inside an AWS VPC (e.g. RDS), the Lambda functions must
also be deployed inside that VPC to reach it. If Postgres is hosted externally (Supabase,
Railway, etc.) with a public endpoint, no VPC config is needed — just set the connection
string as a Lambda environment variable.

**Next step:** Confirm where Postgres is hosted to determine if VPC config is needed.

---

## Implementation Steps

1. **API Gateway** — Create an HTTP API, configure CORS to allow the S3 site's domain
2. **Lambda functions** — Node.js, one function per endpoint (or grouped), using `pg` package
3. **Environment variables** — Store DB connection string as a Lambda env var (never hardcode)
4. **Deploy** — Use AWS SAM or Serverless Framework to define and deploy Lambda + API Gateway
   from a single config file

---

## Auth Consideration

If users need accounts to save favorites:
- **AWS Cognito** — plugs in directly to API Gateway, free tier (50k monthly active users)
- **No auth** — use a browser/device ID stored in `localStorage` if personal accounts aren't needed

---

## Cost Estimate (small project)

| Service | Free Tier | Beyond Free |
|---|---|---|
| API Gateway (HTTP) | 1M requests/month free | $1/1M requests |
| Lambda | 1M requests/month free | $0.20/1M requests |
| PostgreSQL | Existing — no added cost | — |

**Expected cost: $0/month** for a low-traffic personal or small project.
