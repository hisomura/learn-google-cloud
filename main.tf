variable "project_id" {
  type = string
}

variable "project_name" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "default_region" {
  type = string
}

variable "default_zone" {
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
  region  = var.default_region
  zone    = var.default_zone
}

resource "google_dns_managed_zone" "production" {
  name     = replace(var.domain_name, ".", "-")
  dns_name = "${var.domain_name}."
}

resource "google_dns_record_set" "default" {
  name         = google_dns_managed_zone.production.dns_name
  managed_zone = google_dns_managed_zone.production.name
  type         = "A"
  rrdatas      = [google_compute_global_address.default.address]
  ttl          = 300
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
  name   = "${data.archive_file.default.output_md5}.zip"
  bucket = google_storage_bucket.default.name
  source = data.archive_file.default.output_path # Add path to the zipped function source code
}

resource "google_compute_region_network_endpoint_group" "function_neg" {
  name                  = "function-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.default_region
  cloud_function {
    function = google_cloudfunctions2_function.default.name
  }
}

resource "google_cloudfunctions2_function" "default" {
  name        = "function-v2"
  location    = var.default_region
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
  lifecycle {
    ignore_changes = [build_config["docker_repository"]]
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
  region = var.default_region
}

resource "google_compute_global_address" "default" {
  name = "my-test-static-ip-address"
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

resource "google_compute_target_http_proxy" "default" {
  name    = "http-proxy"
  url_map = google_compute_url_map.default.id
}


resource "google_compute_url_map" "default" {
  name            = "url-map"
  default_service = google_compute_backend_service.default.id

  host_rule {
    hosts        = [var.domain_name]
    path_matcher = "default"
  }

  path_matcher {
    name            = "default"
    default_service = google_compute_backend_service.default.id

    path_rule {
      paths   = ["/home"]
      service = google_compute_backend_service.default.id
      route_action {
        url_rewrite {
          path_prefix_rewrite = "/home"
        }
      }
    }

    path_rule {
      paths   = ["/login"]
      service = google_compute_backend_service.default.id
      route_action {
        url_rewrite {
          path_prefix_rewrite = "/hoge"
        }
      }
    }

    path_rule {
      paths   = ["/otel"]
      service = google_compute_backend_service.default.id
      route_action {
        url_rewrite {
          path_prefix_rewrite = "/"
        }
      }
    }
  }
}

resource "google_compute_backend_service" "default" {
  name                  = "backend-service"
  enable_cdn            = true
  load_balancing_scheme = "EXTERNAL_MANAGED"
  backend {
    group = google_compute_region_network_endpoint_group.function_neg.id
  }
}

resource "google_compute_global_forwarding_rule" "default" {
  name                  = "website-global-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.default.id
  ip_address            = google_compute_global_address.default.id
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "website-global-forwarding-rule-http"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.default.id
  ip_address            = google_compute_global_address.default.id
}
