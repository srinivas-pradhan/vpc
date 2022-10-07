locals {
  subnets = cidrsubnets(var.cidr_block, var.subnets[*].new_bits...)
  subnets_with_cidr = [for i, n in var.subnets : {
    name       = n.name
    az         = n.az
    cidr_block = n.name != null ? local.subnets[i] : tostring(null)
  }]
  subnt_map = { for s in local.subnets_with_cidr : s.name => { az = s.az, cidr_block = s.cidr_block } }
  private_subnet_ids = {
    for val in aws_subnet.main : val.tags.Name => {
      subnet_id = val.id
    }
    if !can(regex("^Public Subnet [[:digit:]]", val.tags.Name))
  }
  public_subnet_ids = {
    for val in aws_subnet.main : val.tags.Name => {
      subnet_id = val.id
    }
    if can(regex("^Public Subnet [[:digit:]]", val.tags.Name))
  }
  eips              = [for val in aws_eip.eip : val.public_ip]
  subnet_priv_names = [for k, v in local.private_subnet_ids : v.subnet_id]
  eip_map           = zipmap(local.subnet_priv_names, local.eips)
}

resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames
  tags                 = merge({ "Name" = var.vpc_name }, var.tags)
}

resource "aws_subnet" "main" {
  for_each          = local.subnt_map
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = join("", [var.region, each.value.az])
  tags              = merge({ "Name" = each.key }, var.tags)
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = merge({ "Name" = join("-", [var.vpc_name, "IGW"]) }, var.tags)
}

resource "aws_eip" "eip" {
  count      = length(local.private_subnet_ids)
  vpc        = true
  depends_on = [aws_internet_gateway.gw]
  tags       = merge({ "Name" = "Elastic IP - ${count.index}" }, var.tags)
}
