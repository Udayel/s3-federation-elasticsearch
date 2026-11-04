# Quick Start

The shortest path from clone to first query, using Elastic Cloud Hosted and federated identity. For explanations, static credentials, and version notes, see [README.md](README.md).

**You need:** Elastic Cloud Hosted 9.5+ (Enterprise), the AWS CLI, and Python 3. On **9.5**, first enable `esql.federation.enabled: true` (Elasticsearch) and `xpack.dataFederation.enabled: true` (Kibana) in the deployment's user settings. In 9.6+ they're on by default.

```bash
git clone https://github.com/Udayel/s3-federation-elasticsearch.git
cd s3-federation-elasticsearch

export BUCKET=my-s3-federation-bucket   # globally unique
export REGION=us-west-2

# 1. Bucket + data
bash scripts/create-s3-bucket.sh "$BUCKET" "$REGION"
python3 scripts/upload-parquet.py "$BUCKET" --region "$REGION"
```

**2. Get your identity details.** In Kibana, go to **Data management → ES|QL Data Federation → Connect data source**. Choose **Amazon S3**, then **Federated Identity**, then **Manual**. Copy the issuer URL and the subject (`deployment:<id>`).

```bash
# 3. OIDC provider + role + read policy; prints the role ARN
bash iam/setup-federated-identity.sh "$BUCKET" "<JWT_ISSUER_URL>" "deployment:<deployment-id>"
```

**4. Register the data source and dataset.** Run these in Kibana Dev Tools. On 9.5, add `"region": "<REGION>"` to the data source settings.

```
PUT /_query/data_source/s3_federation
{
  "type": "s3",
  "settings": {
    "auth": "federated_identity",
    "role_arn": "<ROLE_ARN from step 3>",
    "jwt_audience": "sts.amazonaws.com"
  }
}

PUT /_query/dataset/sales
{
  "data_source": "s3_federation",
  "resource": "s3://<BUCKET>/business-data/sales.parquet"
}
```

**5. Query.** Run this in Discover (ES|QL) or Dev Tools:

```esql
FROM sales
| EVAL ym = DATE_FORMAT("yyyy-MM", order_date)
| STATS orders = COUNT(*), revenue = ROUND(SUM(total_amount), 2) BY ym
| SORT ym
```

Expected: four months, peaking in 2026-09 with 94 orders and about $2.19M of revenue.

**Next:** register `customers`, `inventory`, and `crm` with `elastic/02-datasets.console`, then try `elastic/03-queries.esql`.

**Cleanup:** run `elastic/04-cleanup.console` in Dev Tools, then `bash scripts/cleanup.sh "$BUCKET"`.
