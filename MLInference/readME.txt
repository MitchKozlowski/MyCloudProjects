# ML Inference Infrastructure on AWS

Production-style ML inference infrastructure deployed entirely with Terraform on AWS, serving a HuggingFace sentiment analysis model via SageMaker with automated monitoring, data capture, and auto scaling.

## Architecture

```
HuggingFace Model (distilbert-base-uncased-finetuned-sst-2-english)
       ↓
S3 Bucket (data capture + monitor output)
       ↓
SageMaker Model (HuggingFace PyTorch inference container)
       ↓
SageMaker Endpoint Configuration (ml.m5.large, data capture enabled)
       ↓
SageMaker Real-Time Endpoint
       ↓
Application Auto Scaling (1-3 instances, target tracking)
       ↓
SageMaker Model Monitor (hourly data quality checks)
       ↓
CloudWatch (log group + invocation error alarm)

All resources provisioned via Terraform with least-privilege IAM.
```

## Features

- Real-time sentiment classification endpoint (POSITIVE/NEGATIVE + confidence score)
- Infrastructure as Code using Terraform — fully reproducible deployment
- Least-privilege IAM execution role scoped to specific S3 bucket ARN
- S3 bucket with versioning, AES256 encryption, and public access block
- Data capture on inference endpoint — all requests and responses written to S3
- Application Auto Scaling with target tracking policy (1-3 instances)
- SageMaker Model Monitor running hourly data quality checks
- CloudWatch log group with 7-day retention and 4XX error alarm

## Tech Stack

- AWS SageMaker
- AWS S3
- AWS IAM
- AWS CloudWatch
- AWS Application Auto Scaling
- Terraform
- HuggingFace Transformers (distilbert-base-uncased-finetuned-sst-2-english)

## Project Structure

```
ml-inference-aws/
├── main.tf           # All resource definitions
├── variables.tf      # Input variable declarations
├── outputs.tf        # Output value declarations
├── terraform.tfvars  # Variable values (not committed to git)
└── .gitignore
```

## Usage

### Prerequisites

- Terraform >= 1.0
- AWS CLI v2 configured with appropriate permissions
- WSL / Linux / Mac terminal

### Deploy

```bash
git clone https://github.com/MitchKozlowski/MLInference
cd ml-inference-aws
terraform init
terraform plan
terraform apply
```

Endpoint creation takes approximately 8-10 minutes while SageMaker provisions the instance and pulls the container image.

### Test the Endpoint

```bash
aws sagemaker-runtime invoke-endpoint \
  --endpoint-name huggingface-sentiment-endpoint \
  --content-type application/json \
  --body '{"inputs": "Your text here"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
```

### Example Response

```json
[{"label":"POSITIVE","score":0.9998}]
```

### Verify Data Capture

```bash
aws s3 ls s3://your-bucket-name/data-capture/ --recursive
```

Inference requests and responses are captured to S3 within minutes of invocation, partitioned by endpoint, variant, date, and hour.

### Destroy

```bash
terraform destroy
```

Always destroy when not actively using — the ml.m5.large endpoint instance incurs cost while running (~$0.134/hr).

## Key Design Decisions & Tradeoffs

### HuggingFace Managed Container vs Custom Image
Used AWS's official HuggingFace PyTorch inference container rather than a custom image. The managed container handles the serving layer automatically, allowing focus on infrastructure rather than model packaging. Tradeoff: less control over the serving stack, but appropriate for this pattern where the infrastructure is the deliverable, not the model.

### ml.m5.large vs ml.t2.medium
Initially provisioned with ml.t2.medium for cost efficiency, but AWS does not support Application Auto Scaling on burstable instance types due to unpredictable CPU credit behavior. Migrated to ml.m5.large — a non-burstable general purpose instance — to enable auto scaling. Tradeoff: approximately 2x cost (~$0.065/hr vs ~$0.134/hr) in exchange for consistent, scalable performance.

### Least-Privilege IAM — Custom Policy vs Managed Policy
The SageMaker execution role uses a custom IAM policy scoped specifically to the project S3 bucket ARN rather than broad S3 access. AWS managed policy (AmazonSageMakerFullAccess) is attached for SageMaker internals such as ECR image pulling and CloudWatch logging — this is standard practice for SageMaker execution roles. Tradeoff: slightly more complex IAM configuration in exchange for a significantly reduced blast radius if credentials are compromised.

### Asymmetric Auto Scaling Cooldowns
Scale-out cooldown is set to 60 seconds while scale-in cooldown is set to 300 seconds. This means the endpoint responds aggressively to traffic spikes but scales in conservatively. Tradeoff: slightly higher cost during traffic lulls in exchange for avoiding endpoint thrashing and ensuring capacity is available during burst traffic.

### Data Capture at 100% Sampling
Configured data capture at 100% sampling rate rather than a lower percentage. For a dev environment this is appropriate — capturing all traffic gives full visibility into inference behavior. In production, 10-20% sampling is typical to reduce S3 storage costs at scale. Tradeoff: higher storage cost in exchange for complete inference observability during development.

### Model Monitor on ml.t3.medium
The data quality monitoring job uses ml.t3.medium rather than ml.m5.large due to AWS account-level service quota limits on processing job instances. In a production account with higher quotas, ml.m5.large or larger would be appropriate for monitoring jobs processing high volumes of captured data. Tradeoff: lower compute for monitoring jobs, acceptable for dev-scale inference volumes.

### No Baseline for Model Monitor
Model Monitor is configured for data quality monitoring without a statistical baseline. A proper baseline requires a representative sample of training data to establish expected distributions. In a real deployment the data science team owns baseline creation — the infrastructure engineer's responsibility is provisioning the monitoring schedule and output storage, which this project demonstrates. Tradeoff: monitoring runs and captures data but cannot flag drift without a baseline.
