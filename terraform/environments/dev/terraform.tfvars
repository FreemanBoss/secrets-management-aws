project_name = "secrets-mgmt"
environment  = "dev"
region       = "us-east-1"

vpc_cidr = "10.0.0.0/16"

eks_cluster_version = "1.29"
eks_node_instance_types = ["t3.medium"]
eks_node_desired_size = 2
eks_node_min_size = 1
eks_node_max_size = 5

rds_instance_class = "db.t3.micro"
rds_allocated_storage = 20
