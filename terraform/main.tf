#data to pull in the attributed for ActiveMQ engine
data "aws_mq_broker_instance_type_offerings" "engine" {
  engine_type = "ACTIVEMQ"
}

data "aws_availability_zones" "pri_available" {
  state = "available"
}

data "aws_availability_zones" "dr_available" {
  provider = aws.dr
  state = "available"
}

module "pri_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.env_name
  cidr = var.cidr_block

  azs             = [data.aws_availability_zones.pri_available.names[0], data.aws_availability_zones.pri_available.names[1], data.aws_availability_zones.pri_available.names[2]]
  private_subnets = [cidrsubnet(var.cidr_block, 4, 0), cidrsubnet(var.cidr_block, 4, 1), cidrsubnet(var.cidr_block, 4, 2)]
  public_subnets  = [cidrsubnet(var.cidr_block, 4, 3), cidrsubnet(var.cidr_block, 4, 4), cidrsubnet(var.cidr_block, 4, 5)]

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }

}

module "dr_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  providers = {
    aws = aws.dr
  } 

  name = var.env_name
  cidr = var.cidr_block

  azs             = [data.aws_availability_zones.dr_available.names[0], data.aws_availability_zones.dr_available.names[1], data.aws_availability_zones.dr_available.names[2]]
  private_subnets = [cidrsubnet(var.cidr_block, 4, 0), cidrsubnet(var.cidr_block, 4, 1), cidrsubnet(var.cidr_block, 4, 2)]
  public_subnets  = [cidrsubnet(var.cidr_block, 4, 3), cidrsubnet(var.cidr_block, 4, 4), cidrsubnet(var.cidr_block, 4, 5)]

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }

}


#deploys the Rabbit MQ cluster in the primary region
resource "aws_mq_broker" "primary" {
  broker_name = "activemq_primary"

  engine_type         = "ActiveMQ"
  engine_version      = data.aws_mq_broker_instance_type_offerings.engine.broker_instance_options.0.supported_engine_versions.0
  host_instance_type  = "mq.m5.large"
  deployment_mode     = "ACTIVE_STANDBY_MULTI_AZ"
  publicly_accessible = true

  subnet_ids = [ module.pri_vpc.public_subnets.0, module.pri_vpc.public_subnets.1 ]
  security_groups = [ module.pri_vpc.default_security_group_id ]

  user {
    username = var.user
    password = var.password
    console_access = true
  }
}

# Configuraiton for dr broker
resource "aws_mq_configuration" "dr_link" {
  provider = aws.dr
  description    = "Cross Region Replication"
  name           = "CRDR"
  engine_type    = "ActiveMQ"
  engine_version = data.aws_mq_broker_instance_type_offerings.engine.broker_instance_options.0.supported_engine_versions.0

  data = <<DATA
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<broker xmlns="http://activemq.apache.org/schema/core" schedulePeriodForDestinationPurge="10000">
  <destinationPolicy>
    <policyMap>
      <policyEntries>
        <policyEntry topic="&gt;" gcInactiveDestinations="true" inactiveTimoutBeforeGC="600000">
          <pendingMessageLimitStrategy>
            <constantPendingMessageLimitStrategy limit="1000"/>
          </pendingMessageLimitStrategy>
        </policyEntry>
        <policyEntry queue="&gt;" gcInactiveDestinations="true" inactiveTimoutBeforeGC="600000" />
      </policyEntries>
    </policyMap>
  </destinationPolicy>
  <plugins>
  </plugins>
  <networkConnectors>
    <networkConnector name="brokerinDRRegion_to_ brokerinPriRegion" duplex="true" networkTTL="5" userName="${var.user}" uri="static:(${aws_mq_broker.primary.instances.0.endpoints.0})" />
  </networkConnectors>
</broker>
DATA
}


#deploys the Active MQ cluster in the secondary region
resource "aws_mq_broker" "secondary" {
  provider = aws.dr
  broker_name = "active_secondary"
  depends_on = [
    aws_mq_configuration.dr_link
  ]
  configuration {
    id       = aws_mq_configuration.dr_link.id
    revision = aws_mq_configuration.dr_link.latest_revision
  }

  engine_type         = "ActiveMQ"
  engine_version      = data.aws_mq_broker_instance_type_offerings.engine.broker_instance_options.0.supported_engine_versions.0
  host_instance_type  = "mq.m5.large"
  deployment_mode     = "ACTIVE_STANDBY_MULTI_AZ"
  publicly_accessible = true

  subnet_ids = [ module.dr_vpc.public_subnets.0, module.dr_vpc.public_subnets.1 ]
  security_groups = [ module.dr_vpc.default_security_group_id ]

  user {
    username = var.user
    password = var.password
    console_access = true
  }
}