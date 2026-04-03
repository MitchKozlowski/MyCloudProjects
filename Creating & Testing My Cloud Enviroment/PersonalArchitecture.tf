provider "aws" {
  region = "ExampleRegion = ap-southeast-6"
}

# -------------------
# VARIABLES
# -------------------
variable "my_ip" {
  description = "ExampleIP = 32.145.32.195"
  default     = "ExampleIP = 32.145.32.195/32"
}

variable "key_name" {
  description = "Existing AWS key pair"
  default     = "ExampleKeyPairName"
}

# -------------------
# VPC
# -------------------
resource "aws_vpc" "main" {
  cidr_block = "ExampleCidr = 10.4.0.0/16"

  tags = {
    Name = "my-vpc"
  }
}

# -------------------
# SUBNET (Public)
# -------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "Examplecidr = 10.0.0.128/26"
  availability_zone       = "ExampleAZ = us-west-1c"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

# -------------------
# INTERNET GATEWAY
# -------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# -------------------
# ROUTE TABLE
# -------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "public-rt"
  }
}

# Route to internet
resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associate route table with subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# -------------------
# SECURITY GROUP
# -------------------
resource "aws_security_group" "ssh" {
  name   = "allow-ssh"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -------------------
# EC2 INSTANCE
# -------------------
resource "aws_instance" "web" {
  ami           = "ami-0c02fb55956c7d316" # Amazon Linux 2 (us-east-1)
  instance_type = "t3.small"

  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ssh.id]
  key_name               = var.key_name

  tags = {
    Name = "PersonalEC2Instance"
  }
}