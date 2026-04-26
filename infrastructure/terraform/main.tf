provider "aws" {
  region = "us-east-1"
}

resource "aws_db_instance" "postgres" {
  allocated_storage    = 20
  engine               = "postgres"
  instance_class       = "db.t3.micro"
  name                 = "mydb"
  username             = "user"
  password             = "password"
  skip_final_snapshot  = true
}
