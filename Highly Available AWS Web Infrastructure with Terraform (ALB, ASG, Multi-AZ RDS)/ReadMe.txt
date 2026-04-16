
Purpose:

	This project demonstrates the design and deployment of a highly available, production-style AWS architecture using Terraform. The goal was to build a scalable, fault-tolerant system with proper network isolation, load balancing, and a managed database layer.

	The environment includes:

		- A custom VPC with public and private subnets
		- An internet-facing Application Load Balancer (ALB)
		- An Auto Scaling Group (ASG) running EC2 instances in private subnets
		- A Multi-AZ RDS MySQL database
		- NAT Gateway for secure outbound internet access

	The project validates end-to-end connectivity by having EC2 instances connect to RDS and display the result via the ALB.


Design Tradeoffs:

	Nat Gateway:
		- For this project only 1 NAT Gateway was provisioned. This of course means less Resillience,
		but keeps the cost down. For a real production system 2 NAT Gateways would be required, however because the
		NAT Gateway is only used for potential updates, I can justify only using 1 for this project.

	Multi-AZ RDS:
		- This gives our database high availablilty and automatic failover. This doubles the cost of the service,
		but is essential to ensure data integrity and reduce any down time. The data is synchronous between the 
		2 DBs.
	
	Hardcoded Credentials:
		- The DB credentials are hard coded into the main.tf file. This is very bad practice for real world
		solutions. Here it was used for simplicity, to test the connection between the ASG and DB.
		I would recommened using AWS Secrets Manager to store the credentials.

Architecture:

	High-Level Flow:

		Internet
		   ↓
		Application Load Balancer (Public Subnets)
		   ↓
		Auto Scaling Group (Private App Subnets)
		   ↓
		RDS MySQL (Private DB Subnets, Multi-AZ)



Networking Design:
	
	
	VPC:
		CIDR: 10.0.0.0/22
		Subnets (2 Availability Zones)
		
		Type			AZ1				AZ2
		Public			10.0.0.0/27		10.0.0.32/27
		Private (App)	10.0.0.64/26	10.0.0.128/26
		Private (DB)	10.0.0.192/28	10.0.0.208/28

	-I chose to use the CIDR 10.0.0.0/22 because that gives me 1024 possible IP addresses.
	This is more than enough for a project of this scope, and leaves room for future expansion.


Security Design:

	Security Groups

		ALB Security Group:

			Inbound: HTTP (80) from 0.0.0.0/0
			Outbound: All traffic

		ASG Security Group:

			Inbound: HTTP (80) from ALB SG only
			Outbound: All traffic

		RDS Security Group:

			Inbound: MySQL (3306) from ASG SG only
			Outbound: All traffic


Internet Access:

	Internet Gateway (IGW)
		- Attached to VPC
		- Used by public subnets
	
	NAT Gateway
		- Placed in a public subnet
		- Uses Elastic IP
		- Enables private instances to:
		- Install packages
		- Reach external services


Routing:

	Public Route Table
		- 0.0.0.0/0 → IGW
		- Associated with public subnets
	
	Private Route Table
		- 0.0.0.0/0 → NAT Gateway
		- Associated with private app subnets
	
	DB Subnets
		- No direct internet route
		- Fully isolated

Compute Layer (ASG):

	Launch Template
		- Amazon Linux 2
		- Installs:
		    - Nginx
		    - MySQL client
		- Runs a simple DB connectivity test
	
	Auto Scaling Group
		- Multi-AZ deployment
		- Desired capacity: 2
		- Integrated with ALB target group


Load Balancing:

	Application Load Balancer
		- Internet-facing
		- Deployed across 2 public subnets
		- Listener on port 80
		- Routes traffic to ASG instances

Database Layer:

	RDS MySQL (Multi-AZ)
		- Engine: MySQL 8.0
		- Instance type: db.t3.micro
		- Multi-AZ enabled
	
	Behavior
		- Primary instance handles reads/writes
		- Standby instance in another AZ
		- Synchronous replication
		- Automatic failover


Testing:

	Instead of building a full application, a lightweight validation approach was used.
	I wanted a simple way to test that the ASG and RDS DB were connected and working properly.
	This way I know that the infrastructure is configured properly, and an application could be
	built on it if needed:

	EC2 User Data Script:
	
		- Installs required packages
		- Connects to RDS
		
		Runs:
		- SHOW DATABASES;
		- Outputs result to web page
	
	Result

		Accessing the ALB DNS displays:
			- Successful DB connection
			- Available databases
		
		*** Refer to Screenshot DBTest.png ***
		
		
	ALB + ASG Validation:

		To verify that the Application Load Balancer (ALB) and Auto Scaling Group (ASG) were correctly configured, a simple test was implemented to confirm that traffic was being properly distributed across multiple EC2 instances.

		Approach:

		Each EC2 instance was configured (via user data) to:

		Install and run nginx
		Retrieve its own instance ID from the instance metadata service
		Display the instance ID on the default web page
		Implementation

		The following logic was used in the EC2 user data script:

		INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

		echo "<h1>Hello from $INSTANCE_ID</h1>" > /usr/share/nginx/html/index.html
		Result

		When accessing the ALB DNS endpoint in a browser:

		Refreshing the page resulted in different instance IDs being displayed
		
		This confirmed that:
		- Traffic was being routed through the ALB
		- Requests were being distributed across multiple EC2 instances
		- The ASG was successfully maintaining multiple healthy instances
	
		*** Refer to Screenshots (ASGTest1.png, ASGTest2.png)

		This test validated:

		- Proper ALB listener and target group configuration
		- Successful ASG instance provisioning across multiple Availability Zones
		- Functional end-to-end request routing from the internet to private EC2 instances


Future Improvements:

	- Replace user_data script with a real backend (Node.js / Flask)
	- Add HTTPS using ACM
	- Store DB credentials in Secrets Manager
	- Introduce CI/CD pipeline for automated deployments
	- Add CloudWatch logging and monitoring
	- Add read replicas for scaling reads
	
	
Summary:

	This project demonstrates a production-style AWS architecture with:

	- High availability across multiple AZs
	- Secure network segmentation
	- Scalable compute layer with ASG
	- Managed database with failover
	- Infrastructure fully defined in Terraform