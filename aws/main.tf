terraform {
  required_version = ">=0.13"
  required_providers {
      aws = ">=2.0"
  }
}

provider "aws" {
  region = "eu-west-3"
}

resource "aws_vpc" "default" {
  cidr_block = "10.10.0.0/24"
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
}
/** 
 *  Public subnets
 */
resource "aws_subnet" "publica" {
  vpc_id                  = aws_vpc.default.id
  map_public_ip_on_launch = true
  cidr_block              = "10.10.0.0/28"
  availability_zone       = "eu-west-3a"

  tags = {
    Name = "Subnet region a"
  }
}

resource "aws_subnet" "publicb" {
  vpc_id                  = aws_vpc.default.id
  map_public_ip_on_launch = true
  cidr_block              = "10.10.0.16/28"
  availability_zone       = "eu-west-3b"

  tags = {
    Name = "Subnet region b"
  }
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }

  tags = {
    Name = "Public-rt"
  }
}

resource "aws_route_table_association" "public_subneta_association" {
  subnet_id      = aws_subnet.publica.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_subnetb_association" {
  subnet_id      = aws_subnet.publicb.id
  route_table_id = aws_route_table.public.id
}

/** 
 *  Private subnets
 */
resource "aws_subnet" "privatea" {
  vpc_id                  = aws_vpc.default.id
  map_public_ip_on_launch = false
  cidr_block              = "10.10.0.32/28"
  availability_zone       = "eu-west-3a"

  tags = {
    Name = "Private subnet A"
  }
}

resource "aws_subnet" "privateb" {
  vpc_id                  = aws_vpc.default.id
  map_public_ip_on_launch = false
  cidr_block              = "10.10.0.48/28"
  availability_zone       = "eu-west-3b"

  tags = {
    Name = "Private subnet B"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.default.id

  tags = {
    Name = "Private-rt"
  }
}

resource "aws_route_table_association" "private_subnet_associationa" {
  subnet_id      = aws_subnet.privatea.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_subnet_associationb" {
  subnet_id      = aws_subnet.privateb.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "default" {
  name   = "default sg"
  vpc_id = aws_vpc.default.id

  tags = {
    Name = "Default Security Group"
  }
}

resource "aws_security_group_rule" "allow_HTTP_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.default.id

  from_port = 80
  to_port   = 80
  protocol  = "tcp"

  source_security_group_id = null
  cidr_blocks              = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_ssh_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.default.id

  from_port = 22
  to_port   = 22
  protocol  = "tcp"

  source_security_group_id = null
  cidr_blocks              = ["0.0.0.0/0"]
}


resource "aws_security_group_rule" "allow_all_outbound" {

  type              = "egress"
  security_group_id = aws_security_group.default.id

  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

// LOAD BALANCER

resource "aws_lb" "default" {
  name               = "application-load-balancer"
  load_balancer_type = "application"

  subnets         = [aws_subnet.publica.id, aws_subnet.publicb.id]
  security_groups = [aws_security_group.default.id]
}

resource "aws_lb_listener" "listener" {
  # host header is set create one listener with multiple rules
  # if not create one listener and one rule per target group
  load_balancer_arn = aws_lb.default.arn
  port              = 80
  protocol          = "HTTP"

  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_lb_target_group" "target" {
  name        = "server"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.default.id
  target_type = "instance"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = aws_lb_target_group.target.arn
  target_id        = aws_instance.instacesuba.id
  port             = 80
}

resource "aws_lb_listener_rule" "rule" {
  # If host header is set, add several rules to same listener on port 80 or 443 with decreasing priority
  # If not, add one rule per target group
  listener_arn = aws_lb_listener.listener.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target.arn
  }
}

resource "aws_instance" "instacesuba" {
  ami           = "ami-0ddab716196087271"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.publica.id
  user_data = "${file("user-data.sh")}"
  security_groups = [aws_security_group.default.id]

  tags = {
    Name = "Instance in subnet A"
  }
}

resource "aws_instance" "instacesubb" {
  ami           = "ami-0ddab716196087271"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.publicb.id
  user_data = "${file("user-data.sh")}"
  security_groups = [aws_security_group.default.id]

  tags = {
    Name = "Instance in subnet B"
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "subnet group for rds"
  subnet_ids = [aws_subnet.private_nat_a.id,aws_subnet.private_nat_b.id]

  tags = {
    Name = "My DB private subnet group"
  }
}

resource "aws_db_instance" "mysqldb" {
  allocated_storage    = 10
  db_subnet_group_name =  aws_db_subnet_group.default.name
  db_name              = "mydb"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  username             = "foo"
  password             = "foobarbaz"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
}

resource "aws_eip" "nat_a" {
  vpc   = true

  tags = {
    Name = "eip-nat"
  }
}

resource "aws_eip" "nat_b" {
  vpc   = true

  tags = {
    Name = "eip-nat"
  }
}

resource "aws_nat_gateway" "defaultpublic_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.publica.id

  tags = {
    Name = "nat-gateway-A"
  }
}

resource "aws_nat_gateway" "defaultpublic_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.publicb.id

  tags = {
    Name = "nat-gateway-B"
  }
}

resource "aws_subnet" "private_nat_a" {
  vpc_id                  = aws_vpc.default.id
  map_public_ip_on_launch = false
  cidr_block              = "10.10.0.64/28"
  availability_zone       = "eu-west-3a"

  tags = {
    Name = "Private nat subnet zone A"
  }
}

resource "aws_subnet" "private_nat_b" {
  vpc_id                  = aws_vpc.default.id
  map_public_ip_on_launch = false
  cidr_block              = "10.10.0.80/28"
  availability_zone       = "eu-west-3b"

  tags = {
    Name = "Private nat subnet zone B"
  }
}

resource "aws_route_table" "private_nat_a" {
  
  vpc_id = aws_vpc.default.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.defaultpublic_a.id
  }

  tags = {
    Name = "private_nat-rt-A"
  }
}

resource "aws_route_table" "private_nat_b" {
  
  vpc_id = aws_vpc.default.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.defaultpublic_b.id
  }

  tags = {
    Name = "private_nat-rt-B"
  }
}

resource "aws_route_table_association" "private_nat_subnet_association_a" {
  subnet_id      = aws_subnet.private_nat_a.id
  route_table_id = aws_route_table.private_nat_a.id
}

resource "aws_route_table_association" "private_nat_subnet_association_b" {
  subnet_id      = aws_subnet.private_nat_b.id
  route_table_id = aws_route_table.private_nat_b.id
}