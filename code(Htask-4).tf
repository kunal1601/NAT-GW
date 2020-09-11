#Providing login credentials to aws
provider "aws" {
  region     = "ap-south-1"
  profile    = "jack" 
}

#Creating private key
resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits = 4096
}
resource "aws_key_pair" "generated_key" {
 key_name = "wordpress_key"
 public_key = tls_private_key.key.public_key_openssh

depends_on = [
    tls_private_key.key
]
}

#Downloading priavte key
resource "local_file" "file" {
    content  = tls_private_key.key.private_key_pem
    filename = "C:/Users/NMC/Downloads/wordpress_key.pem"
    file_permission = "0400"
}

#creating vpc
resource "aws_vpc" "new-vpc" {
  cidr_block       = "192.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = "true"

  tags = {
    Name = "new-vpc"
  }
}
#Creating Public Subnet
resource "aws_subnet" "public" {
  depends_on = [aws_vpc.new-vpc, ]
  vpc_id     = aws_vpc.new-vpc.id
  cidr_block = "192.168.0.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch  =  true
  tags = {
    Name = "Public"
  }
}

#Creating Private Subnet
resource "aws_subnet" "private" {
  depends_on = [ aws_vpc.new-vpc,
                  aws_subnet.public, ]
  vpc_id     = aws_vpc.new-vpc.id
  cidr_block = "192.168.1.0/24"
  availability_zone = "ap-south-1b"
    tags = {
    Name = "Private"
  }
}
# Creating Internet Gateway
resource "aws_internet_gateway" "int-gw" {
  depends_on = [ aws_vpc.new-vpc,
                   aws_subnet.public, ]
  vpc_id = aws_vpc.new-vpc.id

  tags = {
    Name = "new-gw"
  }
}

#creating routing table to access Internet Gateway
resource "aws_route_table" "new-rt" {
  depends_on = [aws_internet_gateway.int-gw, ]
  vpc_id = aws_vpc.new-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.int-gw.id
    }
   tags = {
    Name = "routing table"
  }
} 
resource "aws_route_table_association" "new" {
   depends_on = [ aws_route_table.new-rt, ]
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.new-rt.id
}

# Creating Elastic ip
resource "aws_eip" "public_ip" {
  vpc      = true
}
#creating Nat Gateway
resource "aws_nat_gateway" "NAT-gw" {
  allocation_id = aws_eip.public_ip.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "NAT-GW"
  }
}
#Creating routing table to access NAT Gateway
resource "aws_route_table" "new2-rt" {
  vpc_id =  aws_vpc.new-vpc.id

route {
    cidr_block = "0.0.0.0/0"
     gateway_id = aws_nat_gateway.NAT-gw.id
}
   
 tags = {
    Name = "NAT_table"
  }
}
resource "aws_route_table_association" "new2" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.new2-rt.id
}
#creating security group for wordpress
resource "aws_security_group" "wordpress-sg" {
 depends_on = [ aws_vpc.new-vpc, ]
  name        = "wordpress-sg"
  description = "All HTTP,SSH inbound traffic"
  vpc_id      = aws_vpc.new-vpc.id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-sg"
  }
}
#Creating Security group of bastion host
resource "aws_security_group" "bastion" {
  name        = "bastion"
  description = "Bastion host security group"
  vpc_id      =  aws_vpc.new-vpc.id
  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
}
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name ="bastion"
  }
}
# Creating Security group for Mysql
resource "aws_security_group" "mysql-sg" {
  depends_on = [ aws_vpc.new-vpc,
                   aws_security_group.wordpress-sg, ]
  name        = "mysql_sg"
  description = "Allow Wordpress"
  vpc_id      = aws_vpc.new-vpc.id

  ingress {
    description = "MYSQL from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = ["${aws_security_group.wordpress-sg.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Mysql-sg"
  }
}

# Creating another Security group for Mysql that allow only bastion host security group
resource "aws_security_group" "bastion_allow" {
  name        = "bashion_allow"
  description = "Mysql security group that allow only bashion host security group"
  vpc_id      = aws_vpc.new-vpc.id
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name ="bastion_allow"
  }
}
# Creating Bastion instance
resource "aws_instance" "bastion" {
  ami           = "ami-09a7bbd08886aafdf"
  instance_type = "t2.micro"
  key_name = "wordpress_key"
  vpc_security_group_ids =[aws_security_group.bastion.id]
  subnet_id = aws_subnet.public.id
 
  tags = {
    Name = "bastion_os"
  }
}
# Creating wordpress instance
resource "aws_instance" "wordpress" {
 depends_on = [   aws_subnet.public,
                  aws_security_group.wordpress-sg, ]
  ami           = "ami-02b9afddbf1c3b2e5"
  instance_type = "t2.micro"
  key_name = "wordpress_key"
  vpc_security_group_ids = [aws_security_group.wordpress-sg.id]
  subnet_id = aws_subnet.public.id
 tags = {
    Name = "WordPress"
  }
}
#Creating Mysql instance
resource "aws_instance" "mysql" {
depends_on = [    aws_subnet.private,
                  aws_security_group.mysql-sg, ]
  ami           = "ami-0d8b282f6227e8ffb"
  instance_type = "t2.micro"
  key_name = "wordpress_key"
  vpc_security_group_ids = [aws_security_group.mysql-sg.id,
                            aws_security_group.bastion_allow.id      
    ]
  subnet_id = aws_subnet.private.id
 tags = {
    Name = "Mysql"
  }
}
