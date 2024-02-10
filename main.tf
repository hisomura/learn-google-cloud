variable "project_id" {
  type = string
}

variable "project_name" {
  type = string
}

variable "domain_name" {
  type = string
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "us-central1"
  zone    = "us-central1-c"
}


resource "google_storage_bucket" "default" {
  name                        = "${var.project_name}-gcf-source" # Every bucket name must be globally unique
  location                    = "US"
  uniform_bucket_level_access = true
}

data "archive_file" "default" {
  type        = "zip"
  output_path = "${path.module}/build.zip"
  source_dir  = "${path.module}/build"
  excludes    = ["index.js.map"]
}

resource "google_storage_bucket_object" "object" {
  name   = "build.zip"
  bucket = google_storage_bucket.default.name
  source = data.archive_file.default.output_path # Add path to the zipped function source code
}

resource "google_cloudfunctions2_function" "default" {
  name        = "function-v2"
  location    = "us-central1"
  description = "a new function"

  build_config {
    runtime     = "nodejs20"
    entry_point = "helloWorld" # Set the entry point
    source {
      storage_source {
        bucket = google_storage_bucket.default.name
        object = google_storage_bucket_object.object.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256M"
    timeout_seconds    = 60
  }
}

resource "google_cloud_run_service_iam_member" "member" {
  location = google_cloudfunctions2_function.default.location
  service  = google_cloudfunctions2_function.default.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "function_uri" {
  value = google_cloudfunctions2_function.default.service_config[0].uri
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_address" "default" {
  name   = "my-test-static-ip-address"
  region = "us-central1"
}

resource "google_compute_managed_ssl_certificate" "default" {
  name = var.project_name

  managed {
    domains = [var.domain_name]
  }
}

resource "google_compute_target_https_proxy" "default" {
  name             = "https-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}


resource "google_compute_url_map" "default" {
  name = "url-map"
  default_url_redirect {
    host_redirect = "google.com"
    strip_query   = false
  }
}

resource "google_dns_managed_zone" "production" {
  name     = replace(var.domain_name, ".", "-")
  dns_name = "${var.domain_name}."
}

resource "google_dns_record_set" "default" {
  name         = google_dns_managed_zone.production.dns_name
  managed_zone = google_dns_managed_zone.production.name
  type         = "A"
  rrdatas      = [google_compute_address.default.address]
  ttl          = 300
}
