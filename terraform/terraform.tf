terraform {
  # Providers necesarios y sus versiones (~> permite parches y mejoras menores, no cambios mayores)
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
    # Se usa para empaquetar el codigo de la Lambda en un zip
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # Estado remoto en S3: asi el estado persiste entre ejecuciones de los
  # workflows y Terraform sabe que recursos existen (necesario para el destroy).
  backend "s3" {
    bucket = "angel-proyecto-cloud-bucket"
    key    = "backend/terraform.tfstate"
    region = "eu-north-1"
  }

  # Version minima de Terraform
  required_version = ">= 1.2"
}