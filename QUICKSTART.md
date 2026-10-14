# Quick Start Guide

Get S3 Federation with Elasticsearch Cloud running in **10 minutes**.

## Prerequisites

- AWS CLI configured with credentials
- Bash shell
- AWS Account with appropriate permissions

## Step 1: Clone Repository

```bash
git clone https://github.com/yourusername/s3-federation.git
cd s3-federation
```

## Step 2: Create S3 Bucket (2 minutes)

```bash
# Set your bucket name
BUCKET_NAME="my-s3-federation-poc"
REGION="us-east-1"

# Create bucket with encryption and versioning
bash scripts/create-s3-bucket.sh $BUCKET_NAME $REGION
```

## Step 3: Upload Sample Data (2 minutes)

```bash
bash scripts/upload-data.sh $BUCKET_NAME $REGION
```

**Verify upload:**
```bash
aws s3 ls s3://$BUCKET_NAME/business-data/
```

## Step 4: Setup IAM (2 minutes)

```bash
# Create policy, role, and user
bash iam/setup-iam.sh $BUCKET_NAME business-data elasticsearch-user
```

## Step 5: Generate Credentials (2 minutes)

```bash
# Create access keys for the Elasticsearch user
aws iam create-access-key --user-name elasticsearch-user

# Output will show:
# AccessKeyId: AKIA...
# SecretAccessKey: ...
# ^^^ SAVE THESE ^^^
```

## Step 6: Configure Elasticsearch (1 minute)

1. Open Kibana: `https://your-cluster.kb.your-region.aws.elastic.cloud/`
2. Go to: **Stack Management** → **Data Sources** → **Add Data Source**
3. Select: **S3**
4. Fill in:
   - **Bucket:** `my-s3-federation-poc`
   - **Region:** `us-east-1`
   - **Prefix:** `business-data`
   - **Format:** `CSV`
   - **Access Key ID:** (from Step 5)
   - **Secret Access Key:** (from Step 5)
5. Click: **Test Connection** (should show success)
6. Click: **Save**

## Step 7: Test Query (1 minute)

In Kibana Dev Tools:

```sql
SELECT COUNT(*) as customers
FROM s3(bucket='my-s3-federation-poc', path='business-data/customers.csv')
```

Expected: `20`

---

**Done!** You now have S3 Federation working with Elasticsearch Cloud.

## Next Steps

1. **Convert to Parquet** (better performance):
   ```bash
   # Use Python script or AWS Glue
   python3 scripts/csv_to_parquet.py
   ```

2. **Explore Data:**
   - Query sales data
   - Join customers with sales
   - Analyze inventory

3. **Setup Dashboards:**
   - Create visualizations from queries
   - Build supply chain dashboard

4. **Deploy Automation:**
   - Setup workflows
   - Configure AI agents

## Troubleshooting

### "Access Denied" in Kibana
```bash
# Verify IAM policy
aws iam get-user-policy --user-name elasticsearch-user --policy-name elastic-s3-federation-policy
```

### "NoSuchBucket" error
```bash
# Verify bucket exists and region is correct
aws s3 ls --region us-east-1
```

### Data not showing in Elasticsearch
```bash
# Verify files in S3
aws s3 ls s3://my-s3-federation-poc/business-data/ --human-readable
```

## Sample Data

| Data Set | Records | Use Case |
|----------|---------|----------|
| customers.csv | 20 | Customer profiles |
| sales.csv | 25 | Transactions |
| inventory.csv | 15 | Product stock |
| crm.csv | 10 | Contact info |

---

**Need help?** See [README.md](README.md) for detailed documentation.
