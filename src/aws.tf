terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 2.13.0"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

resource "aws_instance" "app_server" {
  ami           = "ami-09e67e426f25ce0d7"
  instance_type = "t2.micro"
  key_name = "deployer-key"

  tags = {
    Name = "Plone in a Box™"
  }

  provisioner "remote-exec" {
    script = "StackScript"
    connection {
      type = "ssh"
      user = "ubuntu"
      host = aws_instance.app_server.public_ip
    }
  }
}

resource "aws_key_pair" "deployer" {
  key_name = "deployer-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCZv7tmokQijTEC2guA9YkYQb+BO9pUrMsIgDPkfhioO5HrGEhJmf8YKuXnFqZePpBSdUeKkamSJU5h1b7nZB1dTeR9Pi3zHdq5OFdw3sFLu7XtIqRyLq5m7nw+AboycKN5JTLedIJNmie4UpjLdt8ZK4q8MHa9DOCty9LaajtwQqWzabIMMLl6JUHS6Ux8GZe9xolYIdCVgyjQ2imRab9rOzskJPTfR+6/96QK+oNvM+b9VDVwhsvPhANb7Dgh7vqq8ZS5/xW725X0JNLnI4ckk+WuQVzKECLWKA9chGddd8dGvUHEsnK8zeSCTQe+lw4ATuYxcEwGo+vkgsKgfJG0KeSRtxOFfkW8woLjtITNa6OWJNKWUXn1jSm1yjwAEaFT9cmyNFUvdlHD42OqWnTjFR3mrD+vH2cfhJRRYMmdRkChS+lOR16E4CAQJSg18Fr8GQ9xy3PIlfj/DCjHbS3bCdU0VOrVaGhYt/446CFB0LdKcJKoFCuYY4CL4GMC0GDN9V2Fc/inAXa67AaEmKHSC39xu2rRf7/WOZXJTZPL2r8qoSjCVIy7cO8Zf1iKUcnj5OOssqFHRaoBHnEPAw4Wy+VNASJq3gpDFPFc+LbSuRBHalobNaiW5A5NM3l4OEZgNM+2WUpTBB6Ric/MhtLfFiNYRs85k+yCbReEgyby9Q== kimnguyen@Kims-MBP.new.rr.com"
}
