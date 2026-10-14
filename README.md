# S3 Federation for Elasticsearch Cloud

Complete setup repository for S3 Federation with Elasticsearch Cloud, including sample data, IAM templates, and automation scripts.

## 📋 Contents

```
├── data/
│   ├── customers.csv      - Sample customer data (20 records)
│   ├── sales.csv          - Sample sales transactions (25 records)
│   ├── inventory.csv      - Sample inventory (15 products)
│   └── crm.csv           - Sample CRM contacts (10 records)
├── iam/
│   ├── s3-federation-policy-template.json  - Parameterized IAM policy
│   ├── trust-policy-template.json          - Parameterized trust policy
│   └── setup-iam.sh                        - IAM setup automation
├── scripts/
│   ├── create-s3-bucket.sh  - Create and configure S3 bucket
│   └── upload-data.sh       - Upload data files to S3
└── README.md
```

## 🚀 Quick Start (5 minutes)

### Step 1: Create S3 Bucket

```bash
bash scripts/create-s3-bucket.sh my-s3-federation-bucket us-east-1
```

**What it does:**
- Creates S3 bucket
- Enables versioning
- Enables encryption (AES256)
- Blocks public access
- Creates `business-data/` prefix

### Step 2: Upload Data Files

```bash
bash scripts/upload-data.sh my-s3-federation-bucket us-east-1
```

**Files uploaded:**
- customers.csv (20 records)
- sales.csv (25 transactions)
- inventory.csv (15 products)
- crm.csv (10 contacts)

### Step 3: Setup IAM

```bash
bash iam/setup-iam.sh my-s3-federation-bucket business-data elasticsearch-user
```

**Creates:**
- IAM Policy: `elastic-s3-federation-policy`
- IAM Role: `elastic-s3-federation-role`
- IAM User: `elasticsearch-user`

### Step 4: Generate Access Keys

```bash
aws iam create-access-key --user-name elasticsearch-user
```

**Save the output:**
- Access Key ID
- Secret Access Key

### Step 5: Configure Elasticsearch

1. Go to Kibana → Stack Management → Data Sources
2. Add S3 Data Source
3. Enter:
   - Bucket: `my-s3-federation-bucket`
   - Prefix: `business-data`
   - Region: `us-east-1`
   - Format: CSV (or convert to Parquet)
   - Access Keys: (from Step 4)
4. Test Connection
5. Save

## 📊 Sample Data

### Customers (20 records)
- Customer ID, Name, Email, Phone
- Segments: Startup, Mid-Market, Enterprise, Premium
- Lifetime Value: $28K - $695K

### Sales (25 transactions)
- Order ID, Customer ID, Product ID
- Quantity, Unit Price, Total Amount
- Order Date, Status, Region

### Inventory (15 products)
- Product ID, Name, SKU, Category
- Quantity on Hand, Reorder Level
- Unit Price, Supplier ID
- Status: Active, Low, Critical, OutOfStock

### CRM (10 contacts)
- Contact ID, Customer ID, Contact Name
- Email, Phone, Department, Job Title
- Last Contact Date, Interaction Type, Notes

## 🔐 IAM Configuration

### Policy Permissions

The `elastic-s3-federation-policy` grants:

**S3 Read Access:**
- `s3:ListBucket` - List objects
- `s3:GetObject` - Read objects
- `s3:GetBucketLocation` - Get region
- `s3:ListBucketVersions` - List versions
- `s3:GetObjectVersion` - Read specific versions

**CloudWatch Logging:**
- `logs:CreateLogGroup`
- `logs:CreateLogStream`
- `logs:PutLogEvents`

### Parameterized Templates

The templates use placeholders (no hardcoded values):

```json
"Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/${S3_PREFIX}/*"
"AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
```

The setup scripts automatically replace these with actual values.

## 🛠️ Configuration

All scripts accept parameters - customize for your environment:

```bash
# Create bucket in specific region
bash scripts/create-s3-bucket.sh my-bucket eu-west-1

# Use custom IAM names and prefix
bash iam/setup-iam.sh my-bucket data-exports my-custom-user
```

