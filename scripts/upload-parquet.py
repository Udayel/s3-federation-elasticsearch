#!/usr/bin/env python3
"""
upload-parquet.py — Upload the Parquet sample data to S3 for ES|QL Data Federation.

Runs anywhere the AWS credentials and the parquet files are both available
(your Mac with aws-cli configured, or AWS CloudShell after `git clone`).

Uploads every *.parquet in the data folder to:
    s3://<bucket>/<prefix>/<file>.parquet

Usage:
    python3 upload-parquet.py <BUCKET> [--region us-west-2] [--prefix business-data-parquet] [--data-dir data/parquet]

Examples:
    python3 scripts/upload-parquet.py elastic-s3-fed-010526247135-usw2
    python3 scripts/upload-parquet.py my-bucket --region us-east-1 --prefix business-data-parquet
"""
import argparse
import hashlib
import subprocess
import sys
from pathlib import Path


def md5(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def upload_boto3(files, bucket, prefix, region):
    import boto3  # imported lazily so the CLI fallback works without boto3
    s3 = boto3.client("s3", region_name=region)
    for f in files:
        key = f"{prefix}/{f.name}"
        print(f"  → s3://{bucket}/{key}  ({f.stat().st_size:,} bytes, md5={md5(f)})")
        s3.upload_file(str(f), bucket, key)
    return True


def upload_cli(files, bucket, prefix, region):
    for f in files:
        key = f"{prefix}/{f.name}"
        print(f"  → s3://{bucket}/{key}  ({f.stat().st_size:,} bytes, md5={md5(f)})")
        rc = subprocess.run(
            ["aws", "s3", "cp", str(f), f"s3://{bucket}/{key}", "--region", region]
        ).returncode
        if rc != 0:
            raise SystemExit(f"aws s3 cp failed for {f.name} (rc={rc})")
    return True


def main():
    ap = argparse.ArgumentParser(description="Upload Parquet sample data to S3.")
    ap.add_argument("bucket", help="Target S3 bucket name")
    ap.add_argument("--region", default="us-west-2", help="AWS region (default: us-west-2)")
    ap.add_argument("--prefix", default="business-data-parquet",
                    help="S3 key prefix (default: business-data-parquet)")
    ap.add_argument("--data-dir", default=str(Path(__file__).resolve().parent.parent / "data" / "parquet"),
                    help="Folder containing *.parquet (default: ../data/parquet relative to this script)")
    args = ap.parse_args()

    data_dir = Path(args.data_dir)
    if not data_dir.is_dir():
        raise SystemExit(f"Data dir not found: {data_dir}")

    files = sorted(data_dir.glob("*.parquet"))
    if not files:
        raise SystemExit(f"No .parquet files found in {data_dir}")

    print(f"Uploading {len(files)} file(s) from {data_dir}")
    print(f"Destination: s3://{args.bucket}/{args.prefix}/  (region {args.region})\n")

    try:
        upload_boto3(files, args.bucket, args.prefix, args.region)
        engine = "boto3"
    except ImportError:
        print("(boto3 not available — falling back to the aws CLI)\n")
        upload_cli(files, args.bucket, args.prefix, args.region)
        engine = "aws cli"

    print(f"\n✅ Done via {engine}. Verify with:")
    print(f"   aws s3 ls s3://{args.bucket}/{args.prefix}/ --region {args.region}")


if __name__ == "__main__":
    main()
