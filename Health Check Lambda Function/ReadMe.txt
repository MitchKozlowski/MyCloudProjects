
AWS Serverless Infrastructure Monitoring System

A serverless, event-driven monitoring system built using AWS services and Infrastructure as Code (Terraform).
The system periodically checks the health of external services and logs results for observability.


Overview:

	- This project simulates a real-world cloud monitoring system similar to what is used in production environments for uptime tracking and service reliability.

	- It uses a fully serverless architecture to periodically check the health of configured endpoints stored in Amazon S3, eliminating the need for persistent servers or manual execution.
	
	
Architecture:

	The system is composed of the following AWS services:

		- AWS Lambda → Executes health check logic
		- Amazon EventBridge → Triggers Lambda on a schedule
		- Amazon S3 → Stores configuration (list of monitored servers)
		- AWS IAM → Manages secure access between services
		- Amazon CloudWatch → Captures logs and execution output
		- Terraform → Provisions all infrastructure as code
		
		
How It Works:

	1) A JSON configuration file containing a list of server URLs is stored in S3
	2) EventBridge triggers the Lambda function on a fixed schedule (e.g., every minute)
	3) The Lambda function retrieves the configuration from S3
	4) It performs HTTP health checks on each endpoint
	5) Results are printed to CloudWatch Logs for observability		
		
		
Key Design Decisions:

	Serverless Architecture:

	The system uses AWS Lambda instead of EC2 to eliminate infrastructure management and reduce cost, enabling automatic scaling and event-driven execution.
	

	Externalized Configuration (S3):

	Server endpoints are stored in S3 instead of being hardcoded. This allows updates to monitored services without redeploying code or infrastructure.

	
	Event-Driven Execution:

	Amazon EventBridge is used to trigger monitoring at regular intervals, simulating production-grade scheduling behavior.

	
	Infrastructure as Code:

	All AWS resources are provisioned using Terraform to ensure repeatability, version control, and reproducible deployments.
		
		
		
Implementation Guide:

	This section explains how to deploy and run the project step by step using Terraform and AWS.
	
	
	1) Prerequisites:

		Make sure you have the following installed and configured:

		- AWS CLI configured (aws configure)
		- Terraform installed (v1.3+ recommended)
		- Python 3.13+
		- An AWS account with permissions to create:
		- Lambda
		- S3
		- IAM roles
		- EventBridge rules
		
	
	
	2) Clone the Repository:
	
	git clone https://github.com/https://github.com/MitchKozlowski/MyCloudProjects/cloud-health-monitor.git
	cd cloud-health-monitor
	
	
	3) Configure the Server List:

		Edit the servers.json file:
			[
		  "https://google.com",
		  "https://github.com",
		  "https://example.com"
			]
	- This file defines which endpoints will be monitored.
	
	
	
	4) Package the Lambda Function:

		Install dependencies and create deployment package:
	
		cd lambda
		pip install requests -t .
		zip -r ../lambda.zip .
		cd ..
	
	
	5) Initialize and Plan:
	
		terraform init
		terraform plan
	
	This will show all AWS resources that will be created:

		S3 bucket (for config storage)
		Lambda function (health checks)
		IAM roles (permissions)
		EventBridge rule (scheduler)
	
	
	6) Deploy the infrastructure:
	
		terraform apply
		
	- Type yes when prompted.
	
	7) Verify Deployment

		After deployment:

		- Go to AWS Lambda Console
		- Confirm function exists: health-check-monitor
		- Go to EventBridge
		- Confirm schedule rule is active
		- Go to S3
		- Confirm servers.json exists in bucket
		- Go to CloudWatch Logs
		- View health check execution logs
	
		You should see logs like:
		
		[OK] https://google.com
		[DOWN] https://invalid-site.com
	