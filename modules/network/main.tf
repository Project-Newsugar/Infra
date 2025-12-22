resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.project_name}-${var.env}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-${var.env}-igw" }
}

# Public Subnets
resource "aws_subnet" "public" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index) # .0, .1
  availability_zone = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.project_name}-${var.env}-public-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Private App Subnets (EKS 노드가 배치될 곳)
resource "aws_subnet" "app" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10) # .10, .11
  availability_zone = var.azs[count.index]

  tags = {
    Name                              = "${var.project_name}-${var.env}-private-app-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Private Data Subnets
resource "aws_subnet" "data" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20) # .20, .21
  availability_zone = var.azs[count.index]

  tags = { Name = "${var.project_name}-${var.env}-private-data-${count.index + 1}" }
}

# NAT Gateway
resource "aws_eip" "nat" {
  count  = var.nat_count
  domain = "vpc"
  tags   = { Name = "${var.project_name}-${var.env}-eip-${count.index + 1}" }
}

resource "aws_nat_gateway" "nat" {
  count         = var.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index % length(var.azs)].id
  tags          = { Name = "${var.project_name}-${var.env}-nat-${count.index + 1}" }
}

# Route Tables (Public)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project_name}-${var.env}-public-rt" }
}

# Route Tables (Private)
resource "aws_route_table" "private" {
  count  = length(var.azs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    # NAT 개수에 따라 라우팅 분배 (NAT가 1개면 모두 0번 NAT로, 2개면 각자 AZ로)
    nat_gateway_id = aws_nat_gateway.nat[count.index % var.nat_count].id
  }
  tags = { Name = "${var.project_name}-${var.env}-private-rt-${count.index + 1}" }
}

# Associations 생략 (위와 동일한 로직으로 작성)
resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "app" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
resource "aws_route_table_association" "data" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
