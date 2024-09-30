terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.68.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "eu-west-1"
}

# 1. Create a VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "playground_vpc"
  }
}

# 2. Create Private Subnets (2 subnets in 2 different availability zones)
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-1a"
  map_public_ip_on_launch = false  # No public IP
  tags = {
    Name = "private_subnet_1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-1b"
  map_public_ip_on_launch = false  # No public IP
  tags = {
    Name = "private_subnet_2"
  }
}


# 3. Create NAT Gateway for private subnets to access the internet (optional)
# First, create a public subnet to place the NAT Gateway
resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-west-1a"
  map_public_ip_on_launch = true  # Public IP
  tags = {
    Name = "public_subnet_1"
  }
}
resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "eu-west-1b"
  map_public_ip_on_launch = true  # Public IP
  tags = {
    Name = "public_subnet_2"
  }
}

# Create an Internet Gateway for the NAT Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "playground_igw"
  }
}

#  4. Create public Route Table and Route to NAT Gateway
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "public_rt"
  }
}

# 4. Create Private Route Table and Route to NAT Gateway
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.my_nat_gw.id
  }

  tags = {
    Name = "private_rt"
  }
}


# 5. Associate Private Route Table with Private Subnets
resource "aws_route_table_association" "public_subnet_1_assoc" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "public_subnet_2_assoc" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_subnet_1_assoc" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "private_subnet_2_assoc" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}


# Create a NAT Gateway in the public subnet

resource "aws_nat_gateway" "my_nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_1.id
}

# Create Elastic IP for the NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}


# 6. Security Group for the Load Balancer
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # allow access from outside
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb_sg"
  }
}

# 7. Create an Internal Application Load Balancer
resource "aws_lb" "my_alb" {
  name               = "playground-internal-alb"
  internal           = false  # Internal ALB for private access only
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id] #aws_subnet.private_subnet_2.id

  tags = {
    Name = "my_internal_alb"
  }
}

# 8. Create a Target Group
resource "aws_lb_target_group" "my_target_group" {
  name     = "metabase"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "my_target_group"
  }
}

# 9. Create a Listener for the Load Balancer
resource "aws_lb_listener" "my_alb_listener" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}



resource "aws_instance" "my_ec2" {
  ami           = "ami-0fed63ea358539e44" # Amazon Linux 2 AMI (latest in us-east-1)
  instance_type = "t2.micro"
  associate_public_ip_address = true

  # User data script to install Docker and run Metabase
  user_data = templatefile("./scripts.sh", {})

  key_name      = "palygroundKey" # Specify your existing SSH key for access
  subnet_id    = aws_subnet.public_subnet_1.id # Specify the appropriate subnet ID
  security_groups  = [aws_security_group.ec2_sg.id]# Reference to security group below

  tags = {
    Name = "Metabase-Instance"
  }
}

# Security group to allow SSH and HTTP (port 3000 for Metabase)
resource "aws_security_group" "ec2_sg" {
  name   = "allow_ssh_http"
  vpc_id = aws_vpc.my_vpc.id
  description = "Allow SSH and HTTP traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow SSH from anywhere, restrict if needed
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # security_groups = ["0.0.0.0/0"] #[aws_security_group.alb_sg.id] # Allow HTTP (Metabase) from anywhere
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "EC2SecurityGroup"
  }
}