## ✅ Verification

### Verify S3 Setup
```bash
aws s3 ls s3://my-s3-federation-bucket/business-data/
```

Expected output:
```
2024-10-14 customers.csv
2024-10-14 sales.csv
2024-10-14 inventory.csv
2024-10-14 crm.csv
```

### Verify IAM
```bash
aws iam get-policy --policy-arn arn:aws:iam::ACCOUNT_ID:policy/elastic-s3-federation-policy
aws iam get-role --role-name elastic-s3-federation-role
aws iam get-user --user-name elasticsearch-user
```

### Test Access
```bash
# Using the user's credentials
export AWS_ACCESS_KEY_ID=your_key_id
export AWS_SECRET_ACCESS_KEY=your_secret_key

aws s3 ls s3://my-s3-federation-bucket/business-data/
```

## 📝 Elasticsearch Configuration

### Data Source Settings
```
Type: S3
Bucket: my-s3-federation-bucket
Region: us-east-1
Prefix: business-data/
Format: CSV or Parquet
Access Key ID: [from Step 4]
Secret Access Key: [from Step 4]
```

### Sample Query (ES|SQL)
```sql
SELECT customer_id, customer_name, total_spent
FROM s3(bucket='my-s3-federation-bucket', path='business-data/customers.csv')
LIMIT 10
```

## 🔄 Data Format Conversion

The sample data is in CSV format. For production Elasticsearch ES|SQL Federation:

### Option 1: AWS Glue
```bash
# Create Glue crawler to convert CSV to Parquet
```

### Option 2: Local Python
```python
import pandas as pd

for file in ['customers', 'sales', 'inventory', 'crm']:
    df = pd.read_csv(f'{file}.csv')
    df.to_parquet(f'{file}.parquet')
```

### Option 3: AWS Lambda
Use AWS Lambda with PyArrow to convert on upload

## 📚 Documentation

For detailed setup and troubleshooting, see:
- `/Users/uday/s3-federation-poc/IMPLEMENTATION-SEQUENCE.md`
- `/Users/uday/s3-federation-poc/IAM-SECURITY-MATRIX.md`

## 🔒 Security Best Practices

✅ **Implemented:**
- Least privilege IAM policy
- S3 encryption enabled
- Public access blocked
- Versioning enabled
- User-based access control

✅ **Recommended:**
- Rotate access keys every 90 days
- Enable CloudTrail logging
- Use AWS Secrets Manager for credentials
- Restrict bucket policy to specific IPs
- Enable S3 access logging

## 📋 Checklist

- [ ] Clone/fork this repository
- [ ] Create S3 bucket: `bash scripts/create-s3-bucket.sh`
- [ ] Upload data: `bash scripts/upload-data.sh`
- [ ] Setup IAM: `bash iam/setup-iam.sh`
- [ ] Generate access keys: `aws iam create-access-key`
- [ ] Configure Elasticsearch
- [ ] Test query in Kibana

## 🆘 Troubleshooting

### "Access Denied" Error
- Verify IAM policy is attached to user
- Check S3 bucket name matches policy
- Verify access keys are correct

### "NoSuchBucket" Error
- Verify bucket name is correct
- Verify bucket is in correct region
- Check bucket exists: `aws s3 ls`

### Data Not Visible
- Verify files are uploaded: `aws s3 ls s3://bucket/prefix/`
- Verify file format (CSV vs Parquet)
- Check Elasticsearch prefix matches S3 path

## 📞 Support

For issues or questions:
1. Check troubleshooting section above
2. Review IAM policy permissions
3. Verify S3 bucket configuration
4. Check Elasticsearch data source settings

## 📄 License

Open source - feel free to fork and customize for your environment

## 🎯 Next Steps

After basic setup:
1. Convert CSV to Parquet for better Elasticsearch performance
2. Add more sample data for testing
3. Setup Elasticsearch dashboards
4. Configure automated workflows
5. Deploy AI agents for monitoring

---

**Ready to get started?** Run the quick start commands above! 🚀
