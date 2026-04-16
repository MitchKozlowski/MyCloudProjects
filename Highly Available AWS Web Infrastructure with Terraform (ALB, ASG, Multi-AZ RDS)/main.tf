provider "aws" {
	region = "us-east-1"
}

# EIP Allocation to the account--------------------------------
resource "aws_eip" "AppNatEip" {
  domain = "vpc"
  
  tags = {
	Name = "AppNatEip"
  }
}

# VPC Creation--------------------------------------------------	
resource "aws_vpc" "AppVpc"{
	
	cidr_block = "10.0.0.0/22"
		
	tags = {
		Name = "AsgApp"
	}
	
}
	
# IGW Creation--------------------------------------------------	
resource "aws_internet_gateway" "AppIgw" {
	
	vpc_id = aws_vpc.AppVpc.id
	
	tags = {
		Name = "AppIgw"
	}
	
}

# Nat Gateway Creation--------------------------------------------------
resource "aws_nat_gateway" "AppNat" {
  allocation_id = aws_eip.AppNatEip.id
  subnet_id     = aws_subnet.Public2.id

  depends_on = [aws_internet_gateway.AppIgw]
  
  tags = {
	Name = "AppNat"
  }
}

# Subnet(s) Creation--------------------------------------------------
resource "aws_subnet" "Public1"{

        vpc_id = aws_vpc.AppVpc.id
        cidr_block = "10.0.0.0/27"
        availability_zone = "us-east-1c"
		map_public_ip_on_launch = true

        tags = {
        Name = "Public1"
        }
}

resource "aws_subnet" "Public2"{

        vpc_id = aws_vpc.AppVpc.id
        cidr_block = "10.0.0.32/27"
        availability_zone = "us-east-1d"
		map_public_ip_on_launch = true

        tags = {
        Name = "Public2"
        }
}

resource "aws_subnet" "Private_ASG_1C"{

        vpc_id = aws_vpc.AppVpc.id
        cidr_block = "10.0.0.64/26"
        availability_zone = "us-east-1c"

        tags = {
        Name = "Private_ASG_1C"
        }
}

resource "aws_subnet" "Private_ASG_1D"{

        vpc_id = aws_vpc.AppVpc.id
        cidr_block = "10.0.0.128/26"
        availability_zone = "us-east-1d"

        tags = {
        Name = "Private_ASG_1D"
        }
}

resource "aws_subnet" "Private_RDS_1C"{

        vpc_id = aws_vpc.AppVpc.id
        cidr_block = "10.0.0.192/28"
        availability_zone = "us-east-1c"

        tags = {
        Name = "Private_RDS_1C"
        }
}

resource "aws_subnet" "Private_RDS_1D"{

        vpc_id = aws_vpc.AppVpc.id
        cidr_block = "10.0.0.208/28"
        availability_zone = "us-east-1d"

        tags = {
        Name = "Private_RDS_1D"
        }
}


# IGW Route Table Creation--------------------------------------------------
resource "aws_route_table" "AppIgwRt"{

	vpc_id = aws_vpc.AppVpc.id
	
	route{
	cidr_block = "0.0.0.0/0"
	gateway_id = aws_internet_gateway.AppIgw.id
	}

	tags = {
		Name = "AppIgwRt"
	}

}


# NAT Route Table Creation--------------------------------------------------
resource "aws_route_table" "AppNatRt"{

	vpc_id = aws_vpc.AppVpc.id
	
	route{
	cidr_block = "0.0.0.0/0"
	nat_gateway_id = aws_nat_gateway.AppNat.id
	}

	tags = {
		Name = "AppNatRt"
	}

}


# Route Table Associations-----------------------------------------------

resource "aws_route_table_association" "Public1Assoc" {
  subnet_id      = aws_subnet.Public1.id
  route_table_id = aws_route_table.AppIgwRt.id
}

resource "aws_route_table_association" "Public2Assoc" {
  subnet_id      = aws_subnet.Public2.id
  route_table_id = aws_route_table.AppIgwRt.id
}

resource "aws_route_table_association" "PrivateAsg1CAssoc"{
	subnet_id = aws_subnet.Private_ASG_1C.id
	route_table_id = aws_route_table.AppNatRt.id
}

resource "aws_route_table_association" "PrivateAsg1DAssoc" {
  subnet_id      = aws_subnet.Private_ASG_1D.id
  route_table_id = aws_route_table.AppNatRt.id
}

