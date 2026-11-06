# S3 Federation for Elasticsearch

Companion repo for the blog *"Querying Amazon S3 in Place: ES|QL Data Federation Brings Zero-ETL to Elastic."*

Query Parquet files in Amazon S3 **in place** with ES|QL Data Federation. There's no ingestion, and you use the same `FROM` syntax you use for indices. The walkthrough follows one dataset, `sales`, from upload to query, and registers three more datasets for further exploration.

> ⚠️ **Feature status.** ES|QL Data Federation is **experimental in 9.5** and in **technical preview in 9.6+**. It isn't GA and isn't intended for production workloads. See [Version differences](#version-differences-95-vs-96).

## Contents

```
├── data/parquet/                    Sample data (synthetic)
│   ├── sales.parquet                250 orders, Jul–Oct 2026
│   ├── customers.parquet            100 customers
│   ├── inventory.parquet            50 products
│   └── crm.parquet                  100 CRM opportunities
├── iam/
│   ├── s3-federation-policy-template.json   s3:GetObject on the prefix + s3:ListBucket
│   ├── trust-policy-template.json           OIDC trust policy (sts:AssumeRoleWithWebIdentity)
│   ├── setup-federated-identity.sh          OIDC provider + role + policy (Elastic Cloud Hosted)
│   └── setup-static-credentials.sh          IAM user + policy (self-managed / ECE / ECK)
├── elastic/
│   ├── 01-data-source-federated-identity.console
│   ├── 01-data-source-static-credentials.console
│   ├── 02-datasets.console
│   ├── 03-queries.esql
│   └── 04-cleanup.console
└── scripts/
    ├── create-s3-bucket.sh
    ├── upload-parquet.py
    └── cleanup.sh
```

## Prerequisites

- An Elastic deployment on **9.5 or later** with an **Enterprise** subscription.
  - **Federated identity** (recommended) requires **Elastic Cloud Hosted** on AWS, Azure, or Google Cloud.
  - Self-managed, ECE, and ECK clusters must use **static credentials**.
  - Not supported on Windows nodes.
- **9.5 only:** turn the feature on. In 9.6+ it is on by default.
  - Elasticsearch (`elasticsearch.yml`): `esql.federation.enabled: true`
  - Kibana (`kibana.yml`): `xpack.dataFederation.enabled: true`
  - On Elastic Cloud, add these under the deployment's **user settings**. Applying them triggers a rolling restart.
- The cluster `manage` privilege to use the Kibana UI.
- The AWS CLI, configured with permission to create S3 buckets and IAM resources, and Python 3.

```bash
export BUCKET=my-s3-federation-bucket   # must be globally unique
export REGION=us-west-2                 # keep the bucket in your deployment's region to avoid transfer costs
```

## Step 1: Create the bucket and upload the data

```bash
bash scripts/create-s3-bucket.sh "$BUCKET" "$REGION"
python3 scripts/upload-parquet.py "$BUCKET" --region "$REGION"
aws s3 ls "s3://$BUCKET/business-data/" --region "$REGION"
```

The bucket is created with versioning, SSE-S3 encryption, and all public access blocked. The data lands under `business-data/`, the prefix the IAM policy grants.

## Step 2: Grant Elasticsearch read access

Both options attach the same least-privilege policy: `s3:GetObject` on `arn:aws:s3:::<bucket>/business-data/*`, and `s3:ListBucket` on the bucket (needed only for prefix or glob datasets).

> **Prefix scoping matters.** `business-data/*` does **not** match `business-data-parquet/...`. If you put data under another prefix, pass it as the `PREFIX` argument.

### Option A: Federated identity (Elastic Cloud Hosted, recommended)

No AWS keys are stored in Elastic. Elastic issues a signed token for your deployment, and AWS trades it for temporary credentials on a role that only your deployment can assume.

1. In Kibana, go to **Data management → ES|QL Data Federation → Connect data source**. Choose **Amazon S3** and keep **Federated Identity** as the authentication method.
2. Pick a setup method:
   - **CloudFormation** (easiest): click **Open template in AWS Console** and create the stack. Copy the `RoleArn` output, then attach `iam/s3-federation-policy-template.json` to that role (the template creates the role without permissions).
   - **Manual / this repo**: select **Manual** and copy the **issuer URL** (`JWT_ISSUER`) and **subject** (`deployment:<id>`). Then run:

     ```bash
     bash iam/setup-federated-identity.sh "$BUCKET" "<JWT_ISSUER_URL>" "deployment:<deployment-id>"
     ```

     The script creates (or reuses) the IAM OIDC identity provider for the issuer, and a role with this trust policy:

     ```json
     {
       "Effect": "Allow",
       "Principal": { "Federated": "arn:aws:iam::<account>:oidc-provider/<issuer-host>/<path>" },
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": {
         "StringEquals": {
           "<issuer-host>/<path>:aud": "sts.amazonaws.com",
           "<issuer-host>/<path>:sub": "deployment:<deployment-id>"
         }
       }
     }
     ```

     It then attaches the read policy and prints the role ARN.
3. Paste the role ARN into the flyout and click **Connect**. Or run `elastic/01-data-source-federated-identity.console` in Dev Tools.

Reference: [Connect to Amazon S3 with federated identity](https://www.elastic.co/docs/reference/query-languages/esql/esql-data-federation-federated-identity).

### Option B: Static credentials (self-managed, ECE, ECK)

```bash
bash iam/setup-static-credentials.sh "$BUCKET" business-data
aws iam create-access-key --user-name elasticsearch-s3-federation   # secret is shown once
```

Then run `elastic/01-data-source-static-credentials.console` in Dev Tools with the key pair.

Reference: [Connect to Amazon S3 with static credentials](https://www.elastic.co/docs/reference/query-languages/esql/esql-data-federation-static-credentials).

## Step 3: Register the data source and datasets

A **data source** holds the connection and authentication. A **dataset** says which files to read. Updating a data source's credentials updates every dataset that uses it. Dataset names share the namespace with indices, data streams, aliases, and views.

```
PUT /_query/data_source/s3_federation
{
  "type": "s3",
  "settings": {
    "auth": "federated_identity",
    "role_arn": "arn:aws:iam::<ACCOUNT_ID>:role/elastic-esql-federation-role",
    "jwt_audience": "sts.amazonaws.com"
  }
}

PUT /_query/dataset/sales
{
  "data_source": "s3_federation",
  "resource": "s3://<BUCKET>/business-data/sales.parquet"
}
```

- **9.5:** add `"region": "<BUCKET_REGION>"` to the data source settings. In 9.6+ that setting is deprecated and ignored; the region is auto-detected, or you can set it per dataset.
- **Format detection:** Elasticsearch infers the format only when the resource pattern implies exactly one format, for example `*.parquet`. For extensionless paths (`logs/*`) or mixed patterns (`*.{parquet,csv}`), set `"settings": { "format": "parquet" }` on the dataset.
- The other three datasets (`customers`, `inventory`, `crm`) are in `elastic/02-datasets.console`.

You can also do all of this in Kibana under **Data management → ES|QL Data Federation → Add dataset**.

## Step 4: Query with ES|QL

There's no special syntax. Query the dataset with `FROM`, just like an index (Discover in ES|QL mode, or Dev Tools):

```esql
FROM sales
| LIMIT 10
```

```esql
FROM sales
| EVAL ym = DATE_FORMAT("yyyy-MM", order_date)
| STATS orders = COUNT(*), revenue = ROUND(SUM(total_amount), 2) BY ym
| SORT ym
```

This returns a monthly series that peaks at **Sept 2026: $2.19M across 94 orders**. October is a partial month.

On Parquet, `WHERE`, `KEEP`, and `LIMIT` push down into the reader, so Elasticsearch reads fewer bytes from S3:

```esql
FROM sales
| WHERE status == "Completed"
| STATS orders = COUNT(*), revenue = ROUND(SUM(total_amount), 2) BY payment_method
| SORT revenue DESC
```

More patterns over `customers`, `crm`, and `inventory` are in [`elastic/03-queries.esql`](elastic/03-queries.esql). For example, the CRM pipeline by stage returns **Won = $4.48M across 14 deals**.

## Progressive acceleration: when to index

Keep raw data in S3, explore it on demand, and promote high-value subsets into indices when you need capabilities that depend on index structures.

| Capability | S3 federated datasets | Elasticsearch indices |
|---|---|---|
| Storage cost | S3 object storage, plus per-query S3 GET and transfer | Index storage (plus replicas) |
| Ingestion pipeline | None | Required |
| ES\|QL `FROM` queries | ✅ | ✅ |
| `LOOKUP JOIN` target | ❌ (dataset can be the left side only) | ✅ |
| `TS` time-series command | ❌ | ✅ |
| kNN vector search | 9.5: ❌ · 9.6+: exact (brute-force) `KNN` via `TO_DENSE_VECTOR` | ✅ approximate (HNSW) |
| Relevance scoring (`_score`) | 9.5: none (`_score` is `null`) · 9.6+: runtime `MATCH`/`MATCH_PHRASE` scoring by boost and matched terms, **not BM25** (no index statistics) | ✅ BM25 and hybrid search |
| Document/field-level security | ❌ queries are rejected | ✅ |

References: [Querying datasets and limitations](https://www.elastic.co/docs/reference/query-languages/esql/esql-data-federation-querying).

## Version differences (9.5 vs 9.6+)

| | 9.5 | 9.6+ |
|---|---|---|
| Status | Experimental | Technical preview |
| Feature flags | Must be enabled in ES and Kibana | On by default (`esql.federation.enabled: false` turns it off) |
| `region` | On the data source | Deprecated on the data source; auto-detected or set per dataset |
| `_score` on dataset rows | `null` | Runtime scoring with `MATCH`/`MATCH_PHRASE` |
| `KNN`, `MATCH_PHRASE` on datasets | ❌ | ✅ |
| Snapshot and restore of data sources and datasets | ❌ | ✅ (credentials must be re-entered) |

## Cleanup

```bash
# 1. Elastic: run elastic/04-cleanup.console in Dev Tools
# 2. AWS: deletes all object versions, the bucket, policy, role, user, and access keys
bash scripts/cleanup.sh "$BUCKET"
```

The bucket is versioned, so a plain `aws s3 rb --force` leaves old versions behind and fails. The script removes every version first. It asks you to confirm, and it does **not** delete the shared OIDC identity provider.

## Troubleshooting

- **403 / Access Denied.** The policy prefix doesn't cover the object path, or (for globs) `s3:ListBucket` is missing. Check with `aws s3 ls s3://$BUCKET/business-data/`.
- **Federated identity fails to connect.** The `aud`/`sub` conditions in the trust policy must match the data source's `jwt_audience` (default `sts.amazonaws.com`) and your `deployment:<id>` exactly. Federated identity isn't available on self-managed, ECE, ECK, or GovCloud.
- **Endpoint not found (9.5).** Check both feature settings, a version of 9.5 or later, and an Enterprise subscription.
- **Wrong or missing columns.** Run `FROM <dataset> | LIMIT 1` to inspect the inferred schema. For CSV/TSV/NDJSON, the schema is inferred from sampled rows.
- **`InvalidObjectState`.** The objects are in Glacier Flexible Retrieval or Deep Archive. Restore them first.

## License

[MIT](LICENSE)
