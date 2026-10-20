# S3 Federation for Elasticsearch Cloud

Complete setup repository for **ES|QL Data Federation** with Elasticsearch Cloud — query Parquet data in Amazon S3 **in place**, with no ingestion, using the same ES|QL syntax you use for indexed data.

> Companion to the blog *"Querying Amazon S3 in Place: ES|QL Data Federation Brings Zero-ETL to Elastic."*

## 📋 Contents

```
├── data/
│   └── parquet/
│       ├── customers.parquet   - 100 customers (segment, CLV, signup_date, …)
│       ├── sales.parquet       - 250 orders, Jul–Oct 2026 (total_amount, status, payment_method, …)
│       ├── inventory.parquet   - 50 products (quantity_on_hand, reorder_level, warehouse_location, …)
│       └── crm.parquet         - 100 CRM records (opportunity_stage, estimated_value, lead_status, …)
├── iam/
│   ├── s3-federation-policy-template.json
│   ├── trust-policy-template.json
│   └── setup-iam.sh
├── scripts/
│   ├── create-s3-bucket.sh
│   └── upload-parquet.py       - Upload the Parquet data to S3 (boto3 or aws CLI)
└── README.md
```

> **Note on data format.** This repo ships **Parquet** sample data. ES|QL Data Federation also supports CSV, TSV, and NDJSON, but Parquet is recommended: column selection and row-group statistics push down into the reader, so queries read far fewer bytes from S3.

## ✅ Prerequisites

ES|QL Data Federation is an **experimental** feature. Before you start:

- An Elastic deployment on **version 9.5 or later** (Elastic Cloud Hosted, ECE, ECK, or self-managed).
- An **Enterprise** subscription.
- The feature enabled on the deployment:
  - Elasticsearch (`elasticsearch.yml`): `esql.federation.enabled: true`
  - Kibana (`kibana.yml`): `xpack.dataFederation.enabled: true`
  - On Elastic Cloud, add these under the deployment's **user settings** and apply (triggers a rolling restart).
- Not supported on Windows.
- AWS CLI configured with permission to create S3 buckets and IAM resources.

## 🚀 Quick Start

### Step 1 — Create the S3 bucket
```bash
bash scripts/create-s3-bucket.sh my-s3-federation-bucket us-west-2
```
Creates the bucket with versioning, AES256 encryption, public access blocked, and a `business-data/` prefix.

### Step 2 — Upload the Parquet data
```bash
python3 scripts/upload-parquet.py my-s3-federation-bucket --region us-west-2
```
Uploads every `data/parquet/*.parquet` to `s3://my-s3-federation-bucket/business-data/`. Uses `boto3` if available, otherwise falls back to the `aws` CLI. Prints each file's size and md5.

Verify:
```bash
aws s3 ls s3://my-s3-federation-bucket/business-data/ --region us-west-2
```

### Step 3 — Set up IAM (least privilege)
```bash
bash iam/setup-iam.sh my-s3-federation-bucket business-data elasticsearch-s3-federation
```
Creates a policy granting **only** `s3:ListBucket` (bucket) and `s3:GetObject` (objects under `business-data/`), and an IAM user to attach it to.

> ⚠️ **Prefix scoping matters.** The policy grants `GetObject` on `arn:aws:s3:::<bucket>/business-data/*`. If you place the data under a *different* prefix (e.g. `business-data-parquet/`), you must widen the policy Resource accordingly — `business-data/*` does **not** match `business-data-parquet/...`. Keeping the data in `business-data/` needs no change.

### Step 4 — Generate an access key
```bash
aws iam create-access-key --user-name elasticsearch-s3-federation
```
Save the `AccessKeyId` and `SecretAccessKey` (shown once).

### Step 5 — Register the data source and datasets in Elastic
Data Federation uses two objects: a **data source** (connection + auth) and one or more **datasets** (which files). In **Kibana → Dev Tools → Console**, or via the REST API:

```
PUT /_query/data_source/s3_federation
{
  "type": "s3",
  "settings": {
    "auth": "static_credentials",
    "access_key": "<AWS_ACCESS_KEY_ID>",
    "secret_key": "<AWS_SECRET_ACCESS_KEY>",
    "region": "us-west-2"
  }
}
```
```
PUT /_query/dataset/customers
{ "data_source": "s3_federation", "resource": "s3://my-s3-federation-bucket/business-data/customers.parquet" }

PUT /_query/dataset/sales
{ "data_source": "s3_federation", "resource": "s3://my-s3-federation-bucket/business-data/sales.parquet" }

PUT /_query/dataset/inventory
{ "data_source": "s3_federation", "resource": "s3://my-s3-federation-bucket/business-data/inventory.parquet" }

PUT /_query/dataset/crm
{ "data_source": "s3_federation", "resource": "s3://my-s3-federation-bucket/business-data/crm.parquet" }
```

You can also do this in Kibana under **Data management → ES|QL Data Federation → Connect data source → Add dataset**.

> **Security tip.** For production, prefer **federated identity** (OIDC / `sts:AssumeRoleWithWebIdentity`) over long-lived access keys, so no static AWS credentials are stored in Elastic.

### Step 6 — Query the data with ES|QL
There is no special syntax — query a dataset with `FROM`, exactly like an index:

```esql
FROM customers
| LIMIT 10
```

## 📊 Hands-On Query Patterns

**1. Customer segmentation by lifetime value**
```esql
FROM customers
| STATS customers = COUNT(*), total_clv = SUM(customer_lifetime_value) BY segment
| SORT total_clv DESC
```

**2. CRM pipeline by opportunity stage**
```esql
FROM crm
| STATS deals = COUNT(*), total_value = ROUND(SUM(estimated_value), 2) BY opportunity_stage
| SORT total_value DESC
```
Returns, e.g., **Won = $4.48M across 14 deals**, **Lead = $4.39M across 20 opportunities**.

**3. Inventory reorder alerts**
```esql
FROM inventory
| WHERE quantity_on_hand < reorder_level
| KEEP product_name, quantity_on_hand, reorder_level, warehouse_location
| SORT quantity_on_hand ASC
```

**4. Monthly revenue trend**
```esql
FROM sales
| EVAL ym = DATE_FORMAT("yyyy-MM", order_date)
| STATS orders = COUNT(*), revenue = ROUND(SUM(total_amount), 2) BY ym
| SORT ym
```
Returns the monthly series peaking at **Sept 2026 = $2.19M across 94 orders** (October is a partial month).

## 🔄 Progressive Acceleration

| Capability | S3 Federated Datasets | Elasticsearch Indices |
|---|---|---|
| Storage cost | Low (S3 object storage) | Standard index storage |
| Ingestion pipeline | None (Zero-ETL) | Required |
| ES\|QL `FROM` queries | ✅ | ✅ |
| kNN vector search | ❌ | ✅ |
| LOOKUP JOIN target | ❌ | ✅ |
| Time series (TS) functions | ❌ | ✅ |
| Relevance scoring | Runtime (boolean similarity) | Full BM25 / hybrid |

Keep raw data cheap in S3; promote high-value subsets into indices when you need advanced search.

## 🆘 Troubleshooting

- **403 / Access Denied on query** — the IAM policy prefix doesn't cover your object path. Confirm the data is under `business-data/` (or widen the policy). Verify with `aws s3 ls`.
- **Feature/endpoint not found** — confirm `esql.federation.enabled` (ES) and `xpack.dataFederation.enabled` (Kibana) are set, the deployment is 9.5+, and the subscription is Enterprise.
- **No rows / wrong schema** — query `FROM <dataset> | LIMIT 1` to inspect inferred types.

## 📄 License
Open source — fork and customize for your environment.