# Security Group(s) Creation-------------------------------------------------- 
resource "aws_security_group" "AlbSG" {
  name        = "AlbSG"
  description = "Allow HTTP from internet"
  vpc_id      = aws_vpc.AppVpc.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "AlbSG"
  }
}

resource "aws_security_group" "AsgSg"{
	name = "AsgSg"
	description = "Traffic from ALB to ASG"
	vpc_id = aws_vpc.AppVpc.id

	ingress{
		description = "HTTP from ALB only"
	    from_port       = 80
		to_port         = 80
		protocol        = "tcp"
		security_groups = [aws_security_group.AlbSG.id]
	}

	egress{
		description = "Allow all outbound"
		from_port = 0
		to_port = 0
		protocol = -1
		cidr_blocks = ["0.0.0.0/0"]
	}

	tags = {
		Name = "AsgSg"
	}

}
# ALB Creation--------------------------------------------------
resource "aws_lb" "AppAlb" {
  name               = "AppAlb"
  load_balancer_type = "application"
  internal           = false

  security_groups = [aws_security_group.AlbSG.id]

  subnets = [
    aws_subnet.Public1.id,
    aws_subnet.Public2.id
  ]

  tags = {
    Name = "AppAlb"
  }
}

# Target Group Creation--------------------------------------------------
resource "aws_lb_target_group" "AppTG" {
  name     = "AppTG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.AppVpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "AppTG"
  }
}

# Listener Creation--------------------------------------------------
resource "aws_lb_listener" "HttpListener" {
  load_balancer_arn = aws_lb.AppAlb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.AppTG.arn
  }
}


# Launch Template Creation--------------------------------------------------
resource "aws_launch_template" "AppLaunchTemplate" {
  name_prefix   = "AppLT"
  image_id      = "ami-0c02fb55956c7d316" # Amazon Linux 2 (us-east-1)
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.AsgSg.id]

	user_data = base64encode(<<-EOF
	#!/bin/bash

	# Install nginx + mysql client
	amazon-linux-extras install -y nginx1
	yum install -y mysql

	systemctl start nginx
	systemctl enable nginx

	# Wait for DB
	sleep 60

	# Test DB connection
	RESULT=$(mysql -h app-rds-db.c45qkiomky11.us-east-1.rds.amazonaws.com -u admin -pSecretPass1234! -e "SHOW DATABASES;" 2>&1)
	
	# Output result to webpage
	echo "<h1>DB Connection Test</h1><pre>$RESULT</pre>" > /usr/share/nginx/html/index.html

	EOF
	)

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "AsgInstance"
    }
  }
}

# ASG Creation--------------------------------------------------

resource "aws_autoscaling_group" "AppAsg" {
  desired_capacity = 2
  max_size         = 4
  min_size         = 2

  vpc_zone_identifier = [
    aws_subnet.Private_ASG_1C.id,
    aws_subnet.Private_ASG_1D.id
  ]

  target_group_arns = [aws_lb_target_group.AppTG.arn]

  launch_template {
    id      = aws_launch_template.AppLaunchTemplate.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "AppASGInstance"
    propagate_at_launch = true
  }
}

# RDS Security Group --------------------------------------------------------
resource "aws_security_group" "RdsSG" {
  name        = "RdsSG"
  description = "Allow DB access from ASG"
  vpc_id      = aws_vpc.AppVpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.AsgSg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RdsSG"
  }
}

# RDS Subnet Group -----------------------------------------------------------------
resource "aws_db_subnet_group" "AppDbSubnetGroup" {
  name = "app-db-subnet-group"

  subnet_ids = [
    aws_subnet.Private_RDS_1C.id,
    aws_subnet.Private_RDS_1D.id
  ]

  tags = {
    Name = "AppDbSubnetGroup"
  }
}

# RDS Instance Creation----------------------------------------------------------
resource "aws_db_instance" "AppRds" {
  identifier = "app-rds-db"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage = 20

  db_name  = "appdb"
  username = "admin"
  password = "SecretPass1234!" 

  multi_az = true

  db_subnet_group_name   = aws_db_subnet_group.AppDbSubnetGroup.name
  vpc_security_group_ids = [aws_security_group.RdsSG.id]

  publicly_accessible = false
  skip_final_snapshot = true

  tags = {
    Name = "AppRds"
  }
}