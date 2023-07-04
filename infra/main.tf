terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.4.0"
    }
  }
}

provider "aws" {
  # Configuration options
  region = "eu-central-1"
}

resource "aws_default_vpc" "default-vpc"{
  tags = {
    Name="Default Vpc"
  }
}
resource "aws_default_subnet" "default-subnet-1" {
  availability_zone = "eu-central-1a"
  tags = {
    Name = "Default subnet for eu-central-1a"
  }
}
resource "aws_default_subnet" "default-subnet-2" {
  availability_zone = "eu-central-1b"

  tags = {
    Name = "Default subnet for eu-central-1b"
  }
}
resource "aws_security_group" "alb-sg"{
  description = "sg for the ALB"
  name = "alb-sg"
  vpc_id = aws_default_vpc.default-vpc.id
  ingress {
    description="Allow HTTP from all"
    from_port=80
    to_port=80
    protocol="tcp"
    cidr_blocks=["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }

  egress {
    description="Allow to all"
    from_port=0
    to_port=0
    protocol=-1
    cidr_blocks=["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }

}
resource "aws_security_group" "fargate-sg"{
  description = "sg for the Fargate Service"
  name = "fargate-sg"
  vpc_id = aws_default_vpc.default-vpc.id
  ingress {
    description="Allow HTTP from ALB"
    from_port=8080
    to_port=8080
    protocol="tcp"
    security_groups=[aws_security_group.alb-sg.id]
  }
  egress {
    description="Allow to all"
    from_port=0
    to_port=0
    protocol=-1
    cidr_blocks=["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }

}
resource "aws_security_group" "postgres-sg"{
  description = "sg for the Postgres"
  name = "postgres-sg"
  vpc_id = aws_default_vpc.default-vpc.id
  ingress {
    description="Allow HTTP from Fargate Service"
    from_port=5432
    to_port=5432
    protocol="tcp"
    cidr_blocks=["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }
  egress {
    description="Allow to all"
    from_port=0
    to_port=0
    protocol=-1
    cidr_blocks=["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }

}
data "aws_iam_policy_document" "ecs-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "fargate-execution" {
  name = "fargate-execution-role"

  assume_role_policy = data.aws_iam_policy_document.ecs-assume-role-policy.json
  inline_policy {
    name = "execution_role"
    policy = jsonencode({
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          "Resource": "*"
        }
      ]
    })

  }

}
resource "aws_iam_role" "fargate-s3-role" {
  name = "fargate-s3-role"

  assume_role_policy = data.aws_iam_policy_document.ecs-assume-role-policy.json
  inline_policy {
    name = "role_for_s3"
    policy = jsonencode({
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "s3:*",
          ],
          "Resource": "*"
        }
      ]
    })
  }

}

resource "aws_lb" "alb-for-fargate" {
  name = "alb-for-spring"
  internal = false
  load_balancer_type = "application"
  security_groups =[aws_security_group.alb-sg.id]
  subnets =[aws_default_subnet.default-subnet-1.id,aws_default_subnet.default-subnet-2.id]
}
resource "aws_lb_target_group" "alb-tg-fargate" {
  port     = 80
  protocol = "HTTP"
  target_type = "ip"
  vpc_id   = aws_default_vpc.default-vpc.id
  lifecycle {
    create_before_destroy = true
  }

}
resource "aws_lb_target_group" "alb-tg-jvmLambda" {
  target_type = "lambda"
  name = "jvmLambdaTg"
}

resource "aws_lb_target_group" "alb-tg-nativeLambda" {
  target_type = "lambda"
  name = "nativeLambdaTg"
}


resource "aws_lb_listener" "fargate-listener" {
  load_balancer_arn = aws_lb.alb-for-fargate.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-tg-fargate.arn
  }
}
resource "aws_lb_listener_rule" "direct-to-jvm"  {
  listener_arn = aws_lb_listener.fargate-listener.arn
  action {
type = "forward"
target_group_arn = aws_lb_target_group.alb-tg-jvmLambda.arn
}
condition {
path_pattern {
values = ["/jvm/lambda*"]
}
}
}
resource "aws_lb_listener_rule" "direct-to-native"  {
  listener_arn = aws_lb_listener.fargate-listener.arn
  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.alb-tg-nativeLambda.arn
  }
  condition {
    path_pattern {
      values = ["/native/lambda*"]
    }
  }
}
resource aws_cloudwatch_log_group "quarkus-backend-logs"{
  name = "quarkus-backend"
}
resource "aws_s3_bucket" "users-bucket" {
  bucket = "adessopg-users"
}
resource "aws_s3_bucket_versioning" "users-bucket-versioning" {
  bucket = aws_s3_bucket.users-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_ecs_task_definition" "quarkus-task" {
  cpu = "512"
  memory = "2048"
  family = "service"
  container_definitions = <<TASK_DEFINITION
    [
    {
      "name":"quarkus-backend",
      "image":"your ECR url here",
      "cpu":512,
      "memory":2048,
      "portMappings":[{
        "containerPort":8080,
        "hostPort":8080
      }],
      "environment":[{"name":"db_url","value":"jdbc:postgresql://${aws_db_instance.usersDb.endpoint}/${aws_db_instance.usersDb.db_name}"},{"name":"db_username","value":"${aws_db_instance.usersDb.username}"},{"name":"db_password","value":"${aws_db_instance.usersDb.password}"}],
      "essential":true,
      "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "quarkus-backend",
                    "awslogs-region": "eu-central-1",
                    "awslogs-stream-prefix": "quarkus-container"
                }
            }
    }]
  TASK_DEFINITION

  requires_compatibilities =["FARGATE"]
  execution_role_arn = aws_iam_role.fargate-execution.arn
  task_role_arn = aws_iam_role.fargate-s3-role.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture = "X86_64"
  }
  network_mode = "awsvpc"

}

resource "aws_ecs_cluster" "quarkus-cluster" {
  name = "quarkus-cluster"
}
resource "aws_ecs_service" "quarkus-service" {
  name            = "quarkus-service"
  cluster         = aws_ecs_cluster.quarkus-cluster.id
  task_definition = aws_ecs_task_definition.quarkus-task.arn
  desired_count   = 1
  depends_on      = [aws_iam_role.fargate-s3-role,aws_iam_role.fargate-execution,aws_db_instance.usersDb,aws_lb_target_group.alb-tg-fargate]
  launch_type = "FARGATE"
  network_configuration {
    subnets =[aws_default_subnet.default-subnet-1.id,aws_default_subnet.default-subnet-2.id]
    assign_public_ip = true
    security_groups =[aws_security_group.fargate-sg.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.alb-tg-fargate.arn
    container_name   = "quarkus-backend"
    container_port   = 8080
  }


}
resource "aws_db_instance" "usersDb" {
  allocated_storage    = 20
  db_name              = "usersDb"
  engine               = "postgres"
  instance_class       = "db.t3.micro"
  username             = "enter username here"
  password             = "enter password here"
  port = 5432
  publicly_accessible  = true
  vpc_security_group_ids =[aws_security_group.postgres-sg.id]
  skip_final_snapshot = true
}