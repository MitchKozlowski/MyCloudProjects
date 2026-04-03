
Purpose:

	- The purpose of this personal project is to setup an enviroment where I have access to a VM in the cloud, where I can continue building architecture.
	- In the future I can add a database, sns & sqs queues, Lambda functions and much more
	
	- The VPC is in public aws space, and has an IGW, as well as an SG, So that I can connect to my EC2 instance from my desktop
	- The security group allows inbound SSH (port 22) from my local IP only, minimizing exposure to the internet.
	
	- I chose to use a /26 network for potential expansion of my personal resources. This should give me plenty of room compared to a /28.
	  A /26 provides 64 IP addresses, of which 5 are reserved by AWS, leaving 59 usable addresses.

 *** Refer to PersonalArchitecture.tf ***
I attached the terraform file I used to create my personal infrastructure. However you may notice that I redacted and changed some of the variable as to not compromise myself.


Attached AmazonEC2FullAccess & AmazonS3FullAccess IAM roles. These policies were used for initial testing. In a production environment, 
I would replace them with custom IAM policies scoped to only the required actions (e.g., s3:CreateBucket, ec2:DescribeInstances).
I could attach "AdministratorAccess", but it's best practice to restrict the instance role to only using the permission it needs.

	- Normally on desktop I would point the terraform directory to my access & secret keys

 *** Refer to IamInstanceRole.png ***

	- This is the instance role that I attached to my personal EC2 instance
	- The IAM role can be created with terraform, for simplicity I used the management console for testing.
	  For the sake of automation and reusablility, I would put this in the tf file if I were going to re-create this architecture in the future.

 *** Refer to BucketTest.tf & BucketCreationVerification.png ***

	- Using Terraform to apply BucketTest.tf, I was able to create a simple S3 bucket using the EC2 instance.
	- This simply verifies that Terraform is installed and configured correctly on my EC2 instance. It also shows that it has the least amount of privelege 
	  necessary to create an S3 bucket.




